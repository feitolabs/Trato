# ruff: noqa: F811  (fixture `e2` importada de test_profissional_upload)
"""Foto no chat: sobe como anexo de chat, vai na mensagem como `[Foto:<id>]` e abre por URL curta."""

from __future__ import annotations

from conftest import cab
from test_profissional_upload import JPEG_COM_EXIF, e2  # noqa: F401

from trato.pedidos.estados import Estado


def _foto_no_chat(e2, quem="t-cliente"):
    pedir, concluir = e2.enviar(quem, "chat", JPEG_COM_EXIF, pedido_id="ped-1")
    assert concluir is not None and concluir.status_code == 200, pedir.text
    return concluir.json()["midia_id"]


def test_cliente_manda_foto_o_profissional_abre_e_estranho_nao(e2, amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    midia = _foto_no_chat(e2)
    msg = amb.cliente.post(
        "/v1/pedidos/ped-1/mensagens", json={"texto": f"[Foto:{midia}]"}, headers=cab("t-cliente")
    )
    assert msg.status_code == 201
    url = f"/v1/pedidos/ped-1/anexos-chat/{midia}"
    do_prof = e2.get(url, "t-prof")
    assert do_prof.status_code == 200 and do_prof.json()["url"].startswith("https://")
    assert e2.get(url, "t-cliente").status_code == 200
    assert e2.get(url, "t-outro-cliente").status_code == 404
    assert e2.get(url, "t-outro-prof").status_code == 404
    assert e2.get("/v1/pedidos/ped-1/anexos-chat/nao-existe", "t-prof").status_code == 404


def test_profissional_manda_foto_antes_de_ser_contratado_sem_mascara(e2, amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    amb.contexto.contratos._itens.clear()
    orcamento = {
        "itens": [
            {
                "tipo": "outro",
                "descricao": "Serviço",
                "quantidade": 1,
                "valor_unitario_centavos": 9_000,
            }
        ]
    }
    assert e2.post("/v1/pedidos/ped-1/orcamentos", "t-prof", orcamento).status_code == 201
    midia = _foto_no_chat(e2, "t-prof")  # profissional que vê o pedido aberto pode anexar
    r = e2.post("/v1/pedidos/ped-1/mensagens", "t-prof", {"texto": f"[Foto:{midia}]"})
    assert r.status_code == 201
    [m] = e2.get("/v1/pedidos/ped-1/mensagens?profissional_id=pro-1", "t-cliente").json()
    assert m["texto"] == f"[Foto:{midia}]" and m["mascarada"] is False
    # o cliente abre a foto que o profissional mandou (mesmo sem contrato)
    assert e2.get(f"/v1/pedidos/ped-1/anexos-chat/{midia}", "t-cliente").status_code == 200


def test_marcador_de_foto_com_muitos_digitos_nao_vira_telefone():
    from trato.persistencia.conversas import mascarar_contatos

    marcador = "[Foto:1234567890123456abcdef1234567890]"
    assert mascarar_contatos(marcador) == marcador
    # texto comum com telefone continua mascarado
    assert "99999" not in mascarar_contatos("me liga 31 99999-8888")


def test_foto_de_chat_de_outro_pedido_nao_abre_aqui(e2, amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    midia = _foto_no_chat(e2)
    amb.contexto.pedidos.salvar(
        type(amb.contexto.pedidos.obter("ped-1"))(
            id="ped-2",
            cliente_id="cli-1",
            aberto_em=amb.contexto.pedidos.obter("ped-1").aberto_em,
            estado=Estado.ORCAMENTO_ACEITO,
            profissional_id="pro-1",
            orcamento_id="orc-1",
        )
    )
    assert e2.get(f"/v1/pedidos/ped-2/anexos-chat/{midia}", "t-cliente").status_code == 404
