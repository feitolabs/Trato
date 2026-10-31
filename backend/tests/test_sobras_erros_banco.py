"""B3 (revisão de segurança): a recusa do gatilho não devolve uuid nem detalhe interno."""

from trato.persistencia.erros import texto_seguro

PADRAO = "O banco recusou a gravação."


def test_b3_mensagem_com_uuid_vira_texto_fixo():
    msg = "Lançamento 3f2b8c1e-aaaa-4bbb-8ccc-1234567890ab desequilibrado: débitos 10 x créditos 9"
    assert texto_seguro(msg, PADRAO) == PADRAO


def test_b3_mensagem_nossa_sem_identificador_passa():
    assert texto_seguro("Disputa já decidida.", PADRAO) == "Disputa já decidida."


def test_b3_mensagem_vazia_usa_padrao():
    assert texto_seguro(None, PADRAO) == PADRAO


def test_b7_cartao_declara_captura_e_3ds_no_payment_intent():
    from trato.pagamentos.modelos import MeioPagamento
    from trato.pagamentos.provedor.stripe_teste import ProvedorStripeTeste

    chamadas = []

    def transporte(metodo, caminho, campos, cabecalhos):
        chamadas.append(dict(campos))
        return 200, {"id": "pi_1", "amount": 100, "status": "requires_payment_method"}

    stripe = ProvedorStripeTeste("sk_test_" + "x" * 12, "segredo", transporte)
    stripe.criar_cobranca(
        valor_centavos=100, meio=MeioPagamento.CARTAO, chave_idempotencia="c", metadados={}
    )
    campos = chamadas[0]
    assert campos["capture_method"] == "automatic"
    assert campos["payment_method_options[card][request_three_d_secure]"] == "automatic"
