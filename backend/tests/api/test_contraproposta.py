"""Contraproposta de valor: o cliente propõe menos; o profissional aceita e o orçamento ganha versão."""

from __future__ import annotations

from conftest import cab

from trato.pedidos.estados import Estado

ORCAMENTO = {
    "itens": [
        {"tipo": "horas", "descricao": "Mão de obra", "quantidade": 3, "valor_unitario_centavos": 10_000}
    ],
    "prazo_execucao_dias": 2,
    "garantia_dias": 60,
}


def _pedido_com_orcamento(amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _contra(amb, orc, valor, quem="t-cliente", **extra):
    return amb.cliente.post(
        f"/v1/pedidos/ped-1/orcamentos/{orc}/contraproposta",
        json={"valor_centavos": valor, **extra},
        headers=cab(quem),
    )


def test_cliente_propoe_menos_e_o_profissional_aceita_gerando_nova_versao(amb):
    orc = _pedido_com_orcamento(amb)
    r = _contra(amb, orc, 25_000, mensagem="Fecho hoje se der esse valor")
    assert r.status_code == 201, r.text

    # A proposta chega na conversa do profissional, com a marca que o app esconde.
    msgs = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-prof")).json()
    assert msgs[-1]["texto"].startswith(f"[contraproposta:{orc}:25000]")
    assert "R$ 250,00" in msgs[-1]["texto"] and "R$ 300,00" in msgs[-1]["texto"]

    aceite = amb.cliente.post(
        f"/v1/pedidos/ped-1/orcamentos/{orc}/contraproposta/aceitar",
        json={"valor_centavos": 25_000},
        headers=cab("t-prof"),
    )
    assert aceite.status_code == 201, aceite.text
    assert aceite.json()["valor_centavos"] == 25_000

    lista = amb.cliente.get("/v1/pedidos/ped-1/orcamentos", headers=cab("t-cliente")).json()
    assert 25_000 in [o["valor_centavos"] for o in lista]
    det = amb.cliente.get(f"/v1/orcamentos/{aceite.json()['orcamento_id']}", headers=cab("t-cliente"))
    assert det.status_code == 200 and det.json()["valor_centavos"] == 25_000
    assert det.json()["garantia_dias"] == 60  # prazo e garantia seguem os do orçamento original
    # A versão antiga não aceita mais contraproposta (o cliente deve olhar a nova).
    antiga = _contra(amb, orc, 20_000)
    assert antiga.status_code in (404, 409)


def test_contraproposta_tem_regras(amb):
    orc = _pedido_com_orcamento(amb)
    assert _contra(amb, orc, 30_000).status_code == 422  # igual ao atual
    assert _contra(amb, orc, 40_000).status_code == 422  # maior que o atual
    assert _contra(amb, orc, 0).status_code == 422
    assert _contra(amb, orc, 20_000, quem="t-prof").status_code == 404  # profissional não propõe
    assert _contra(amb, orc, 20_000, quem="t-outro-cliente").status_code in (403, 404)
    assert amb.cliente.post(
        "/v1/pedidos/ped-1/orcamentos/nao-existe/contraproposta",
        json={"valor_centavos": 100},
        headers=cab("t-cliente"),
    ).status_code == 404


def test_so_aceita_o_que_o_cliente_propos_e_so_o_autor(amb):
    orc = _pedido_com_orcamento(amb)
    url = f"/v1/pedidos/ped-1/orcamentos/{orc}/contraproposta/aceitar"
    # Sem proposta do cliente, o profissional não consegue "aceitar" um valor qualquer.
    sem = amb.cliente.post(url, json={"valor_centavos": 10_000}, headers=cab("t-prof"))
    assert sem.status_code == 422
    assert _contra(amb, orc, 25_000).status_code == 201
    # Valor diferente do proposto também é recusado.
    outro = amb.cliente.post(url, json={"valor_centavos": 10_000}, headers=cab("t-prof"))
    assert outro.status_code == 422
    # O cliente não aceita no lugar do profissional; outro profissional não vê o orçamento.
    assert amb.cliente.post(url, json={"valor_centavos": 25_000}, headers=cab("t-cliente")).status_code == 403
    assert amb.cliente.post(url, json={"valor_centavos": 25_000}, headers=cab("t-outro-prof")).status_code == 404


def test_depois_de_contratar_nao_cabe_contraproposta(amb):
    orc = _pedido_com_orcamento(amb)
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO, orcamento_id=orc)
    assert _contra(amb, orc, 20_000).status_code == 409
