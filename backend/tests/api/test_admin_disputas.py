"""Decisão de disputa pela equipe: alçada, segunda pessoa, espelho no ledger, auditoria."""

import pytest
from admin_ambiente import AGORA, PEDIDO, adm, cab  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.financeiro.ledger import CUSTODIA
from trato.pedidos.estados import Estado

URL = f"/v1/admin/disputas/{PEDIDO}"
DECISAO = f"{URL}/decisao"
APROVACAO = f"{URL}/aprovacao"
JUSTIFICATIVA = "Fotos mostram o serviço fora do combinado"


def decidir(adm, resultado, quem="t-mediador", **extra):
    corpo = {"resultado": resultado, "justificativa": JUSTIFICATIVA, **extra}
    return adm.cliente.post(DECISAO, json=corpo, headers=cab(quem))


def por_tipo(adm):
    soma: dict[str, int] = {}
    for i in adm.lancamentos():
        soma[i.tipo.value] = soma.get(i.tipo.value, 0) + i.valor
    return soma


# --- Fila e detalhe --------------------------------------------------------------------------


def test_fila_mostra_so_o_que_falta_decidir_e_filtra_por_estado(adm):
    adm.semear_disputa()
    fila = adm.cliente.get("/v1/admin/disputas", headers=cab("t-atendente_n2")).json()
    assert fila["total"] == 1 and fila["itens"][0]["estado"] == "em_analise"
    assert fila["itens"][0]["valor_congelado_centavos"] == 100_000
    so_abertas = adm.cliente.get("/v1/admin/disputas?estado=aberta", headers=cab("t-mediador"))
    assert so_abertas.json()["total"] == 0
    decidir(adm, "liberar_tudo")
    assert adm.cliente.get("/v1/admin/disputas", headers=cab("t-mediador")).json()["total"] == 0
    decididas = adm.cliente.get("/v1/admin/disputas?estado=decidida", headers=cab("t-mediador"))
    assert decididas.json()["total"] == 1


def test_detalhe_traz_evidencias_sem_codigos_e_linha_do_tempo(adm):
    adm.semear_disputa()
    r = adm.cliente.get(URL, headers=cab("t-mediador"))
    assert r.status_code == 200
    corpo = r.json()
    assert (
        corpo["cliente"]["nome"] == "Maria Cliente"
        and corpo["profissional"]["nome"] == "João Pintor"
    )
    assert corpo["evidencias"][0]["origem"] == "abrir_disputa"
    assert corpo["evidencias"][0]["dados"]["descricao"] == "Parede manchada"
    assert "1234" not in r.text and "9876" not in r.text and "codigo" not in r.text
    acoes = [e["acao"] for e in corpo["linha_do_tempo"]]
    assert acoes[0] in ("abrir_disputa", "disputa_aberta") and "disputa_respondida" in acoes
    assert [e["em"] for e in corpo["linha_do_tempo"]] == sorted(
        e["em"] for e in corpo["linha_do_tempo"]
    )
    assert adm.cliente.get("/v1/admin/disputas/xx", headers=cab("t-mediador")).status_code == 404


# --- Decisão dentro da alçada ----------------------------------------------------------------------


def test_liberar_tudo_conclui_reparte_a_custodia_e_audita(adm):
    adm.semear_disputa()

    r = decidir(adm, "liberar_tudo")

    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["estado"] == "decidida" and corpo["decidido_por"] == "eq-mediador"
    assert corpo["divisao"]["para_profissional_centavos"] == 100_000
    assert adm.pedido().estado is Estado.CONCLUIDO
    assert por_tipo(adm) == {"cobranca": 100_000, "retencao": 92_500, "taxa": 7_500}
    assert adm.contexto.ledger.saldo_da_conta(CUSTODIA, PEDIDO) == 0
    assert adm.contexto.garantias.obter_garantia(PEDIDO) is not None
    reg, _ = adm.admin.auditoria.listar(FiltroAuditoria(acao="financeiro."), 5, 0)
    assert reg[0].acao == "financeiro.disputa_decidida" and reg[0].motivo == JUSTIFICATIVA
    assert reg[0].depois["para_profissional_centavos"] == 100_000
    assert [e.acao.value for e in adm.contexto.pedidos.eventos(PEDIDO)][-1] == "decidir_disputa"


