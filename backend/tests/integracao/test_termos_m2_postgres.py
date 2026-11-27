"""TERMOS-M2 no Postgres LOCAL descartável: conclusão por prazo pelo agendador montado, revisão
e reenvio de ordem de estorno e reembolso com o parcelado passando pelos gatilhos do banco.
Provedor falso. Nunca toca no Supabase."""

# ruff: noqa: F811 - os parâmetros com nome de fixture importada são do pytest

from __future__ import annotations

import uuid
from dataclasses import replace
from datetime import UTC, date, datetime, timedelta

import pytest

from trato.financeiro.ledger import (
    CUSTODIA,
    TAXA_TRATO,
    Livro,
    estornar_pedido,
    registrar_cobranca,
    separar_custo_parcelamento,
)
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import (
    Aditivo,
    ConfigPagamento,
    EstadoAditivo,
    EstadoCobranca,
)
from trato.pagamentos.parcelamento import ConfigParcelamento
from trato.pagamentos.provedor import ErroProvedor, TipoEvento
from trato.pedidos.estados import Acao
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

from .pg_local import RAIZ
from .test_ausencia_reembolso_postgres import ausencia, montar, ordens, pago_e_agendado  # noqa: F401
from .test_dinheiro_postgres import VALOR as VALOR_DO_ORCAMENTO
from .test_dinheiro_postgres import ate_em_confirmacao, contratar
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    cobrar,
    estado_pedido,
    linhas,
    migrations_novas,
    pedido_aceito,
    pg,
    webhook,
)

pytestmark = pytest.mark.integracao


def test_conclusao_por_prazo_grava_repasse_uma_vez_no_banco(pg, montar):
    pid = ate_em_confirmacao(pg)  # pagamento, agenda, check-in e check-out reais
    contexto = pg.pagto[1]
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR_DO_ORCAMENTO
    executor = montar()
    acao = AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"prazo:{pid}", acao=Acao.CONCLUIR_POR_PRAZO
    )
    depois = datetime.now(UTC) + timedelta(days=30)
    executor.executar(acao, depois)
    executor.executar(acao, depois)
    assert estado_pedido(pg, pid) == "concluido"
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    (repasse,) = contexto.repasses.do_pedido(pid)
    assert repasse.gatilho == "prazo" and repasse.valor_liquido_centavos == VALOR_DO_ORCAMENTO


def test_estorno_por_fora_vira_revisao_no_banco_e_resposta_perdida_confere(
    pg,
    montar,
    monkeypatch,
):
    provedor, contexto, servico = pg.pagto[2].provedor, pg.pagto[1], pg.pagto[2]
    pid, cobranca, depois = pago_e_agendado(pg)
    executor = montar()
    original = provedor.estornar

    def resposta_perdida(*args):
        original(*args)
        raise ErroProvedor("sem resposta")

    with monkeypatch.context() as m:
        m.setattr(provedor, "estornar", resposta_perdida)
        executor.executar(ausencia(pid), depois)
    assert [o.estado for o in ordens(pg, pid)] == ["pendente"]
    provedor.esquecer_chaves()
    assert executor.reenviar_estornos(datetime.now(UTC) + timedelta(hours=48)) >= 1
    assert [o.estado for o in ordens(pg, pid)] == ["enviada"]
    assert sum(e.valor_centavos for e in provedor.estornos_da_cobranca(cobranca)) == VALOR_ORCAMENTO

    pid2, cobranca2, depois2 = pago_e_agendado(pg)
    with monkeypatch.context() as m:

        def fora_do_ar(*args):
            raise ErroProvedor("fora do ar")

        m.setattr(provedor, "estornar", fora_do_ar)
        executor.executar(ausencia(pid2), depois2)
    provedor.estornar_por_fora(cobranca2, 1_000)
    for _ in range(2):
        executor.reenviar_estornos(datetime.now(UTC) + timedelta(hours=48))
    assert [o.estado for o in ordens(pg, pid2)] == ["pendente"]
    achadas = linhas(
        pg,
        "select erro from public.eventos_webhook where tipo = 'trato.ordem_estorno.revisao' "
        "and payload #>> '{data,object,metadata,cobranca_id}' = %s",
        (cobranca2,),
    )
    assert len(achadas) == 1 and achadas[0][0].startswith("revisar:")
    assert contexto is not None and servico is not None


