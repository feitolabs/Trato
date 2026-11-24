"""POST /v1/denuncias: perfil ou chat denunciado vira alerta na fila de risco."""

from __future__ import annotations

from conftest import cab

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import PerfilDetalhe
from trato.pedidos.estados import Estado

URL = "/v1/denuncias"
MENSAGEM = "Denúncia enviada para análise da nossa equipe."


def _corpo(**extra):
    base = {
        "alvo_tipo": "chat",
        "denunciado_id": "pro-1",
        "pedido_id": "ped-1",
        "motivo": "assedio",
        "detalhes": "Mensagens ofensivas no chat.",
    }
    return {**base, **extra}


def _alertas(amb):
    return list(amb.contexto.denuncias.alertas.values())


def test_denuncia_de_chat_cria_alerta_na_fila_de_risco(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    r = amb.cliente.post(URL, json=_corpo(), headers=cab("t-cliente"))
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["status"] == "recebida" and corpo["mensagem"] == MENSAGEM and corpo["id"]
    (alerta,) = _alertas(amb)
    assert alerta.id == corpo["id"]
    assert (alerta.tipo, alerta.severidade) == ("denuncia_chat", "alta")  # assédio é grave
    assert (alerta.usuario_id, alerta.pedido_id) == ("pro-1", "ped-1")
    assert "cli-1" in alerta.detalhes and "assedio" in alerta.detalhes
    assert "Mensagens ofensivas" in alerta.detalhes


def test_motivo_comum_tem_severidade_media(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    r = amb.cliente.post(URL, json=_corpo(motivo="outro"), headers=cab("t-cliente"))
    assert r.status_code == 201
    assert _alertas(amb)[0].severidade == "media"


def test_profissional_tambem_denuncia_o_cliente_do_pedido(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    r = amb.cliente.post(URL, json=_corpo(denunciado_id="cli-1"), headers=cab("t-prof"))
    assert r.status_code == 201, r.text
    assert _alertas(amb)[0].usuario_id == "cli-1"


def test_denuncia_de_perfil_exige_perfil_existente(amb):
    corpo = {
        "alvo_tipo": "perfil",
        "denunciado_id": "pro-1",
        "motivo": "perfil_falso",
        "detalhes": "Fotos de outra pessoa.",
    }
    assert amb.cliente.post(URL, json=corpo, headers=cab("t-cliente")).status_code == 404
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(
            "pro-1", "João Pintor", PapelUsuario.PROFISSIONAL, "ativo", "verificado", 4.5, 3
        )
    )
    r = amb.cliente.post(URL, json=corpo, headers=cab("t-cliente"))
    assert r.status_code == 201, r.text
    (alerta,) = _alertas(amb)
    assert (alerta.tipo, alerta.severidade, alerta.pedido_id) == ("denuncia_perfil", "media", None)


def test_nao_denuncia_a_si_mesmo(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    r = amb.cliente.post(URL, json=_corpo(denunciado_id="cli-1"), headers=cab("t-cliente"))
    assert r.status_code == 422
    assert r.json()["detail"] == "Você não pode denunciar a si mesmo."
    assert _alertas(amb) == []


def test_terceiro_nao_denuncia_chat_de_outro_pedido(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    r = amb.cliente.post(URL, json=_corpo(), headers=cab("t-outro-cliente"))
    assert r.status_code == 404
    assert _alertas(amb) == []


def test_chat_exige_pedido_e_denunciado_do_pedido(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    sem_pedido = _corpo(pedido_id=None)
    assert amb.cliente.post(URL, json=sem_pedido, headers=cab("t-cliente")).status_code == 422
    estranho = _corpo(denunciado_id="pro-2")
    assert amb.cliente.post(URL, json=estranho, headers=cab("t-cliente")).status_code == 422


def test_validacao_do_corpo_e_login(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    for ruim in (
        _corpo(motivo="spam"),
        _corpo(alvo_tipo="grupo"),
        _corpo(detalhes="oi"),
        _corpo(detalhes="x" * 501),
    ):
        assert amb.cliente.post(URL, json=ruim, headers=cab("t-cliente")).status_code == 422
    assert amb.cliente.post(URL, json=_corpo()).status_code == 401
    assert amb.cliente.post(URL, json=_corpo(), headers=cab("t-equipe")).status_code == 403


def test_segunda_denuncia_do_mesmo_pedido_soma_ao_alerta_aberto(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    primeira = amb.cliente.post(URL, json=_corpo(motivo="outro"), headers=cab("t-cliente"))
    segunda = amb.cliente.post(
        URL, json=_corpo(motivo="fraude", detalhes="Pediu Pix por fora."), headers=cab("t-cliente")
    )
    assert primeira.json()["id"] == segunda.json()["id"]
    (alerta,) = _alertas(amb)
    assert alerta.severidade == "alta" and "Pediu Pix por fora." in alerta.detalhes