def test_reembolso_total_cancela_e_devolve_tudo_ao_cliente(adm):
    adm.semear_disputa()

    r = decidir(adm, "reembolso_total")

    assert r.status_code == 200
    assert adm.pedido().estado is Estado.CANCELADO
    assert por_tipo(adm) == {"cobranca": 100_000, "estorno": 100_000}
    assert adm.contexto.ledger.saldo_da_conta(CUSTODIA, PEDIDO) == 0


def test_reembolso_parcial_por_percentual_divide_sem_perder_centavo(adm):
    adm.semear_disputa()

    r = decidir(adm, "reembolso_parcial", percentual_cliente_bps=2500)

    assert r.status_code == 200
    d = r.json()["divisao"]
    assert (d["para_cliente_centavos"], d["para_profissional_centavos"]) == (25_000, 75_000)
    assert adm.pedido().estado is Estado.CONCLUIDO
    soma = por_tipo(adm)
    assert soma["estorno"] == 25_000 and soma["taxa"] == 5_625 and soma["retencao"] == 69_375
    assert 25_000 + 5_625 + 69_375 == 100_000


def test_reembolso_parcial_por_valor(adm):
    adm.semear_disputa()
    r = decidir(adm, "reembolso_parcial", valor_cliente_centavos=30_001)
    assert r.json()["divisao"]["para_cliente_centavos"] == 30_001
    assert por_tipo(adm)["estorno"] == 30_001


def test_nova_visita_vira_retrabalho_e_o_valor_segue_retido(adm):
    adm.semear_disputa()

    r = decidir(adm, "nova_visita")

    assert r.status_code == 200
    assert adm.pedido().estado is Estado.RETRABALHO
    assert por_tipo(adm) == {"cobranca": 100_000}
    assert r.json()["divisao"]["retido_centavos"] == 100_000


@pytest.mark.parametrize(
    "extra",
    [
        {},  # parcial sem percentual nem valor
        {"percentual_cliente_bps": 2500, "valor_cliente_centavos": 10},  # os dois
        {"valor_cliente_centavos": 100_000},  # reembolso parcial = o total
    ],
)
def test_parcial_mal_formado_da_422_sem_mexer_em_nada(adm, extra):
    adm.semear_disputa()
    assert decidir(adm, "reembolso_parcial", **extra).status_code == 422
    assert adm.pedido().estado is Estado.EM_DISPUTA and len(adm.lancamentos()) == 1


def test_justificativa_e_obrigatoria(adm):
    adm.semear_disputa()
    for corpo in (
        {"resultado": "liberar_tudo"},
        {"resultado": "liberar_tudo", "justificativa": " "},
    ):
        assert adm.cliente.post(DECISAO, json=corpo, headers=cab("t-mediador")).status_code == 422
    assert decidir(adm, "inventado").status_code == 422
    assert adm.pedido().estado is Estado.EM_DISPUTA


# --- Alçada e segunda pessoa -----------------------------------------------------------------------


def test_sem_alcada_a_decisao_espera_a_segunda_pessoa_e_nada_se_move(adm):
    adm.semear_disputa()

    r = decidir(adm, "reembolso_total", quem="t-mediador_sem_alcada")

    assert r.status_code == 200
    corpo = r.json()
    assert corpo["estado"] == "aguardando_aprovacao" and corpo["aguardando_segunda_pessoa"] is True
    assert corpo["divisao"] is None and corpo["decisao"] == "reembolso_total"
    assert adm.pedido().estado is Estado.EM_DISPUTA and len(adm.lancamentos()) == 1
    reg, _ = adm.admin.auditoria.listar(FiltroAuditoria(acao="financeiro."), 5, 0)
    assert reg[0].acao == "financeiro.disputa_decisao_proposta"


def test_quem_decidiu_nao_aprova_a_propria_decisao(adm):
    adm.semear_disputa()
    # O líder de baixa alçada decide (vai para aprovação) e tem o papel de segunda pessoa.
    assert (
        decidir(adm, "liberar_tudo", quem="t-lider_baixa").json()["estado"]
        == "aguardando_aprovacao"
    )

    r = adm.cliente.post(
        APROVACAO, json={"justificativa": "Eu mesmo aprovo"}, headers=cab("t-lider_baixa")
    )

    assert r.status_code == 403
    assert adm.pedido().estado is Estado.EM_DISPUTA and len(adm.lancamentos()) == 1


def test_papel_sem_segunda_pessoa_nao_aprova(adm):
    adm.semear_disputa()
    decidir(adm, "liberar_tudo", quem="t-mediador_sem_alcada")
    r = adm.cliente.post(APROVACAO, json={"justificativa": "Concordo"}, headers=cab("t-mediador"))
    assert r.status_code == 403


