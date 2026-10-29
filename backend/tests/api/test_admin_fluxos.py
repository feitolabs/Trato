"""Verificação, usuários, pedidos, pagamentos (leitura) e auditoria da API administrativa."""

from admin_ambiente import AGORA, PEDIDO, adm, cab  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.repositorios import EventoWebhook
from trato.financeiro.ledger import registrar_cobranca

BASE = "/v1/admin"


# --- Verificação --------------------------------------------------------------------------------


def test_fila_e_detalhe_nao_expoem_caminho_nem_cpf_inteiro(adm):
    fila = adm.cliente.get(f"{BASE}/verificacoes", headers=cab("t-cadastro")).json()
    assert fila["total"] == 1
    detalhe = adm.cliente.get(f"{BASE}/verificacoes/ver-1", headers=cab("t-cadastro")).json()
    assert detalhe["cpf_mascarado"] == "***.***.***-09"
    assert all(d["mascarado"] for d in detalhe["documentos"])
    texto = str(detalhe)
    assert "bucket-privado" not in texto and "123.456" not in texto


def test_url_assinada_e_curta_exige_motivo_e_deixa_auditoria(adm):
    url = f"{BASE}/verificacoes/ver-1/documentos/doc-1/url"
    sem_motivo = adm.cliente.post(url, json={}, headers=cab("t-cadastro"))
    assert sem_motivo.status_code == 422 and not adm.assinador.chamadas

    r = adm.cliente.post(url, json={"motivo": "Conferir frente do RG"}, headers=cab("t-cadastro"))

    assert r.status_code == 200
    assert r.json()["expira_em_segundos"] == 60
    assert adm.assinador.chamadas == [("bucket-privado/ver-1/frente.jpg", 60)]
    registros, _ = adm.admin.auditoria.listar(FiltroAuditoria(acao="dado_pessoal."), 10, 0)
    assert registros[0].motivo == "Conferir frente do RG" and registros[0].ator_id == "eq-cadastro"


def test_documento_inexistente_da_404_e_sem_assinador_da_503(adm):
    corpo = {"motivo": "Conferir documento"}
    url = f"{BASE}/verificacoes/ver-1/documentos"
    assert (
        adm.cliente.post(f"{url}/nao/url", json=corpo, headers=cab("t-cadastro")).status_code == 404
    )
    adm.admin.assinador = None
    assert (
        adm.cliente.post(f"{url}/doc-1/url", json=corpo, headers=cab("t-cadastro")).status_code
        == 503
    )


def test_decisao_da_verificacao_exige_motivo_e_so_vale_uma_vez(adm):
    url = f"{BASE}/verificacoes/ver-1/decisao"
    cadastro = cab("t-cadastro")
    assert adm.cliente.post(url, json={"aprovar": True}, headers=cadastro).status_code == 422
    curto = {"aprovar": True, "motivo": "ok"}
    assert adm.cliente.post(url, json=curto, headers=cadastro).status_code == 422

    recusa = {"aprovar": False, "motivo": "Selfie ilegível"}
    r = adm.cliente.post(url, json=recusa, headers=cadastro)

    assert r.status_code == 200
    assert r.json()["status"] == "recusada" and r.json()["motivo_recusa"] == "Selfie ilegível"
    de_novo = {"aprovar": True, "motivo": "Mudei de ideia"}
    assert adm.cliente.post(url, json=de_novo, headers=cadastro).status_code == 409
    assert adm.cliente.get(f"{BASE}/verificacoes/xx", headers=cadastro).status_code == 404


# --- Usuários e pedidos --------------------------------------------------------------------------


def test_busca_de_usuarios_nao_mostra_dados_pessoais(adm):
    n1 = cab("t-atendente_n1")
    r = adm.cliente.get(f"{BASE}/usuarios?q=maria", headers=n1).json()
    assert r["total"] == 1 and r["itens"][0]["nome"] == "Maria Cliente"
    assert "cpf" not in str(r)
    assert adm.cliente.get(f"{BASE}/usuarios/cli-1", headers=n1).status_code == 200
    assert adm.cliente.get(f"{BASE}/usuarios/xx", headers=n1).status_code == 404