def test_reembolso_com_parcelamento_passa_pelos_gatilhos_do_banco(pg):
    contexto = pg.pagto[1]
    pid = contratar(pg)
    agora = datetime.now(UTC)
    chave = f"cob/{uuid.uuid4().hex}"
    livro = Livro()
    registrar_cobranca(livro, pid, 94_500, chave, agora)
    separar_custo_parcelamento(livro, pid, 4_500, chave, agora)
    contexto.ledger.lancar_varios(livro.lancamentos)

    volta = Livro()
    volta.lancar_varios(contexto.ledger.lancamentos(pid))
    antes = len(volta.lancamentos)
    estornar_pedido(volta, pid, 94_500, f"{chave}/est", agora, incluir_custo=True)
    contexto.ledger.lancar_varios(volta.lancamentos[antes:])

    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    assert contexto.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0


def test_contestacao_perdida_nao_e_estornada_de_novo_no_banco(pg, montar):
    http, contexto, servico = pg.pagto
    pid, cobranca, _ = pago_e_agendado(pg)
    perdido = 30_000
    r = webhook(
        pg,
        TipoEvento.CONTESTACAO,
        cobranca,
        valor_centavos=perdido,
        status_contestacao="lost",
        objeto_id=f"dp_{uuid.uuid4().hex}",
        evento_id=f"evt_{uuid.uuid4().hex}",
    )
    assert r.status_code == 200, r.text
    assert [c.valor_centavos for c in contexto.contestacoes.perdidas_do_pedido(pid)] == [perdido]
    assert servico.cobrancas.obter(cobranca).estornado_centavos == perdido

    r = http.post(
        f"/v1/pedidos/{pid}/acoes/cancelar",
        json={"prova": {"motivo": "desisti"}},
        headers=pg.token("cliente"),
    )
    if r.status_code != 200:
        r = http.post(
            f"/v1/pedidos/{pid}/acoes/cancelar",
            json={"motivo": "desisti"},
            headers=pg.token("cliente"),
        )
    assert r.status_code == 200, r.text
    assert [o.valor_centavos for o in ordens(pg, pid)] == [VALOR_ORCAMENTO - perdido]
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    # a contestação entrou no ledger (antes: só ia para revisão, por causa do id sem hífen)
    assert any(x.chave.startswith("contest/") for x in contexto.ledger.lancamentos(pid))


def test_sem_a_tabela_de_contestacoes_a_consulta_nao_quebra_o_reembolso(pg, montar):
    pid, _, depois = pago_e_agendado(pg)
    executor = montar()
    with pg.local.admin() as con:
        con.execute("alter table public.contestacoes rename to contestacoes_x")
    try:
        executor.executar(ausencia(pid), depois)
    finally:
        with pg.local.admin() as con:
            con.execute("alter table public.contestacoes_x rename to contestacoes")
    assert estado_pedido(pg, pid) == "cancelado"
    assert [o.valor_centavos for o in ordens(pg, pid)] == [VALOR_ORCAMENTO]


def test_aditivo_pago_depois_da_ausencia_volta_inteiro_no_banco(pg, montar):
    _, contexto, servico = pg.pagto
    pid, _, depois = pago_e_agendado(pg)
    agora = datetime.now(UTC)
    proposto = Aditivo(uuid.uuid4().hex, pid, "Peça extra", 5_000, EstadoAditivo.PROPOSTO, agora)
    servico.aditivos.salvar(proposto)
    aprovado = replace(proposto, estado=EstadoAditivo.APROVADO, aprovado_em=agora)
    servico.aditivos.salvar(aprovado)
    extra = servico.cobrar(
        contexto, contexto.pedidos.obter(pid), 5_000, MeioPagamento.PIX, aprovado.id
    )

    montar().executar(ausencia(pid), depois)
    assert servico.cobrancas.obter(extra.id).status is EstadoCobranca.CANCELADA
    assert ("cancelar_cobranca", extra.id) in servico.provedor.chamadas

    servico.provedor.marcar_paga(extra.id)  # o provedor aceitou mesmo assim
    for _ in range(2):
        r = webhook(
            pg, TipoEvento.PAGAMENTO_CONFIRMADO, extra.id, evento_id=f"evt_{uuid.uuid4().hex}"
        )
        assert r.status_code == 200, r.text
    assert servico.cobrancas.obter(extra.id).status is EstadoCobranca.DEVOLVIDA
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    assert [e.valor_centavos for e in servico.provedor.estornos_da_cobranca(extra.id)] == [5_000]


