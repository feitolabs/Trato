"""Denúncias no Postgres: alerta na fila de risco, respeitando as constraints de alertas_risco."""

from __future__ import annotations

import pytest

from .test_fluxo_postgres import abrir_pedido, acao, enviar_orcamento
from .test_rotas_app_postgres import post

pytestmark = pytest.mark.integracao


def _chat(c, pedido_id, motivo, detalhes):
    corpo = {
        "alvo_tipo": "chat",
        "denunciado_id": c.ids["profissional"],
        "pedido_id": pedido_id,
        "motivo": motivo,
        "detalhes": detalhes,
    }
    return post(c, "/v1/denuncias", "cliente", corpo)


def test_denuncias_no_postgres_respeitam_constraints_e_unicidade(cenario):
    c = cenario
    pedido_id = abrir_pedido(c)
    orcamento_id = enviar_orcamento(c, pedido_id)
    ok = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orcamento_id})
    assert ok.status_code == 200, ok.text

    # Perfil: alerta sem pedido, severidade media.
    perfil = {
        "alvo_tipo": "perfil",
        "denunciado_id": c.ids["profissional"],
        "motivo": "perfil_falso",
        "detalhes": "Fotos de outra pessoa.",
    }
    r = post(c, "/v1/denuncias", "cliente", perfil)
    assert r.status_code == 201, r.text
    with c.local.admin() as con:
        linha = con.execute(
            "select tipo, severidade, pedido_id from public.alertas_risco where id = %s",
            (r.json()["id"],),
        ).fetchone()
    assert tuple(linha) == ("denuncia_perfil", "media", None)

    # Chat: a segunda denúncia do mesmo pedido soma ao alerta aberto e sobe a severidade.
    primeira = _chat(c, pedido_id, "outro", "Tom agressivo nas mensagens.")
    assert primeira.status_code == 201, primeira.text
    segunda = _chat(c, pedido_id, "fraude", "Pediu Pix por fora.")
    assert segunda.json()["id"] == primeira.json()["id"]
    with c.local.admin() as con:
        linha = con.execute(
            "select tipo, severidade, detalhes from public.alertas_risco where id = %s",
            (primeira.json()["id"],),
        ).fetchone()
    assert linha[0] == "denuncia_chat" and linha[1] == "alta"
    assert "Tom agressivo" in linha[2] and "Pediu Pix por fora." in linha[2]

    # Com o alerta resolvido, a nova denúncia vira alerta novo (sem o vínculo de pedido).
    with c.local.admin() as con:
        con.execute(
            "update public.alertas_risco set resolvido = true, status = 'resolvido' where id = %s",
            (primeira.json()["id"],),
        )
    terceira = _chat(c, pedido_id, "assedio", "Voltou a ofender.")
    assert terceira.status_code == 201
    assert terceira.json()["id"] != primeira.json()["id"]
    with c.local.admin() as con:
        linha = con.execute(
            "select pedido_id, detalhes from public.alertas_risco where id = %s",
            (terceira.json()["id"],),
        ).fetchone()
    assert linha[0] is None and pedido_id in linha[1]

    # Terceiro (o profissional ainda não orçou outro pedido) e auto-denúncia.
    self_corpo = dict(perfil, denunciado_id=c.ids["cliente"])
    assert post(c, "/v1/denuncias", "cliente", self_corpo).status_code == 422
