"""BE-CHECKOUT-SEM-CODIGO-57-FASE2 no Postgres local (migrations 20261127230000 e 20261128010000):
decisão liberar/estornar, idempotência, trigger de imutabilidade, bloqueios após resposta/decisão/
disputa, permissão e alçada."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import uuid
from datetime import timedelta

import psycopg
import pytest

from trato.api.checkout_sem_codigo import CONFIRMOU
from trato.pedidos.estados import Estado as E

from .test_compensacao_postgres import check_in
from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

URL_FILA = "/v1/admin/checkout-sem-codigo"
MOTIVO = "Provas do pedido conferidas pelo analista."


def _checkout_sem_codigo(pg, pid: str):
    http, contexto, _ = pg.pagto
    agora = contexto.agora().isoformat()
    return http.post(
        f"/v1/pedidos/{pid}/acoes/fazer_check_out",
        json={
            "prova": {
                "foto_final": {"arquivo_id": f"foto-{pid}", "tirada_em": agora},
                "localizacao": {"latitude": -19.9167, "longitude": -43.9345},
                "sem_codigo": True,
                "justificativa": "Cliente saiu antes do término do serviço.",
            }
        },
        headers=pg.token("profissional"),
    )


def _limpar(pg):
    with pg.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.checkout_sem_codigo_casos")


@pytest.fixture
def ambiente_f2(pg, equipe):
    _limpar(pg)
    yield pg
    _limpar(pg)


def _novo_caso(c):
    http, contexto, _ = c.pagto
    pid, _ = agendado(c)
    check_in(c, pid)
    r = _checkout_sem_codigo(c, pid)
    assert r.status_code == 200, r.text
    casos = [x for x in contexto.checkout_sem_codigo.em_aberto() if x.pedido_id == pid]
    assert len(casos) == 1
    caso = casos[0]
    if caso.contatado_em is None:
        r_c = http.post(
            f"{URL_FILA}/{caso.id}/contato",
            json={"canal": "whatsapp", "motivo": "Contato realizado para iniciar prazo."},
            headers=c.token("med_a"),
        )
        assert r_c.status_code == 200, r_c.text
        caso = contexto.checkout_sem_codigo.obter(caso.id)
    return pid, caso


def test_decidir_liberar_idempotencia_e_imutabilidade_no_postgres(ambiente_f2):
    c = ambiente_f2
    http, contexto, _ = c.pagto
    pid, caso = _novo_caso(c)
    chave = f"chave-pg-lib-{uuid.uuid4().hex}"

    # Sem permissão (suporte/financeiro/cliente) -> 403
    assert (
        http.post(
            f"{URL_FILA}/{caso.id}/decisao",
            json={"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": chave},
            headers=c.token("cliente"),
        ).status_code
        == 403
    )

    # Antes do prazo vencer -> 409
    assert (
        http.post(
            f"{URL_FILA}/{caso.id}/decisao",
            json={"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": chave},
            headers=c.token("adm_a"),
        ).status_code
        == 409
    )

    agora_orig = contexto.agora
    futuro = agora_orig() + timedelta(days=15)
    contexto.agora = lambda: futuro
    try:
        # Decisão liberar por administrador (alçada irrestrita)
        r = http.post(
            f"{URL_FILA}/{caso.id}/decisao",
            json={"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": chave},
            headers=c.token("adm_a"),
        )
        assert r.status_code == 200, r.text
        corpo = r.json()
        assert corpo["decisao"] == "liberar" and corpo["estado_pedido"] == "concluido"
        assert corpo["idempotente"] is False
        assert contexto.pedidos.obter(pid).estado is E.CONCLUIDO

        # Idempotência com a mesma chave -> 200 idempotente=True
        r2 = http.post(
            f"{URL_FILA}/{caso.id}/decisao",
            json={"decisao": "liberar", "motivo": MOTIVO, "chave_idempotencia": chave},
            headers=c.token("adm_a"),
        )
        assert r2.status_code == 200 and r2.json()["idempotente"] is True

        # Nova chave no mesmo caso -> 409
        assert (
            http.post(
                f"{URL_FILA}/{caso.id}/decisao",
                json={
                    "decisao": "estornar",
                    "motivo": MOTIVO,
                    "chave_idempotencia": f"chave-pg-dup-{uuid.uuid4().hex}",
                },
                headers=c.token("adm_a"),
            ).status_code
            == 409
        )

        # responder() filtra decidido_em is null e não altera caso já decidido
        assert contexto.checkout_sem_codigo.responder(pid, CONFIRMOU, contexto.agora()) == 0

    finally:
        contexto.agora = agora_orig

    # Trigger do banco bloqueia alterar decisão já gravada
    with pytest.raises(psycopg.Error), c.local.admin() as con:
        con.execute(
            "update public.checkout_sem_codigo_casos set decisao = 'estornar' where id = %s",
            (caso.id,),
        )


def test_decidir_estornar_alcada_e_bloqueio_pos_resposta_no_postgres(ambiente_f2):
    c = ambiente_f2
    http, contexto, _ = c.pagto

    # 1. Estornar com sucesso
    pid1, caso1 = _novo_caso(c)
    chave1 = f"chave-pg-est-{uuid.uuid4().hex}"
    agora_orig = contexto.agora
    futuro = agora_orig() + timedelta(days=15)
    contexto.agora = lambda: futuro
    r = http.post(
        f"{URL_FILA}/{caso1.id}/decisao",
        json={"decisao": "estornar", "motivo": MOTIVO, "chave_idempotencia": chave1},
        headers=c.token("adm_a"),
    )
    assert r.status_code == 200, r.text
    assert r.json()["decisao"] == "estornar" and r.json()["estado_pedido"] == "cancelado"
    assert contexto.pedidos.obter(pid1).estado is E.CANCELADO
    saldos = contexto.ledger.saldos_pedido(pid1, c.ids["profissional"])
    assert saldos.retido == 0 and saldos.a_liberar == 0

    contexto.agora = agora_orig
    # 2. Alçada insuficiente -> 403 (mediador com alçada baixa)
    pid2, caso2 = _novo_caso(c)
    contexto.agora = lambda: futuro
    with c.local.admin() as con:
        con.execute(
            "update public.equipe set alcada_centavos = 100 where usuario_id = %s",
            (c.ids["med_a"],),
        )
    assert (
        http.post(
            f"{URL_FILA}/{caso2.id}/decisao",
            json={
                "decisao": "liberar",
                "motivo": MOTIVO,
                "chave_idempotencia": f"chave-pg-alc-{uuid.uuid4().hex}",
            },
            headers=c.token("med_a"),
        ).status_code
        == 403
    )

    contexto.agora = agora_orig
    # 3. Cliente abre disputa -> decisão bloqueada com 409
    assert (
        http.post(
            f"/v1/pedidos/{pid2}/disputa",
            json={"motivo": "mal_feito", "descricao": "Não foi finalizado corretamente."},
            headers=c.token("cliente"),
        ).status_code
        == 201
    )
    assert (
        http.post(
            f"{URL_FILA}/{caso2.id}/decisao",
            json={
                "decisao": "liberar",
                "motivo": MOTIVO,
                "chave_idempotencia": f"chave-pg-disp-{uuid.uuid4().hex}",
            },
            headers=c.token("adm_a"),
        ).status_code
        == 409
    )