def test_dados_pessoais_exigem_motivo_e_registram_so_os_campos(adm):
    url = f"{BASE}/usuarios/cli-1/dados-pessoais"
    assert adm.cliente.post(url, json={}, headers=cab("t-dpo")).status_code == 422
    assert adm.cliente.post(url, json={"motivo": "   "}, headers=cab("t-dpo")).status_code == 422

    r = adm.cliente.post(url, json={"motivo": "Pedido do titular nº 42"}, headers=cab("t-dpo"))

    assert r.status_code == 200 and r.json()["cpf"] == "123.456.789-09"
    lista = adm.cliente.get(f"{BASE}/auditoria?acao=dado_pessoal.", headers=cab("t-seguranca"))
    entrada = lista.json()["itens"][0]
    assert entrada["motivo"] == "Pedido do titular nº 42" and entrada["ator_id"] == "eq-dpo"
    assert "123.456" not in str(entrada)  # a trilha guarda quais campos, nunca os valores


def test_dados_pessoais_de_quem_nao_existe_da_404_sem_auditar(adm):
    url = f"{BASE}/usuarios/xx/dados-pessoais"
    r = adm.cliente.post(url, json={"motivo": "Teste de 404"}, headers=cab("t-dpo"))
    assert r.status_code == 404
    assert adm.cliente.get(f"{BASE}/auditoria", headers=cab("t-dpo")).json()["total"] == 0


def test_detalhe_do_pedido_nao_vaza_codigos(adm):
    adm.semear_disputa()
    n1 = cab("t-atendente_n1")
    r = adm.cliente.get(f"{BASE}/pedidos/{PEDIDO}", headers=n1)
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["cliente"]["nome"] == "Maria Cliente" and corpo["tem_disputa"] is True
    assert "1234" not in r.text and "9876" not in r.text
    busca = adm.cliente.get(f"{BASE}/pedidos?estado=em_disputa", headers=n1).json()
    assert busca["total"] == 1 and busca["itens"][0]["valor_centavos"] == 100_000
    assert adm.cliente.get(f"{BASE}/pedidos/xx", headers=n1).status_code == 404


# --- Pagamentos: leitura -----------------------------------------------------------------------


def test_pagamentos_resumo_extrato_e_webhook_em_leitura(adm):
    adm.semear_disputa()
    objeto = {"id": "pi_teste_1", "amount_received": 100_000, "metadata": {"pedido_id": PEDIDO}}
    adm.contexto.eventos_webhook.registrar(
        EventoWebhook(
            "stripe", "evt_1", "payment_intent.succeeded", {"data": {"object": objeto}}, AGORA
        )
    )
    fin = cab("t-financeiro")

    pagamentos = adm.cliente.get(f"{BASE}/pagamentos", headers=fin).json()
    assert pagamentos["itens"][0]["valor_centavos"] == 100_000
    assert pagamentos["itens"][0]["referencia_provedor"] == "pi_teste_1"
    assert pagamentos["itens"][0]["divergente"] is False
    resumo = adm.cliente.get(f"{BASE}/pagamentos/resumo", headers=fin).json()
    assert resumo["confirmado_centavos"] == 100_000 and resumo["retido_centavos"] == 100_000
    evento = adm.cliente.get(f"{BASE}/webhooks/eventos", headers=fin).json()["itens"][0]
    assert evento["pedido_id"] == PEDIDO and evento["valor_centavos"] == 100_000
    assert "payload" not in evento
    extrato = adm.cliente.get(f"{BASE}/contratos/{PEDIDO}/extrato", headers=fin).json()
    assert extrato["valor_contrato_centavos"] == 100_000
    assert extrato["saldo"]["retido_centavos"] == 100_000
    assert [i["tipo"] for i in extrato["lancamentos"]] == ["cobranca"]
    assert adm.cliente.get(f"{BASE}/contratos/xx/extrato", headers=fin).status_code == 404
    assert adm.cliente.get(f"{BASE}/lancamentos?tipo=cobranca", headers=fin).json()["total"] == 1


