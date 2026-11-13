"""O profissional enxerga os orçamentos que enviou; as conversas respeitam o papel de quem vê."""

from __future__ import annotations

from conftest import CLIENTE, PROFISSIONAL, cab
from test_notificacoes_api import servico_do

from trato.pedidos.estados import Estado

ORC = {
    "itens": [
        {"tipo": "outro", "descricao": "Serviço", "quantidade": 1, "valor_unitario_centavos": 9_000}
    ]
}


def _get(amb, url, quem="t-cliente", **kw):
    return amb.cliente.get(url, headers=cab(quem), **kw)


def _post(amb, url, quem, corpo=None, **kw):
    return amb.cliente.post(url, json=corpo, headers=cab(quem), **kw)


def _aberto(amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    amb.contexto.contratos._itens.clear()
    # a fixture traz um orçamento de exemplo; aqui só valem os que o teste envia
    amb.contexto.orcamentos._itens.clear()
    amb.contexto.orcamentos._detalhes.clear()


def test_profissional_ve_o_orcamento_que_enviou_aguardando_o_cliente(amb):
    _aberto(amb)
    assert _get(amb, "/v1/profissional/orcamentos", "t-prof").json() == []
    novo = _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof", ORC).json()
    [o] = _get(amb, "/v1/profissional/orcamentos", "t-prof").json()
    assert o["orcamento_id"] == novo["id"] and o["pedido_id"] == "ped-1"
    assert o["valor_centavos"] == 9_000 and o["situacao"] == "aguardando"
    # nova versão (contraproposta aceita): continua UM item, com a versão e o valor novos
    base = f"/v1/pedidos/ped-1/orcamentos/{novo['id']}/contraproposta"
    assert _post(amb, base, "t-cliente", {"valor_centavos": 7_000}).status_code == 201
    r = _post(amb, base + "/aceitar", "t-prof", {"valor_centavos": 7_000})
    assert r.status_code == 201, r.text
    [o] = _get(amb, "/v1/profissional/orcamentos", "t-prof").json()
    assert o["valor_centavos"] == 7_000 and o["versao"] == 2


def test_orcamento_aceito_e_orcamento_de_pedido_que_fechou_com_outro(amb):
    _aberto(amb)
    mine = _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof", ORC).json()["id"]
    outro = _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-outro-prof", ORC).json()["id"]
    # cliente fecha com o outro profissional
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO, orcamento_id=outro, profissional_id="pro-2")
    [o] = _get(amb, "/v1/profissional/orcamentos", "t-prof").json()
    assert o["orcamento_id"] == mine and o["situacao"] == "encerrado"
    [o2] = _get(amb, "/v1/profissional/orcamentos", "t-outro-prof").json()
    assert o2["situacao"] == "aceito"


def test_so_profissional_ve_a_lista_e_ve_so_os_seus(amb):
    _aberto(amb)
    _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof", ORC)
    assert _get(amb, "/v1/profissional/orcamentos", "t-cliente").status_code == 403
    assert _get(amb, "/v1/profissional/orcamentos", "t-outro-prof").json() == []


def test_conversas_separadas_por_papel_na_mesma_conta(amb):
    servico_do(amb)
    # PROFISSIONAL é cliente do pedido ped-1 (dois papéis) e profissional no pedido ped-2
    amb.semear_pedido(
        Estado.ABERTO, cliente_id=PROFISSIONAL.id, profissional_id=None, orcamento_id=None
    )
    amb.contexto.contratos._itens.clear()
    # pro-2 puxa conversa no pedido aberto de pro-1; pro-1 (como cliente) responde
    _post(amb, "/v1/pedidos/ped-1/mensagens", "t-outro-prof", {"texto": "oi, tiro dúvidas?"})
    _post(
        amb, "/v1/pedidos/ped-1/mensagens", "t-prof", {"texto": "olá"},
        params={"profissional_id": "pro-2"},
    )  # fmt: skip
    # pro-1, como cliente, converse com pro-2; e, como profissional, com CLIENTE em outro pedido
    outro = type(amb.contexto.pedidos.obter("ped-1"))(
        id="ped-2",
        cliente_id=CLIENTE.id,
        aberto_em=amb.contexto.pedidos.obter("ped-1").aberto_em,
        estado=Estado.ABERTO,
    )
    amb.contexto.pedidos.salvar(outro)
    _post(amb, "/v1/pedidos/ped-2/mensagens", "t-prof", {"texto": "posso orçar"})
    todas = _get(amb, "/v1/conversas", "t-prof").json()
    como_cliente = _get(amb, "/v1/conversas?como=cliente", "t-prof").json()
    como_prof = _get(amb, "/v1/conversas?como=profissional", "t-prof").json()
    assert {c["pedido_id"] for c in todas} == {"ped-1", "ped-2"}
    assert [c["pedido_id"] for c in como_cliente] == ["ped-1"] and como_cliente[0]["sou_cliente"]
    assert [c["pedido_id"] for c in como_prof] == ["ped-2"] and not como_prof[0]["sou_cliente"]
    assert _get(amb, "/v1/conversas?como=qualquer", "t-prof").status_code == 422
