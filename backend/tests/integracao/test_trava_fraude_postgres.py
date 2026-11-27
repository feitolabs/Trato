"""BE-1B no Postgres local (migration 20261127001000): rota de risco, limite com dois
pedidos ao mesmo tempo, criação x liberação e banco sem as colunas novas."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path

import psycopg
import pytest

from trato.agendador.executor import Adiada
from trato.api.medidas import aplicar
from trato.financeiro.ledger import a_liberar
from trato.persistencia.medidas import Medida

from .test_ausencia_cliente_postgres import _post
from .test_compensacao_postgres import concluido, liberar
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_medidas_postgres import limpar, status
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)

RISCO = "/v1/admin/risco"
LINHAS = (
    "select motivo_fraude, limite_retencao_centavos, fim_em - inicio_em from public.medidas_conta "
    "where usuario_id = %s and tipo = 'trava_saque' order by criado_em"
)


def corpo(c, **extra):
    return {"usuario_id": c.ids["profissional"], "motivo": "Fraude em apuração."} | extra


def total_a_liberar(c) -> int:
    return c.pagto[1].ledger.saldo_da_conta(a_liberar(c.ids["profissional"]))


def trava(c, limite) -> Medida:
    agora = datetime.now(UTC)
    return Medida(
        usuario_id=c.ids["profissional"],
        tipo="trava_saque",
        motivo=f"Fraude em apuração ({limite}).",
        clausulas=("20.6",),
        inicio_em=agora,
        fim_em=agora + timedelta(days=30),
        efeito="Segue a cláusula 20.6.",
        como_contestar="Pelo atendimento.",
        aplicada_por=c.ids["adm_a"],
        motivo_fraude=True,
        limite_retencao_centavos=limite,
    )


def test_rota_de_risco_grava_e_diz_a_verdade(pg, equipe):  # noqa: F811
    limpar(pg)
    quem = pg.ids["profissional"]
    try:
        url = f"{RISCO}/travar-saque"
        assert _post(pg, "adm_a", url, corpo(pg, motivo_fraude=True)).status_code == 422
        comum = _post(pg, "adm_a", url, corpo(pg))
        assert "NÃO são bloqueados" in comum.json()["mensagem"], comum.text
        pedido = corpo(pg, motivo_fraude=True, limite_retencao_centavos=5_000)
        respostas = []
        threads = [
            threading.Thread(target=lambda: respostas.append(_post(pg, "adm_a", url, pedido)))
            for _ in range(4)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert [r.status_code for r in respostas] == [200] * 4, [r.text for r in respostas]
        texto = respostas[0].json()["mensagem"]
        assert "liberação no livro fica adiada" in texto and "R$ 50,00" in texto
        assert "Stripe continua sem trava" in texto and status(pg) == "restrito"
        assert linhas(pg, LINHAS, (quem,)) == [
            (False, None, None),
            (True, 5_000, timedelta(days=30)),
        ]
        r = _post(pg, "adm_a", f"{RISCO}/destravar-saque", corpo(pg))
        assert r.status_code == 200, r.text
        assert pg.pagto[1].medidas.retencao_por_fraude(quem, datetime.now(UTC)) is None
    finally:
        limpar(pg)


def test_dois_pedidos_ao_mesmo_tempo_retem_exatamente_o_limite(pg, equipe):  # noqa: F811
    limpar(pg)
    try:
        primeiro, segundo = concluido(pg), concluido(pg)
        contexto = pg.pagto[1]
        saldo = contexto.ledger.saldos_pedido(primeiro, pg.ids["profissional"]).a_liberar
        antes = total_a_liberar(pg)
        limite = antes - saldo - 100  # só um pedido inteiro e 100 centavos podem sair
        aplicar(contexto, trava(pg, limite))
        erros = []

        def rodar(pid):
            try:
                liberar(pg, pid)
            except BaseException as erro:  # noqa: BLE001 - conferido abaixo
                erros.append(erro)

        threads = [threading.Thread(target=rodar, args=(p,)) for p in (primeiro, segundo)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert all(isinstance(e, Adiada) for e in erros), erros
        assert total_a_liberar(pg) == limite
    finally:
        limpar(pg)


def test_criacao_em_andamento_segura_a_liberacao(pg, equipe):  # noqa: F811
    limpar(pg)
    try:
        pid = concluido(pg)
        quem = pg.ids["profissional"]
        contexto = pg.pagto[1]
        antes = total_a_liberar(pg)
        erros = []

        def rodar():
            try:
                liberar(pg, pid, timedelta(seconds=30))
            except BaseException as erro:  # noqa: BLE001 - conferido abaixo
                erros.append(erro)

        tarefa = threading.Thread(target=rodar)
        with contexto.transacao():
            aplicar(contexto, trava(pg, antes))  # criada e ainda sem commit
            tarefa.start()
            tarefa.join(1.0)
            assert tarefa.is_alive()
        tarefa.join(20)
        assert [type(e) for e in erros] == [Adiada], erros
        assert total_a_liberar(pg) == antes
        with contexto.transacao():  # e a liberação em andamento segura a criação
            contexto.medidas.retencao_por_fraude(quem, datetime.now(UTC))
            with pg.local.admin() as con, pytest.raises(psycopg.errors.LockNotAvailable):
                with con.transaction():
                    con.execute("set local lock_timeout = '500ms'")
                    con.execute(
                        "select 1 from public.usuarios where id = %s for no key update", (quem,)
                    )
    finally:
        limpar(pg)


def test_sem_as_colunas_novas_nao_bloqueia(pg, equipe):  # noqa: F811
    limpar(pg)
    raiz = Path(__file__).resolve().parents[3] / "supabase"
    nome = "20261127001000_trava_saque_fraude"
    try:
        with pg.local.admin() as con:
            con.execute((raiz / "rollback" / f"{nome}_rollback.sql").read_text("utf-8"))
        try:
            contexto = pg.pagto[1]
            quem = pg.ids["profissional"]
            r = _post(
                pg,
                "adm_a",
                f"{RISCO}/travar-saque",
                corpo(pg, motivo_fraude=True, limite_retencao_centavos=5_000),
            )
            assert r.status_code == 200, r.text
            assert "NÃO são bloqueados" in r.json()["mensagem"]
            assert contexto.medidas.retencao_por_fraude(quem, datetime.now(UTC)) is None
            assert contexto.medidas.prazo_maximo_trava_fraude_dias() == 30
            pid = concluido(pg)
            liberar(pg, pid, timedelta(seconds=30))
            assert contexto.ledger.saldos_pedido(pid, quem).a_liberar == 0
        finally:
            limpar(pg)
            with pg.local.admin() as con:
                con.execute((raiz / "migrations" / f"{nome}.sql").read_text("utf-8"))
    finally:
        limpar(pg)
