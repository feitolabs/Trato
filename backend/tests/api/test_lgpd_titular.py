# ruff: noqa: F811
"""TERMOS-BE-1410 (14.9 e 14.10): pedidos de titular LGPD e revisão de decisão automatizada."""

from __future__ import annotations

import pytest
from admin_ambiente import adm, cab, token_de  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.persistencia.lgpd_titular import LgpdTitularEmMemoria


def test_usuario_abre_pedido_comum_e_revisao_automatizada_idempotente_e_lista(adm):
    # Validações de entrada
    assert (
        adm.cliente.post(
            "/v1/me/lgpd/pedidos",
            json={"tipo": "revisao_decisao_automatizada", "descricao": "Sem tipo de decisão."},
            headers=cab("t-cliente"),
        ).status_code
        == 422
    )
    assert (
        adm.cliente.post(
            "/v1/me/lgpd/pedidos",
            json={"tipo": "acesso", "decisao_automatizada": "alerta_fraude"},
            headers=cab("t-cliente"),
        ).status_code
        == 422
    )

    # Pedido comum (acesso) -> 201 e repetição idempotente -> 200
    r1 = adm.cliente.post(
        "/v1/me/lgpd/pedidos",
        json={"tipo": "acesso", "descricao": "Quero confirmar quais dados pessoais há na conta."},
        headers=cab("t-cliente"),
    )
    assert r1.status_code == 201, r1.text
    p1 = r1.json()
    assert p1["status"] == "aberto" and p1["protocolo"].startswith("LGPD-")
    assert "analista_id" not in p1

    r1_dup = adm.cliente.post(
        "/v1/me/lgpd/pedidos",
        json={"tipo": "acesso", "descricao": "Quero confirmar quais dados pessoais há na conta."},
        headers=cab("t-cliente"),
    )
    assert r1_dup.status_code == 200 and r1_dup.json()["id"] == p1["id"]

    # Revisão de decisão automatizada -> 201
    r2 = adm.cliente.post(
        "/v1/me/lgpd/pedidos",
        json={
            "tipo": "revisao_decisao_automatizada",
            "decisao_automatizada": "alerta_fraude",
            "descricao": "Minha conta caiu no alerta automático indevidamente.",
        },
        headers=cab("t-cliente"),
    )
    assert r2.status_code == 201, r2.text

    # Listagem própria: só do cliente, não do profissional
    meus = adm.cliente.get("/v1/me/lgpd/pedidos", headers=cab("t-cliente"))
    assert meus.status_code == 200 and meus.json()["total"] == 2
    assert all("analista_id" not in item for item in meus.json()["itens"])

    outros = adm.cliente.get("/v1/me/lgpd/pedidos", headers=cab("t-prof"))
    assert outros.status_code == 200 and outros.json()["total"] == 0


