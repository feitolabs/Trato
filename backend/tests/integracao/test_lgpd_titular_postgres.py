"""TERMOS-BE-1410 no Postgres local: triggers de `public.lgpd_pedidos_titular`
(migration 20261125225700), prazo de 15 dias em UTC-3, protocolo LGPD- e papéis dpo/seguranca."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest

from trato.persistencia.lgpd_titular import LgpdTitularPostgres, calcular_responder_ate

from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

pytestmark = pytest.mark.integracao


def _criar_equipe_lgpd(c) -> tuple[str, str]:
    dpo_id = str(uuid.uuid4())
    seg_id = str(uuid.uuid4())
    with c.local.admin() as con:
        for uid, nome, papel in (
            (dpo_id, "DPO Teste", "dpo"),
            (seg_id, "Seguranca Teste", "seguranca"),
        ):
            con.execute("insert into auth.users (id) values (%s)", (uid,))
            con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, nome))
            con.execute(
                "insert into public.equipe (usuario_id, papel, ativo) values (%s, %s, true)",
                (uid, papel),
            )
    return dpo_id, seg_id


def test_pedidos_titular_e_revisao_automatizada_no_postgres(cenario, migrations_novas):  # noqa: F811
    _ = migrations_novas
    c = cenario
    repo = LgpdTitularPostgres(c.banco)
    assert repo.disponivel()
    dpo_id, seg_id = _criar_equipe_lgpd(c)

    agora = datetime.now(UTC)
    prazo = calcular_responder_ate(agora, 15)

    # Pedido de revisão automatizada -> protocolo LGPD-... e idempotência
    p1, novo1 = repo.abrir(
        usuario_id=c.ids["cliente"],
        tipo="revisao_decisao_automatizada",
        decisao_automatizada="alerta_fraude",
        referencia_tipo=None,
        referencia_id=None,
        descricao="Revisão do bloqueio automático.",
        canal="app",
        exclusao_id=None,
        aberto_em=agora,
        responder_ate=prazo,
    )
    assert novo1 and p1.protocolo.startswith("LGPD-")

    p1_dup, novo2 = repo.abrir(
        usuario_id=c.ids["cliente"],
        tipo="revisao_decisao_automatizada",
        decisao_automatizada="alerta_fraude",
        referencia_tipo=None,
        referencia_id=None,
        descricao="Revisão do bloqueio automático.",
        canal="app",
        exclusao_id=None,
        aberto_em=agora,
        responder_ate=prazo,
    )
    assert not novo2 and p1_dup.id == p1.id

    # Segurança analisa e responde com critérios informados (passa no trigger do banco!)
    p_ana, cod_ana = repo.iniciar_analise(p1.id, seg_id)
    assert cod_ana == "ok" and p_ana is not None and p_ana.status == "em_analise"

    p_resp, cod_resp = repo.responder(
        p1.id,
        "atendido",
        seg_id,
        "Revisão concluída pela equipe de segurança.",
        agora,
        criterios_informados="Regra de múltiplas tentativas de dispositivo.",
    )
    assert cod_resp == "ok" and p_resp is not None and p_resp.status == "atendido"

    # Pedido comum atendido pelo DPO
    p2, novo3 = repo.abrir(
        usuario_id=c.ids["cliente"],
        tipo="acesso",
        decisao_automatizada=None,
        referencia_tipo=None,
        referencia_id=None,
        descricao="Acesso aos dados.",
        canal="app",
        exclusao_id=None,
        aberto_em=agora,
        responder_ate=prazo,
    )
    assert novo3
    p2_resp, cod2 = repo.responder(p2.id, "atendido", dpo_id, "Dados enviados ao titular.", agora)
    assert cod2 == "ok" and p2_resp is not None and p2_resp.status == "atendido"

    itens, total = repo.listar_do_usuario(c.ids["cliente"], 10, 0)
    assert total == 2 and len(itens) == 2