def test_aprovador_com_alcada_menor_que_o_valor_e_barrado_exceto_administrador(adm):
    adm.semear_disputa()
    decidir(adm, "reembolso_total", quem="t-mediador_sem_alcada")
    corpo = {"justificativa": "Concordo com a decisão"}

    baixo = adm.cliente.post(APROVACAO, json=corpo, headers=cab("t-lider_baixa"))
    assert baixo.status_code == 403 and adm.pedido().estado is Estado.EM_DISPUTA

    ok = adm.cliente.post(APROVACAO, json=corpo, headers=cab("t-lider_suporte"))
    assert ok.status_code == 200, ok.text
    assert ok.json()["estado"] == "decidida" and ok.json()["aprovado_por"] == "eq-lider_suporte"
    assert adm.pedido().estado is Estado.CANCELADO
    assert por_tipo(adm) == {"cobranca": 100_000, "estorno": 100_000}


def test_administrador_aprova_acima_da_propria_alcada(adm):
    adm.semear_disputa(valor=900_000)
    assert (
        decidir(adm, "liberar_tudo", quem="t-mediador").json()["estado"] == "aguardando_aprovacao"
    )
    r = adm.cliente.post(
        APROVACAO, json={"justificativa": "Valor alto, conferido"}, headers=cab("t-administrador")
    )
    assert r.status_code == 200 and r.json()["estado"] == "decidida"
    assert adm.pedido().estado is Estado.CONCLUIDO


def test_aprovar_sem_decisao_pendente_da_409(adm):
    adm.semear_disputa()
    r = adm.cliente.post(
        APROVACAO, json={"justificativa": "Nada a aprovar"}, headers=cab("t-administrador")
    )
    assert r.status_code == 409


# --- Estado, idempotência e falhas -----------------------------------------------------------------


def test_repetir_a_decisao_da_409_e_nao_duplica_lancamentos(adm):
    adm.semear_disputa()
    assert decidir(adm, "liberar_tudo").status_code == 200
    antes = list(adm.lancamentos())

    r = decidir(adm, "liberar_tudo")

    assert r.status_code == 409
    assert list(adm.lancamentos()) == antes


def test_disputa_ainda_no_prazo_do_profissional_nao_se_decide(adm):
    adm.semear_disputa(responder=False)
    assert decidir(adm, "liberar_tudo").status_code == 409


def test_profissional_que_nao_respondeu_no_prazo_deixa_decidir(adm):
    adm.semear_disputa(responder=False)
    adm.relogio.avancar(days=3)
    r = decidir(adm, "liberar_tudo")
    assert r.status_code == 200 and r.json()["sem_resposta"] is True


def test_pedido_fora_de_em_disputa_recusa_antes_de_mexer_no_ledger(adm):
    adm.semear_disputa(estado_pedido=Estado.EM_CONFIRMACAO)
    r = decidir(adm, "reembolso_total")
    assert r.status_code == 409
    assert len(adm.lancamentos()) == 1
    assert adm.contexto.disputas.obter(PEDIDO).estado.value == "em_analise"


def test_sem_taxa_configurada_nao_decide_liberar_tudo(adm):
    adm.semear_disputa()
    adm.contexto.taxa = None
    assert decidir(adm, "liberar_tudo").status_code == 503
    assert adm.pedido().estado is Estado.EM_DISPUTA and len(adm.lancamentos()) == 1
    # Reembolso total não usa taxa: continua possível.
    assert decidir(adm, "reembolso_total").status_code == 200


def test_falha_no_meio_e_refeita_sem_duplicar_o_ledger(adm, monkeypatch):
    adm.semear_disputa()
    original = adm.contexto.pedidos.salvar
    chamadas = {"n": 0}

    def salvar_com_falha(*args, **kwargs):
        chamadas["n"] += 1
        if chamadas["n"] == 1:
            raise RuntimeError("banco caiu")
        return original(*args, **kwargs)

    monkeypatch.setattr(adm.contexto.pedidos, "salvar", salvar_com_falha)
    with pytest.raises(RuntimeError):
        decidir(adm, "liberar_tudo")
    depois_da_falha = list(adm.lancamentos())
    assert len(depois_da_falha) == 3  # cobrança + retenção + taxa já no espelho

    r = decidir(adm, "liberar_tudo")

    assert r.status_code == 200, r.text
    assert list(adm.lancamentos()) == depois_da_falha
    assert adm.pedido().estado is Estado.CONCLUIDO
