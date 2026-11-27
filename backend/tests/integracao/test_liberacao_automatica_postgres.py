"""TERMOS-BE-LIBERA no Postgres local: o agendador real (configuração publicada, registro no
banco) libera, compensa, não repete e respeita o que está em aberto."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from trato.agendador import Agendador
from trato.agendador.executor import FonteContexto, ids_ativos_postgres
from trato.agendador.registro import RegistroPostgres
from trato.agendador.trava import TravaEmMemoria
from trato.api.liberacao import relato_de_seguranca
from trato.financeiro.contestacoes import Contestacao, StatusContestacao
from trato.financeiro.ledger import a_liberar

from .test_ausencia_cliente_postgres import _no_passado, _post, justificar, painel, registrado
from .test_compensacao_postgres import (  # noqa: F401 - `avisos` é fixture
    PARTE,
    avisos,
    concluido,
    disponivel_do_profissional,
    executor,
    liberar,
    regresso,
    zerar,
)
from .test_contestacao_decisao_postgres import analisar, contestar, decidida
from .test_disputa_painel_postgres import em_disputa, equipe  # noqa: F401 - fixture
from .test_fluxo_postgres import foto  # noqa: F401
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    linhas,
    migrations_novas,
    pg,
)

pytestmark = pytest.mark.integracao
DEPOIS = timedelta(days=10)


@pytest.fixture(scope="module")
def publicado(equipe):  # noqa: F811
    """Publica `prazo_liberacao_dias` numa versão nova e cria a tabela do registro."""
    c = equipe
    migracoes = Path(__file__).resolve().parents[3] / "supabase" / "migrations"
    with c.local.admin() as con:
        if con.execute("select to_regclass('public.agendador_execucoes')").fetchone()[0] is None:
            (arquivo,) = migracoes.glob("*_notificacoes_dispositivos_agendador.sql")
            con.execute(arquivo.read_text(encoding="utf-8"))
        antiga = con.execute(
            "select id from public.config_versoes where status = 'vigente'"
        ).fetchone()[0]
        nova = con.execute(
            "insert into public.config_versoes (criada_por, motivo) values (%s, 'liberacao') "
            "returning id",
            (c.ids["equipe1"],),
        ).fetchone()[0]
        con.execute(
            "insert into public.config_definicoes (chave, descricao, unidade) values "
            "('prazo_liberacao_dias', 'Prazo de liberação', 'dias') on conflict (chave) do nothing"
        )
        con.execute(
            "insert into public.config_parametros (versao_id, chave, valor, escopo_tipo, "
            "escopo_id, escopo_texto) select %s, chave, valor, escopo_tipo, escopo_id, "
            "escopo_texto from public.config_parametros where versao_id = %s "
            "and chave <> 'prazo_liberacao_dias'",
            (nova, antiga),
        )
        con.execute(
            "insert into public.config_parametros (versao_id, chave, valor) "
            "values (%s, 'prazo_liberacao_dias', 5)",
            (nova,),
        )
        con.execute(
            "update public.config_versoes set status = 'aprovada', aprovada_por = %s where id = %s",
            (c.ids["equipe2"], nova),
        )
        con.execute(
            "update public.config_versoes set status = 'substituida' where id = %s", (antiga,)
        )
        con.execute("update public.config_versoes set status = 'vigente' where id = %s", (nova,))
    assert c.pagto[1].config.carregar().prazo_liberacao_dias == 5
    return c


def agendador(c, pid, depois=DEPOIS) -> Agendador:
    """Só o pedido do teste (o banco é dividido com os outros módulos)."""
    contexto = c.pagto[1]
    assert pid in ids_ativos_postgres(c.banco)()  # a consulta real o enxerga
    return Agendador(
        FonteContexto(contexto, lambda: [pid]),
        executor(c),
        RegistroPostgres(c.banco),
        TravaEmMemoria(),  # travas separadas: as duas instâncias disputam de verdade
        lambda: datetime.now(UTC) + depois,
    )


def a_liberar_de(c, pid) -> int:
    contexto = c.pagto[1]
    prof = contexto.pedidos.obter(pid).profissional_id
    return contexto.ledger.saldo_da_conta(a_liberar(prof), pid)


def repasses(c, pid) -> int:
    ((n,),) = linhas(
        c,
        "select count(*) from public.lancamentos l join public.contratos k on k.id = "
        "l.contrato_id where k.pedido_id = %s and l.chave_idempotencia like 'liberacao:%%'",
        (pid,),
    )
    return n


def marcadas(c, pid) -> int:
    ((n,),) = linhas(
        c,
        "select count(*) from public.agendador_execucoes where pedido_id = %s "
        "and tipo = 'liberar_saldo'",
        (pid,),
    )
    return n


def juntos(c, pid) -> list[int]:
    instancias = [agendador(c, pid) for _ in range(3)]
    barreira, falhas = threading.Barrier(len(instancias)), []

    def rodar(instancia) -> None:
        barreira.wait()
        falhas.append(instancia.rodar_uma_vez().falhas)

    fios = [threading.Thread(target=rodar, args=(i,)) for i in instancias]
    [f.start() for f in fios]
    [f.join(60) for f in fios]
    return falhas


def test_libera_e_compensa_uma_vez_com_tres_instancias(publicado, avisos):  # noqa: F811
    c = publicado
    zerar(c)
    antigo = concluido(c)
    liberar(c, antigo)
    divida = regresso(c, antigo)
    assert divida.resultado == "ok", divida
    url = f"/v1/admin/compensacoes/{divida.divida_id}/avisar"
    r = c.pagto[0].post(url, headers=c.token("med_a"))
    assert r.json()["avisado"] is True, r.text
    pid = concluido(c)
    assert agendador(c, pid, timedelta(days=4)).rodar_uma_vez().falhas == 0
    assert a_liberar_de(c, pid) > 0 and repasses(c, pid) == 0  # prazo de 5 dias ainda não venceu
    total = a_liberar_de(c, pid)
    assert juntos(c, pid) == [0, 0, 0]
    assert a_liberar_de(c, pid) == 0 and repasses(c, pid) == 1
    assert disponivel_do_profissional(c, pid) == total - PARTE
    assert c.pagto[1].compensacoes.obter(divida.divida_id).compensado_centavos == PARTE
    assert agendador(c, pid).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 1 and marcadas(c, pid) == 1
    zerar(c)


def test_cartao_contestado_segura_sem_marcar_e_libera_depois(publicado):
    c = publicado
    contexto = c.pagto[1]
    pid = concluido(c)
    agora = datetime.now(UTC)
    disputa = Contestacao(
        f"dp_{pid[:8]}", VALOR_ORCAMENTO, StatusContestacao.ABERTA, agora, agora, pedido_id=pid
    )
    contexto.contestacoes.salvar(disputa)
    assert agendador(c, pid).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 0 and marcadas(c, pid) == 0
    contexto.contestacoes.salvar(
        Contestacao(
            disputa.provedor_contestacao_id,
            VALOR_ORCAMENTO,
            StatusContestacao.GANHA,
            agora,
            agora,
            pedido_id=pid,
        )
    )
    assert agendador(c, pid).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 1 and marcadas(c, pid) == 1


def test_decisao_contestada_segura_ate_a_resposta(publicado):
    c = publicado
    pid = decidida(c)
    assert a_liberar_de(c, pid) > 0
    r = contestar(c, pid)
    assert r.status_code == 201, r.text
    assert agendador(c, pid).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 0
    assert analisar(c, r.json()["id"], "med_b", "mantida", None).status_code == 200
    assert agendador(c, pid).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 1 and a_liberar_de(c, pid) == 0


def test_decisao_nao_contestada_segura_ate_o_fim_do_prazo(publicado):
    c = publicado
    pid = decidida(c)
    # 6 dias: o prazo de liberação (5) venceu, o de contestar (5 dias úteis) ainda não
    assert agendador(c, pid, timedelta(days=6)).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 0 and marcadas(c, pid) == 0
    assert agendador(c, pid, timedelta(days=15)).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 1


def test_acordo_fecha_o_registro_no_banco_e_libera(publicado):
    c = publicado
    pid, _ = em_disputa(c)
    r = _post(c, "cliente", f"/v1/pedidos/{pid}/acoes/encerrar_disputa_por_acordo", None)
    assert r.status_code == 200, r.text
    sql = "select status, decisao from public.disputas where pedido_id = %s"
    assert [tuple(x) for x in linhas(c, sql, (pid,))] == [("acordo", None)]
    assert c.pagto[1].disputas.obter(pid).encerrada
    assert agendador(c, pid).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 1 and a_liberar_de(c, pid) == 0


def test_retencao_de_ausencia_cancelada_libera_depois_do_prazo(publicado):
    c = publicado
    pid, _ = registrado(c, fora_dos_7_dias=True)
    justificar(c, pid)
    retencao = {
        "retencao_centavos": VALOR_ORCAMENTO // 10,
        "retencao_justificativa": "Deslocamento comprovado.",
        "retencao_comprovantes": ["nota-1"],
    }
    r = painel(c, pid, **retencao)
    assert r.status_code == 200, r.text
    _no_passado(  # o prazo do cliente para contestar já passou
        c,
        "update public.cancelamentos_pedido set retencao_mostrada_cliente_em = "
        "retencao_mostrada_cliente_em - interval '15 days' where pedido_id = %s",
        (pid,),
    )
    r = painel(c, pid, rota="confirmar")
    assert r.status_code == 200, r.text
    assert a_liberar_de(c, pid) == VALOR_ORCAMENTO // 10
    assert agendador(c, pid, timedelta(days=1)).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 0 and marcadas(c, pid) == 0
    assert agendador(c, pid, timedelta(days=20)).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 1 and a_liberar_de(c, pid) == 0


def test_relato_de_seguranca_segura_ate_a_analise_terminar(publicado):
    c = publicado
    pid = concluido(c)
    with c.local.admin() as con:
        incidente = con.execute(
            "insert into public.incidentes_seguranca (relator_id, canal, tipo, pedido_id, "
            "cautela_ate) values (%s, 'app', 'acidente_dano', %s, now() + interval '23 hours') "
            "returning id",
            (c.ids["cliente"], pid),
        ).fetchone()[0]
    chamado = {"categoria": "seguranca", "assunto": "Dano", "texto": "Quebrou.", "pedido_id": pid}
    r = _post(c, "cliente", "/v1/sac/chamados", chamado)
    assert r.status_code in (200, 201), r.text
    c.pagto[1].denuncias.registrar(
        c.ids["profissional"], pid, "denuncia_chat", "alta", "relato", datetime.now(UTC)
    )

    def segurado(motivo: str) -> None:
        assert agendador(c, pid).rodar_uma_vez().falhas == 0
        assert repasses(c, pid) == 0 and marcadas(c, pid) == 0, motivo
        assert relato_de_seguranca(c.pagto[1], pid) == motivo

    segurado("incidente")
    with c.local.admin() as con:
        con.execute(
            "update public.incidentes_seguranca set status = 'encerrado', encerrado_em = now(), "
            "responsavel_id = %s, desfecho = 'apurado' where id = %s",
            (c.ids["adm_a"], incidente),
        )
    segurado("chamado_seguranca")
    with c.local.admin() as con:
        con.execute(
            "update public.chamados set status = 'encerrado', encerrado_em = now(), "
            "responsavel_id = %s where pedido_id = %s",
            (c.ids["adm_a"], pid),
        )
    segurado("denuncia_grave")
    with c.local.admin() as con:
        con.execute("update public.alertas_risco set resolvido = true where pedido_id = %s", (pid,))
    assert agendador(c, pid).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 1 and a_liberar_de(c, pid) == 0
