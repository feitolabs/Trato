"""Orçamento por hora: horas de deslocamento e horas trabalhadas, e o total que o cliente vê."""

from __future__ import annotations

from conftest import cab

from trato.pedidos.estados import Estado

POR_HORA = {
    "itens": [
        {
            "tipo": "deslocamento",
            "descricao": "Deslocamento (horas)",
            "quantidade": 1.5,
            "valor_unitario_centavos": 8_000,
        },
        {
            "tipo": "horas",
            "descricao": "Horas trabalhadas",
            "quantidade": 3.5,
            "valor_unitario_centavos": 8_000,
        },
        {
            "tipo": "material",
            "descricao": "Cimento",
            "quantidade": 1,
            "valor_unitario_centavos": 5_000,
        },
    ],
    "garantia_dias": 60,
}


def _enviar(amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    amb.contexto.contratos._itens.clear()
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=POR_HORA, headers=cab("t-prof"))
    assert r.status_code == 201, r.text
    return r.json()


def test_orcamento_por_hora_soma_as_horas_dos_dois_campos(amb):
    novo = _enviar(amb)
    # 1,5 h de deslocamento + 3,5 h trabalhadas, a R$ 80,00 a hora, mais R$ 50,00 de material
    assert novo["valor_total_centavos"] == 5 * 8_000 + 5_000
    det = amb.cliente.get(f"/v1/orcamentos/{novo['id']}", headers=cab("t-cliente")).json()
    assert det["horas_deslocamento"] == "1.5"
    assert det["horas_trabalhadas"] == "3.5"
    assert det["total_horas"] == "5"


def test_orcamento_sem_horas_nao_traz_total_de_horas(amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    amb.contexto.contratos._itens.clear()
    corpo = {
        "itens": [
            {
                "tipo": "outro",
                "descricao": "Serviço",
                "quantidade": 1,
                "valor_unitario_centavos": 9_000,
            }
        ]
    }
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=corpo, headers=cab("t-prof"))
    det = amb.cliente.get(f"/v1/orcamentos/{r.json()['id']}", headers=cab("t-cliente")).json()
    assert det["total_horas"] is None and det["horas_trabalhadas"] is None


def test_contraproposta_aceita_mantem_o_total_de_horas(amb):
    novo = _enviar(amb)
    orc = novo["id"]
    base = f"/v1/pedidos/ped-1/orcamentos/{orc}"
    assert (
        amb.cliente.post(
            f"{base}/contraproposta", json={"valor_centavos": 30_000}, headers=cab("t-cliente")
        ).status_code
        == 201
    )
    aceite = amb.cliente.post(
        f"{base}/contraproposta/aceitar", json={"valor_centavos": 30_000}, headers=cab("t-prof")
    )
    assert aceite.status_code == 201, aceite.text
    det = amb.cliente.get(
        f"/v1/orcamentos/{aceite.json()['orcamento_id']}", headers=cab("t-cliente")
    ).json()
    assert det["valor_centavos"] == 30_000  # o horário zerado não soma nada
    assert det["total_horas"] == "5"
    lista = amb.cliente.get("/v1/pedidos/ped-1/orcamentos", headers=cab("t-cliente")).json()
    assert [o["valor_centavos"] for o in lista] == [30_000]  # o valor atual é o combinado
