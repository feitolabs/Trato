"""Mensagens 409/422 do app sem status, slug ou nome interno de documento."""

from __future__ import annotations

from conftest import cab


def test_documentos_faltando_aparecem_com_nome_legivel(amb):
    so_selfie = [{"tipo": "selfie", "storage_path": "pro-1/v/s.jpg"}]
    r = amb.cliente.post(
        "/v1/profissional/verificacao",
        json={"consentimento_lgpd": True, "documentos": so_selfie},
        headers=cab("t-prof"),
    )
    assert r.status_code == 422, r.text
    detalhe = r.json()["detail"]
    assert "frente do documento" in detalhe
    assert "documento_frente" not in detalhe and "_" not in detalhe


def test_recusa_fora_de_enviado_nao_expoe_status(amb):
    from test_b30_nao_escolhido import _ligar, _pedido_com_tres_orcamentos

    _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    assert amb.contexto.orcamentos.recusar("ped-1", "orc-b") is True
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos/orc-b/recusar", headers=cab("t-cliente"))
    assert r.status_code == 200  # já recusado: idempotente, sem erro
