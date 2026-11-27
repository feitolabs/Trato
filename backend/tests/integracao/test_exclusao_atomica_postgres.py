"""BE-ENCERRA-FIM no Postgres local: checar o dinheiro e anonimizar numa transação só
(Termos 4.8), com dinheiro entrando ao mesmo tempo."""

from __future__ import annotations

import threading
import uuid
from dataclasses import replace
from datetime import UTC, datetime, timedelta

import psycopg
import pytest

from trato.api.auth import PapelUsuario, Usuario
from trato.api.repositorios import Contrato
from trato.lgpd.config import obter_config_lgpd
from trato.lgpd.repositorios import PedidoExclusao
from trato.lgpd.servico import ErroLgpd, ServicoLgpd
from trato.persistencia.erros import RegraDoBanco
from trato.persistencia.lgpd import criar_repositorios_lgpd_postgres

from .pg_local import RAIZ
from .test_fluxo_postgres import abrir_pedido, enviar_orcamento
from .test_guarda_tratinhos_postgres import pessoa
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pedido_aceito,
    pg,
)

COPIAR = (
    "insert into public.{tabela} overriding system value select (jsonb_populate_record(t, "
    "%s::jsonb)).* from public.{tabela} t where t.{chave} = %s"
)
STATUS = "select status from public.usuarios where id = %s"


@pytest.fixture(scope="module", autouse=True)
def aparelhos(pg):  # noqa: F811
    """A anonimização apaga `dispositivos_push`, fora da lista de migrations do banco local."""
    with pg.local.admin() as con:
        if con.execute("select to_regclass('public.dispositivos_push')").fetchone()[0] is None:
            (arquivo,) = (RAIZ / "supabase" / "migrations").glob(
                "*_notificacoes_dispositivos_agendador.sql"
            )
            con.execute(arquivo.read_text(encoding="utf-8"))


class SemAuditoria:
    def auditar(self, *_, **__) -> None:
        pass


def servico(c) -> ServicoLgpd:
    repos = criar_repositorios_lgpd_postgres(c.banco)
    return ServicoLgpd(obter_config_lgpd(), repos, SemAuditoria())


def cliente_com_pedido_encerrado(c) -> tuple[str, str]:
    """Conta própria, com um pedido concluído e sem dinheiro (cópia de um contrato real)."""
    origem = pedido_aceito(c)
    uid, pid, orc, ctr = pessoa(c), *(str(uuid.uuid4()) for _ in range(3))
    ((contrato, orcamento),) = linhas(
        c, "select id, orcamento_id from public.contratos where pedido_id = %s", (origem,)
    )
    numero = uuid.uuid4().int % 1_000_000_000
    trocas = (
        ("pedidos", "id", origem, {"id": pid, "cliente_id": uid, "status": "concluido"}),
        ("orcamentos", "id", orcamento, {"id": orc, "pedido_id": pid}),
        (
            "contratos",
            "id",
            contrato,
            {"id": ctr, "pedido_id": pid, "cliente_id": uid, "orcamento_id": orc},
        ),
    )
    with c.local.admin() as con:
        con.execute("set session_replication_role = replica")  # só para montar o cenário
        tem_numero = con.execute(
            "select 1 from information_schema.columns where table_name = 'pedidos' "
            "and column_name = 'numero'"
        ).fetchone()
        for tabela, chave, de, novos in trocas:
            if tabela == "pedidos" and tem_numero:
                novos = novos | {"numero": numero}
            sql = COPIAR.format(tabela=tabela, chave=chave)
            con.execute(sql, (psycopg.types.json.Jsonb(novos), de))
    return uid, pid


def agendar(c, uid) -> PedidoExclusao:
    agora = datetime.now(UTC)
    pedido = PedidoExclusao(
        str(uuid.uuid4()),
        uid,
        "agendada",
        agora - timedelta(days=8),
        executar_apos=agora - timedelta(days=1),
    )
    criar_repositorios_lgpd_postgres(c.banco).exclusoes.salvar(pedido)
    return pedido


def excluir(s, pedido):
    return s._excluir_sem_pendencia(pedido, datetime.now(UTC))


def estornar(con, pid) -> None:
    """Ordem de estorno pendente no contrato (dinheiro a devolver ao cliente)."""
    ctr = con.execute(
        "select id, cliente_id from public.contratos where pedido_id = %s", (pid,)
    ).fetchone()
    pagamento = con.execute(
        "insert into public.pagamentos (contrato_id, pagador_id, tipo, meio, valor_centavos, "
        "status, stripe_payment_intent_id, chave_idempotencia, confirmado_em) values "
        "(%s, %s, 'saldo', 'pix', 1000, 'confirmado', %s, %s, now()) returning id",
        (ctr[0], ctr[1], f"pi_{uuid.uuid4().hex}", f"cob/{uuid.uuid4().hex}"),
    ).fetchone()
    con.execute(
        "insert into public.ordens_estorno (contrato_id, pagamento_id, valor_centavos, estado, "
        "chave_idempotencia) values (%s, %s, 1000, 'pendente', %s)",
        (ctr[0], pagamento[0], f"est/{uuid.uuid4().hex}"),
    )


