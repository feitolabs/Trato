"""Financeiro do painel em memória: conciliação, pagamentos e o que o espelho mostra."""

from admin_ambiente import AGORA, adm, cab  # noqa: F401

from trato.financeiro.ledger import registrar_cobranca

BASE = "/v1/admin"
FIN = cab("t-financeiro")


def test_conciliacoes_alem_de_100_nao_voltam_a_aparecer(adm):  # noqa: F811
    # Antes só as 100 últimas conciliações da auditoria contavam: a 101ª voltava como divergência.
    for n in range(105):
        registrar_cobranca(adm.contexto.ledger.livro, f"ped-fantasma-{n}", 1_000, f"c-{n}", AGORA)
    itens = adm.cliente.get(f"{BASE}/pagamentos?limite=100", headers=FIN).json()["itens"]
    itens += adm.cliente.get(f"{BASE}/pagamentos?limite=100&deslocamento=100", headers=FIN).json()[
        "itens"
    ]
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


def test_filtro_de_periodo_vale_antes_de_montar_a_lista(adm):  # noqa: F811
    registrar_cobranca(adm.contexto.ledger.livro, "ped-velho", 1_000, "c-velho", AGORA)
    adm.relogio.avancar(days=40)
    registrar_cobranca(adm.contexto.ledger.livro, "ped-novo", 2_000, "c-novo", adm.relogio())

    ultimos_30 = adm.cliente.get(f"{BASE}/pagamentos?dias=30", headers=FIN).json()
    todos = adm.cliente.get(f"{BASE}/pagamentos", headers=FIN).json()

    assert [i["pedido_id"] for i in ultimos_30["itens"]] == ["ped-novo"]
    assert todos["total"] == 2


# --- Fechamento mensal, trava e extrato do profissional ----------------------------------------


def _baixar(adm, codigo):  # noqa: F811
    return adm.cliente.get(f"{BASE}/relatorios/baixar/{codigo}")


def test_fechar_mes_grava_retrato_e_nao_deixa_fechar_de_novo(adm):  # noqa: F811
    from datetime import timedelta

    registrar_cobranca(adm.contexto.ledger.livro, "ped-out", 10_000, "cob/pi_out", AGORA)
    motivo = {"motivo": "Fechamento de outubro conferido"}

    cedo = adm.cliente.post(
        f"{BASE}/financeiro/fechamentos/2026-10/fechar", json=motivo, headers=FIN
    )
    assert cedo.status_code == 422  # outubro ainda não terminou (relógio em 29/10)

    adm.relogio.avancar(days=5)
    meses = adm.cliente.get(f"{BASE}/financeiro/fechamentos?ultimos=2", headers=FIN).json()
    assert [(m["mes"], m["pode_fechar"]) for m in meses] == [("2026-11", False), ("2026-10", True)]

    r = adm.cliente.post(f"{BASE}/financeiro/fechamentos/2026-10/fechar", json=motivo, headers=FIN)

    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["fechado"] is True and corpo["confere"] is True and len(corpo["hash"]) == 64
    assert corpo["gravado"]["cobrado_centavos"] == 10_000
    de_novo = adm.cliente.post(
        f"{BASE}/financeiro/fechamentos/2026-10/fechar", json=motivo, headers=FIN
    )
    assert de_novo.status_code == 409
    # Algo que apareça depois no mês fechado (só por fora do sistema) é acusado na tela.
    registrar_cobranca(
        adm.contexto.ledger.livro, "ped-tarde", 1_000, "cob/pi_tarde", AGORA - timedelta(days=1)
    )
    visto = adm.cliente.get(f"{BASE}/financeiro/fechamentos/2026-10", headers=FIN).json()
    assert visto["confere"] is False
    assert visto["gravado"]["cobrado_centavos"] == 10_000
    assert (
        adm.cliente.post(
            f"{BASE}/financeiro/fechamentos/2026-10/fechar",
            json=motivo,
            headers=cab("t-atendente_n1"),
        ).status_code
        == 403
    )


def test_exportar_fechamento_entrega_csv_por_codigo_de_uso_unico(adm):  # noqa: F811
    registrar_cobranca(adm.contexto.ledger.livro, "ped-out", 12_345, "cob/pi_out", AGORA)

    r = adm.cliente.post(f"{BASE}/financeiro/fechamentos/2026-10/exportar", headers=FIN)

    assert r.status_code == 201, r.text
    arquivo = _baixar(adm, r.json()["codigo"])
    texto = arquivo.content.decode("utf-8-sig")
    assert "Prévia (mês ainda não fechado)" in texto
    assert "Recebido de clientes (bruto);123,45" in texto
    assert _baixar(adm, r.json()["codigo"]).status_code == 404  # uso único


def test_extrato_do_profissional_sai_em_pdf_com_motivo_e_auditoria(adm):  # noqa: F811
    from trato.api.admin.repositorios import FiltroAuditoria
    from trato.financeiro.ledger import liberar, repartir_custodia

    livro = adm.contexto.ledger.livro
    registrar_cobranca(livro, "ped-1", 10_000, "cob/pi_1", AGORA)
    repartir_custodia(livro, "ped-1", "pro-1", 0, "din/ped-1/rep", AGORA)
    liberar(livro, "ped-1", "pro-1", "liq/ped-1", AGORA)
    corpo = {"inicio": "2026-10-01", "fim": "2026-10-31", "motivo": "Pedido do profissional"}

    r = adm.cliente.post(f"{BASE}/financeiro/profissionais/pro-1/extrato", json=corpo, headers=FIN)

    assert r.status_code == 201, r.text
    pdf = _baixar(adm, r.json()["codigo"])
    assert pdf.headers["content-type"] == "application/pdf"
    assert pdf.content.startswith(b"%PDF") and "João Pintor".encode("cp1252") in pdf.content
    (registro,), _ = adm.admin.auditoria.listar(FiltroAuditoria(acao="relatorio."), 10, 0)
    assert registro.entidade_id == "pro-1" and registro.motivo == "Pedido do profissional"
    cliente = adm.cliente.post(
        f"{BASE}/financeiro/profissionais/cli-1/extrato", json=corpo, headers=FIN
    )
    assert cliente.status_code == 404
    sem_motivo = adm.cliente.post(
        f"{BASE}/financeiro/profissionais/pro-1/extrato",
        json={**corpo, "motivo": "curto"},
        headers=FIN,
    )
    assert sem_motivo.status_code == 422