def pagar_parcelado(pg, monkeypatch) -> tuple[str, int]:
    http, contexto, servico = pg.pagto
    config = ConfigPagamento(10**9, parcelamento=ConfigParcelamento({3: 500}))
    monkeypatch.setattr(servico, "config", lambda: config)
    pid = pedido_aceito(pg)
    contexto.usuarios.registrar_dados_privados(pg.ids["cliente"], "52998224725", None)
    r = http.post(
        f"/v1/pedidos/{pid}/cobranca",
        json={"meio": "cartao", "parcelas": 3},
        headers=pg.token("cliente"),
    )
    assert r.status_code == 201, r.text
    cob = r.json()
    cobrado = cob["valor_centavos"]
    assert cobrado > VALOR_ORCAMENTO
    servico.provedor.marcar_paga(cob["id"])
    r = webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, cob["id"], evento_id=f"evt_{uuid.uuid4().hex}")
    assert r.status_code == 200, r.text
    return pid, cobrado


def test_profissional_cancela_parcelado_e_o_custo_volta_no_banco(pg, monkeypatch):
    http, contexto, servico = pg.pagto
    pid, cobrado = pagar_parcelado(pg, monkeypatch)

    url = f"/v1/pedidos/{pid}/acoes/cancelar"
    r = http.post(url, json={"prova": {"motivo": "não vou"}}, headers=pg.token("profissional"))
    if r.status_code != 200:
        r = http.post(url, json={"motivo": "não vou"}, headers=pg.token("profissional"))
    assert r.status_code == 200, r.text
    assert [o.valor_centavos for o in ordens(pg, pid)] == [cobrado]
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    assert contexto.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0


def test_vincular_sem_sessao_no_banco_so_conta_nova_que_nunca_entrou(pg):
    c = pg
    contexto = c.pagto[1]
    janela = timedelta(minutes=60)
    with c.local.admin() as con:  # função de login (migration que o banco de teste não aplica)
        if con.execute(
            "select to_regprocedure('privado.confirmar_email_do_usuario(uuid, text)') is null"
        ).fetchone()[0]:
            # o `auth.users` de teste não tem os metadados do Supabase
            con.execute("alter table auth.users add column if not exists raw_user_meta_data jsonb")
            sql = RAIZ / "supabase" / "migrations" / "20261101120000_login_cpf_telefone.sql"
            con.execute(sql.read_text(encoding="utf-8"))

    def conta(acesso: bool) -> tuple[str, str]:
        uid, email = str(uuid.uuid4()), f"{uuid.uuid4().hex}@exemplo.test"
        with c.local.admin() as con:
            con.execute("insert into auth.users (id, email) values (%s, %s)", (uid, email))
            if acesso:
                con.execute("update auth.users set last_sign_in_at = now() where id = %s", (uid,))
        return uid, email

    usuarios = contexto.usuarios
    agora = datetime.now(UTC)
    nova, email = conta(False)
    assert usuarios.pode_vincular_sem_sessao(nova, email, agora, janela)
    assert not usuarios.pode_vincular_sem_sessao(nova, "outra@exemplo.test", agora, janela)
    assert usuarios.data_nascimento(nova) is None
    usuarios.vincular_cadastro(nova, email, "Nova", None, None, date(1990, 1, 1))
    assert usuarios.data_nascimento(nova) == date(1990, 1, 1)
    depois = agora + janela + timedelta(minutes=5)
    assert not usuarios.pode_vincular_sem_sessao(nova, email, depois, janela)
    usada, email_usada = conta(True)
    assert not usuarios.pode_vincular_sem_sessao(usada, email_usada, agora, janela)


def test_cliente_cancela_parcelado_no_banco_e_o_custo_volta(pg, monkeypatch):
    http, contexto, servico = pg.pagto
    pid, cobrado = pagar_parcelado(pg, monkeypatch)
    url = f"/v1/pedidos/{pid}/acoes/cancelar"
    r = http.post(url, json={"prova": {"motivo": "desisti"}}, headers=pg.token("cliente"))
    if r.status_code != 200:
        r = http.post(url, json={"motivo": "desisti"}, headers=pg.token("cliente"))
    assert r.status_code == 200, r.text
    assert [o.valor_centavos for o in ordens(pg, pid)] == [cobrado]
    assert contexto.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0