def test_dinheiro_que_entra_durante_a_checagem_segura_a_exclusao(pg):  # noqa: F811
    uid, pid = cliente_com_pedido_encerrado(pg)
    s, pedido = servico(pg), agendar(pg, uid)
    resultados: list = []
    tarefa = threading.Thread(target=lambda: resultados.append(excluir(s, pedido)))
    with pg.local.admin() as con, con.transaction():
        estornar(con, pid)  # ainda sem commit: segura o contrato
        tarefa.start()
        tarefa.join(1.5)
        assert tarefa.is_alive(), resultados  # a exclusão espera o dinheiro gravar
    tarefa.join(20)
    ((pendencias, resumo),) = resultados
    assert any("reembolso" in p for p in pendencias) and resumo == {}, pendencias
    assert linhas(pg, STATUS, (uid,))[0][0] != "anonimizado"


def test_durante_a_anonimizacao_o_dinheiro_novo_espera(pg):  # noqa: F811
    uid, pid = cliente_com_pedido_encerrado(pg)
    s, pedido = servico(pg), agendar(pg, uid)
    travado, seguir = threading.Event(), threading.Event()
    original = s._r.fonte.anonimizar

    def devagar(usuario_id):
        travado.set()  # já checou as pendências
        assert seguir.wait(20)
        return original(usuario_id)

    s._r.fonte.anonimizar = devagar
    resultados: list = []
    tarefa = threading.Thread(target=lambda: resultados.append(excluir(s, pedido)))
    tarefa.start()
    try:
        assert travado.wait(20)
        for entra in (
            lambda con: estornar(con, pid),
            lambda con: con.execute(
                "select 1 from public.contratos where pedido_id = %s for update", (pid,)
            ),
            lambda con: con.execute(
                "select 1 from public.pedidos where id = %s for update", (pid,)
            ),
        ):
            with pg.local.admin() as con, pytest.raises(psycopg.errors.LockNotAvailable):
                with con.transaction():
                    con.execute("set local lock_timeout = '500ms'")
                    entra(con)
    finally:
        seguir.set()
        tarefa.join(20)
    ((pendencias, resumo),) = resultados
    assert pendencias == [] and "anonimizado" in resumo
    assert linhas(pg, STATUS, (uid,))[0][0] == "anonimizado"


def test_duas_rodadas_ao_mesmo_tempo_anonimizam_uma_vez(pg):  # noqa: F811
    uid, _ = cliente_com_pedido_encerrado(pg)
    pedido = agendar(pg, uid)
    resultados: list = []
    tarefas = [
        threading.Thread(target=lambda: resultados.append(excluir(servico(pg), pedido)))
        for _ in range(4)
    ]
    for t in tarefas:
        t.start()
    for t in tarefas:
        t.join(30)
    assert len(resultados) == 4 and sum(r is not None for r in resultados) == 1, resultados


def situacao(c, pedido) -> str:
    sql = "select status from public.lgpd_pedidos_exclusao where id = %s"
    return linhas(c, sql, (pedido.id,))[0][0]


def test_cancelar_no_meio_da_exclusao_espera_e_e_recusado(pg):  # noqa: F811
    uid, _ = cliente_com_pedido_encerrado(pg)
    s, pedido = servico(pg), agendar(pg, uid)
    travado, seguir = threading.Event(), threading.Event()
    original = s._r.fonte.anonimizar

    def devagar(usuario_id):
        travado.set()
        assert seguir.wait(20)
        return original(usuario_id)

    s._r.fonte.anonimizar = devagar
    feitos: list = []
    recusas: list = []

    def cancelar():
        try:
            servico(pg).cancelar_exclusao(Usuario(uid, PapelUsuario.CLIENTE))
            recusas.append(None)
        except ErroLgpd as erro:
            recusas.append(erro.status)

    exclui = threading.Thread(target=lambda: feitos.append(excluir(s, pedido)))
    cancela = threading.Thread(target=cancelar)
    exclui.start()
    try:
        assert travado.wait(20)
        cancela.start()
        cancela.join(1.5)
        assert cancela.is_alive(), recusas  # leu o pedido ainda agendado e espera para gravar
    finally:
        seguir.set()
        exclui.join(20)
        cancela.join(20)
    assert recusas == [409] and feitos[0][0] == []
    assert situacao(pg, pedido) == "concluida"
    assert linhas(pg, STATUS, (uid,))[0][0] == "anonimizado"


def test_cancelado_antes_nao_anonimiza_e_gravacao_atrasada_nao_muda(pg):  # noqa: F811
    uid, _ = cliente_com_pedido_encerrado(pg)
    s, pedido = servico(pg), agendar(pg, uid)
    s.cancelar_exclusao(Usuario(uid, PapelUsuario.CLIENTE))
    assert excluir(s, pedido) is None
    assert situacao(pg, pedido) == "cancelada"
    assert linhas(pg, STATUS, (uid,))[0][0] != "anonimizado"
    repo = criar_repositorios_lgpd_postgres(pg.banco).exclusoes
    assert repo.salvar(replace(pedido, status="concluida")) is False
    outro = agendar(pg, uid)
    assert excluir(s, outro)[0] == []
    assert repo.salvar(replace(outro, status="cancelada")) is False
    assert situacao(pg, outro) == "concluida"


def test_conta_excluida_nao_ganha_contrato(pg):  # noqa: F811
    pid = abrir_pedido(pg)
    oid = enviar_orcamento(pg, pid)
    cliente = pg.ids["cliente"]
    mudar = "update public.usuarios set status = %s where id = %s"
    with pg.local.admin() as con:
        con.execute(mudar, ("anonimizado", cliente))
    try:
        novo = Contrato(pid, oid, pg.ids["profissional"], 1, aceito_em=datetime.now(UTC))
        with pytest.raises(RegraDoBanco, match="excluída"):
            pg.pagto[1].contratos.salvar(novo)
    finally:
        with pg.local.admin() as con:
            con.execute(mudar, ("ativo", cliente))
