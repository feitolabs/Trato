"""Financeiro do painel em memória: conciliação, pagamentos e o que o espelho mostra."""

from admin_ambiente import AGORA, adm, cab  # noqa: F401

from trato.financeiro.ledger import registrar_cobranca

BASE = "/v1/admin"
FIN = cab("t-financeiro")


def test_conciliacoes_alem_de_100_nao_voltam_a_aparecer(adm):
    # Antes só as 100 últimas conciliações da auditoria contavam: a 101ª voltava como divergência.
    for n in range(105):
        registrar_cobranca(adm.contexto.ledger.livro, f"ped-fantasma-{n}", 1_000, f"c-{n}", AGORA)
    itens = adm.cliente.get(f"{BASE}/pagamentos?limite=100", headers=FIN).json()["itens"]
    itens += adm.cliente.get(
        f"{BASE}/pagamentos?limite=100&deslocamento=100", headers=FIN
    ).json()["itens"]
    assert len(itens) == 105

    for item in itens:
        r = adm.cliente.post(
            f"{BASE}/divergencias/{item['lancamento_id']}/conciliar",
            json={"motivo": "Conferido no extrato do provedor"},
            headers=FIN,
        )
        assert r.status_code == 204, r.text

    resumo = adm.cliente.get(f"{BASE}/pagamentos/resumo", headers=FIN).json()
    assert resumo["divergencias"] == 0
    assert resumo["valor_divergente_centavos"] == 0


def test_filtro_de_periodo_vale_antes_de_montar_a_lista(adm):
    registrar_cobranca(adm.contexto.ledger.livro, "ped-velho", 1_000, "c-velho", AGORA)
    adm.relogio.avancar(days=40)
    registrar_cobranca(adm.contexto.ledger.livro, "ped-novo", 2_000, "c-novo", adm.relogio())

    ultimos_30 = adm.cliente.get(f"{BASE}/pagamentos?dias=30", headers=FIN).json()
    todos = adm.cliente.get(f"{BASE}/pagamentos", headers=FIN).json()

    assert [i["pedido_id"] for i in ultimos_30["itens"]] == ["ped-novo"]
    assert todos["total"] == 2
