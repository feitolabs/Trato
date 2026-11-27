"""BE-2AC no Postgres local: bloqueio e rotina não se cruzam, o prazo não conclui o pedido do
cliente bloqueado e confirmar várias vezes ao mesmo tempo gera um só repasse."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

import psycopg
import pytest

from trato.agendador.executor import Adiada
from trato.api.medidas import aplicar, reverter
from trato.pedidos.estados import Acao
from trato.persistencia.medidas import Medida
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

from .test_ausencia_cliente_postgres import _post
from .test_compensacao_postgres import check_in, executor
from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_fluxo_postgres import foto
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)

pytestmark = pytest.mark.integracao
BLOQUEAR = "update public.usuarios set status = 'bloqueado' where id = %s"
REPASSES = (
    "select count(*) from public.repasses r join public.contratos c on c.id = r.contrato_id "
    "where c.pedido_id = %s"
)


def em_confirmacao(c) -> str:
    pid, _ = agendado(c)
    check_in(c, pid)
    visto = c.pagto[0].get(f"/v1/pedidos/{pid}", headers=c.token("cliente")).json()
    saida = {"foto_final": foto(), "codigo_conclusao": visto["codigo_conclusao"]}
    r = _post(c, "profissional", f"/v1/pedidos/{pid}/acoes/fazer_check_out", {"prova": saida})
    assert r.status_code == 200, r.text
    return pid


def rotina(c, pid) -> None:
    acao = AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"teste:{pid}", acao=Acao.CONCLUIR_POR_PRAZO
    )
    executor(c).executar(acao, datetime.now(UTC) + timedelta(days=10))


def estado(c, pid) -> str:
    return c.pagto[1].pedidos.obter(pid).estado.value


def liberar_conta(c) -> None:
    with c.local.admin() as con:
        con.execute(
            "update public.usuarios set status = 'ativo' where id = %s", (c.ids["cliente"],)
        )


def test_desbloqueio_reabre_a_janela_de_confirmacao(pg, equipe):  # noqa: F811
    contexto = pg.pagto[1]
    pid = em_confirmacao(pg)
    acao = AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"janela:{pid}", acao=Acao.CONCLUIR_POR_PRAZO
    )
    try:
        medida, _ = aplicar(
            contexto,
            Medida(
                usuario_id=pg.ids["cliente"],
                tipo="suspensao",
                motivo="Análise de segurança.",
                clausulas=("20.1",),
                inicio_em=contexto.agora(),
                efeito="Segue a cláusula 20.6.",
                como_contestar="Pelo atendimento.",
                aplicada_por=pg.ids["equipe1"],
            ),
        )
        assert reverter(contexto, medida, pg.ids["equipe1"])
        prazo = contexto.config.carregar().prazos_pedido.confirmacao_cliente
        fim = contexto.medidas.obter(medida.id).revertida_em + prazo
        with pytest.raises(Adiada, match="janela_reaberta"):
            executor(pg).executar(acao, fim - timedelta(seconds=1))
        assert estado(pg, pid) == "em_confirmacao"
        executor(pg).executar(acao, fim)
        assert estado(pg, pid) == "concluido"
        assert linhas(pg, REPASSES, (pid,)) == [(1,)]
    finally:
        liberar_conta(pg)


def test_bloqueio_em_andamento_faz_a_rotina_esperar_e_desistir(pg):  # noqa: F811
    pid = em_confirmacao(pg)
    erros: list[BaseException] = []

    def rodar():
        try:
            rotina(pg, pid)
        except BaseException as erro:  # noqa: BLE001 - conferido abaixo
            erros.append(erro)

    try:
        tarefa = threading.Thread(target=rodar)
        with pg.local.admin() as con:
            with con.transaction():
                con.execute(BLOQUEAR, (pg.ids["cliente"],))  # ainda sem commit
                tarefa.start()
                tarefa.join(1.0)
                assert tarefa.is_alive()  # a rotina espera o bloqueio terminar
        tarefa.join(20)
        assert [type(e) for e in erros] == [Adiada], erros
        assert estado(pg, pid) == "em_confirmacao"
        assert linhas(pg, REPASSES, (pid,)) == [(0,)]
    finally:
        liberar_conta(pg)


def test_rotina_que_leu_a_conta_segura_o_bloqueio_ate_o_fim(pg):  # noqa: F811
    contexto = pg.pagto[1]
    cliente = pg.ids["cliente"]
    try:
        with contexto.transacao():
            assert contexto.medidas.conta_bloqueada_travada(cliente) is False
            with pg.local.admin() as con, pytest.raises(psycopg.errors.LockNotAvailable):
                with con.transaction():
                    con.execute("set local lock_timeout = '500ms'")
                    con.execute(BLOQUEAR, (cliente,))
    finally:
        liberar_conta(pg)


def test_bloqueado_confirma_junto_e_gera_um_repasse(pg):  # noqa: F811
    pid = em_confirmacao(pg)
    try:
        with pg.local.admin() as con:
            con.execute(BLOQUEAR, (pg.ids["cliente"],))
        with pytest.raises(Adiada):
            rotina(pg, pid)
        visto = pg.pagto[0].get(f"/v1/pedidos/{pid}", headers=pg.token("cliente"))
        assert visto.status_code == 200, visto.text
        assert set(visto.json()["acoes_permitidas"]) == {"confirmar_conclusao", "abrir_disputa"}
        eu = pg.pagto[0].get("/v1/me", headers=pg.token("cliente"))
        assert eu.status_code == 403 and eu.json()["codigo"] == "conta_bloqueada"
        url = f"/v1/pedidos/{pid}/acoes/confirmar_conclusao"
        respostas = []
        tarefas = [
            threading.Thread(target=lambda: respostas.append(_post(pg, "cliente", url, None)))
            for _ in range(4)
        ]
        for t in tarefas:
            t.start()
        for t in tarefas:
            t.join()
        assert [r.status_code for r in respostas] == [200] * 4, [r.text for r in respostas]
        assert estado(pg, pid) == "concluido"
        assert linhas(pg, REPASSES, (pid,)) == [(1,)]
    finally:
        liberar_conta(pg)