def test_permissoes_dpo_seguranca_admin_transicoes_e_auditoria_sem_texto_livre(adm):
    p_comum = adm.cliente.post(
        "/v1/me/lgpd/pedidos",
        json={"tipo": "correcao", "descricao": "CPF 123.456.789-00 incorreto no cadastro."},
        headers=cab("t-cliente"),
    ).json()
    p_auto = adm.cliente.post(
        "/v1/me/lgpd/pedidos",
        json={
            "tipo": "revisao_decisao_automatizada",
            "decisao_automatizada": "alerta_fraude",
            "descricao": "Fui bloqueado pelo sistema antifraude.",
        },
        headers=cab("t-cliente"),
    ).json()

    h_seg = cab(token_de("seguranca"))
    h_dpo = cab(token_de("dpo"))
    h_med = cab(token_de("mediador"))

    # Mediador não tem acesso
    assert adm.cliente.get("/v1/admin/lgpd/pedidos", headers=h_med).status_code == 403

    # Segurança vê só revisao_decisao_automatizada e recebe 403 em pedido comum
    lista_seg = adm.cliente.get("/v1/admin/lgpd/pedidos", headers=h_seg)
    assert lista_seg.status_code == 200 and lista_seg.json()["total"] == 1
    assert lista_seg.json()["itens"][0]["id"] == p_auto["id"]
    assert (
        adm.cliente.get(
            "/v1/admin/lgpd/pedidos", params={"tipo": "correcao"}, headers=h_seg
        ).status_code
        == 403
    )
    assert (
        adm.cliente.post(
            f"/v1/admin/lgpd/pedidos/{p_comum['id']}/analisar", headers=h_seg
        ).status_code
        == 403
    )

    # Segurança analisa e responde o pedido de revisão automatizada (exige criterios_informados)
    assert (
        adm.cliente.post(
            f"/v1/admin/lgpd/pedidos/{p_auto['id']}/analisar", headers=h_seg
        ).status_code
        == 200
    )
    assert (
        adm.cliente.post(
            f"/v1/admin/lgpd/pedidos/{p_auto['id']}/responder",
            json={"status": "atendido", "resposta": "Revisado por analista humano."},
            headers=h_seg,
        ).status_code
        == 422
    )
    r_auto_ok = adm.cliente.post(
        f"/v1/admin/lgpd/pedidos/{p_auto['id']}/responder",
        json={
            "status": "atendido",
            "resposta": "Revisão concluída por pessoa e restrição removida.",
            "criterios_informados": "Sinal de risco por tentativas repetidas de dispositivo.",
        },
        headers=h_seg,
    )
    assert r_auto_ok.status_code == 200 and r_auto_ok.json()["status"] == "atendido"

    # DPO vê todos os 2 pedidos, exige motivo_nao_atendido para negado/parcial e responde comum
    lista_dpo = adm.cliente.get("/v1/admin/lgpd/pedidos", headers=h_dpo)
    assert lista_dpo.status_code == 200 and lista_dpo.json()["total"] == 2
    assert (
        adm.cliente.post(
            f"/v1/admin/lgpd/pedidos/{p_comum['id']}/responder",
            json={"status": "negado", "resposta": "Não foi possível corrigir sem documento."},
            headers=h_dpo,
        ).status_code
        == 422
    )
    r_comum_ok = adm.cliente.post(
        f"/v1/admin/lgpd/pedidos/{p_comum['id']}/responder",
        json={
            "status": "negado",
            "resposta": "Não foi possível alterar sem comprovante oficial.",
            "motivo_nao_atendido": "Titular não enviou documento comprobatório válido.",
        },
        headers=h_dpo,
    )
    assert r_comum_ok.status_code == 200 and r_comum_ok.json()["status"] == "negado"

    # Alterar pedido já respondido = 409
    assert (
        adm.cliente.post(
            f"/v1/admin/lgpd/pedidos/{p_comum['id']}/responder",
            json={"status": "atendido", "resposta": "Mudando decisão já tomada."},
            headers=h_dpo,
        ).status_code
        == 409
    )

    # Auditoria registrada sem vazar texto livre/CPF
    eventos, _ = adm.admin.auditoria.listar(FiltroAuditoria(), 50, 0)
    acoes = [e.acao for e in eventos]
    assert "lgpd.pedido_titular_em_analise" in acoes
    assert "lgpd.pedido_titular_respondido" in acoes
    assert all("123.456.789-00" not in repr(e) for e in eventos)


@pytest.mark.parametrize(
    ("metodo", "caminho", "corpo", "token"),
    [
        ("GET", "/v1/me/lgpd/pedidos", None, "t-cliente"),
        ("POST", "/v1/me/lgpd/pedidos", {"tipo": "acesso"}, "t-cliente"),
        ("GET", "/v1/admin/lgpd/pedidos", None, token_de("dpo")),
        ("POST", "/v1/admin/lgpd/pedidos/lgpd-1/analisar", None, token_de("dpo")),
    ],
)
def test_tabela_ausente_responde_503_limpo(adm, metodo, caminho, corpo, token):
    adm.contexto.lgpd_titular = LgpdTitularEmMemoria(disponivel=False)
    r = adm.cliente.request(metodo, caminho, json=corpo, headers=cab(token))
    assert r.status_code == 503