def test_cobranca_sem_pedido_aparece_como_divergente(adm):
    registrar_cobranca(adm.contexto.ledger.livro, "ped-fantasma", 5_000, "cob-x", AGORA)
    fin = cab("t-financeiro")
    assert (
        adm.cliente.get(f"{BASE}/pagamentos?apenas_divergentes=true", headers=fin).json()["total"]
        == 1
    )
    assert adm.cliente.get(f"{BASE}/pagamentos/resumo", headers=fin).json()["divergencias"] == 1


def test_nao_existe_escrita_nem_saque_nem_saldo_proprio(adm):
    rotas = {
        (metodo.upper(), caminho)
        for caminho, metodos in adm.cliente.app.openapi()["paths"].items()
        if caminho.startswith("/v1/admin")
        for metodo in metodos
    }
    assert rotas
    for metodo, caminho in rotas:
        if any(p in caminho for p in ("pagamentos", "lancamentos", "webhooks", "contratos")):
            assert metodo == "GET", (metodo, caminho)
        assert not any(p in caminho for p in ("saque", "saldo", "pix", "repasse"))
    assert (
        adm.cliente.post(f"{BASE}/pagamentos", json={}, headers=cab("t-financeiro")).status_code
        == 405
    )


# --- Auditoria ----------------------------------------------------------------------------------


def test_auditoria_filtros_e_cadeia(adm):
    cadastro = cab("t-cadastro")
    aprovar = {"aprovar": True, "motivo": "Tudo conferido"}
    adm.cliente.post(f"{BASE}/verificacoes/ver-1/decisao", json=aprovar, headers=cadastro)
    adm.relogio.avancar(minutes=5)
    dados = {"motivo": "Pedido do titular"}
    adm.cliente.post(f"{BASE}/usuarios/cli-1/dados-pessoais", json=dados, headers=cadastro)
    seg = cab("t-seguranca")

    tudo = adm.cliente.get(f"{BASE}/auditoria", headers=seg).json()
    assert tudo["total"] == 2 and tudo["itens"][0]["acao"] == "dado_pessoal.revelado"
    so_verif = adm.cliente.get(f"{BASE}/auditoria?acao=verificacao.", headers=seg).json()
    assert [i["acao"] for i in so_verif["itens"]] == ["verificacao.aprovada"]
    por_ator = adm.cliente.get(
        f"{BASE}/auditoria?ator_id=eq-cadastro&entidade=verificacoes", headers=seg
    )
    assert por_ator.json()["total"] == 1
    assert adm.cliente.get(f"{BASE}/auditoria?ator_id=outro", headers=seg).json()["total"] == 0
    pagina = adm.cliente.get(f"{BASE}/auditoria?limite=1&deslocamento=1", headers=seg).json()
    assert pagina["itens"][0]["acao"] == "verificacao.aprovada"

    ok = adm.cliente.post(f"{BASE}/auditoria/verificar-cadeia", headers=seg).json()
    assert ok["integra"] is True and ok["primeira_falha_id"] is None


def test_cadeia_acusa_linha_adulterada(adm):
    for i in range(3):
        adm.admin.auditoria.registrar(
            ator_id="eq-administrador", acao=f"teste.acao{i}", motivo="motivo"
        )
    adm.admin.auditoria.adulterar_para_teste(2, motivo="reescrito depois")

    r = adm.cliente.post(f"{BASE}/auditoria/verificar-cadeia", headers=cab("t-juridico")).json()

    assert r["integra"] is False and r["primeira_falha_id"] == 2
