"""Correções de dinheiro da revisão de segurança (A7, M1, M3) com o provedor falso e memória."""

from __future__ import annotations

import json

from test_fluxo_pagamento_e2e import VALOR, Fluxo, _abrir_e_responder_disputa, fluxo  # noqa: F401

from trato.financeiro.ledger import TipoLancamento
from trato.pagamentos.provedor import TipoEvento


def _decidir_reembolso_total(fluxo: Fluxo, pid: str):  # noqa: F811
    decisao = {"resultado": "reembolso_total", "justificativa": "Serviço não feito."}
    return fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-equipe", decisao)


# --- A7: a intenção entra no ledger antes do provedor ----------------------------------------


def test_a7_provedor_fora_do_ar_deixa_a_ordem_pendente_e_a_reconciliacao_reenvia(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    estornar = fluxo.fake.estornar

    def cai(*args, **kwargs):
        raise RuntimeError("provedor fora do ar")

    fluxo.fake.estornar = cai
    r = _decidir_reembolso_total(fluxo, pid)

    # O ledger e o pedido já registram a devolução; a ordem ao provedor fica pendente.
    assert r.status_code == 200, r.text
    assert TipoLancamento.ESTORNO in fluxo.tipos(pid)
    (ordem,) = fluxo.servico.ordens.pendentes(pid)
    assert ordem.valor_centavos == VALOR and ordem.estado == "pendente"

    fluxo.fake.estornar = estornar  # o provedor voltou
    assert fluxo.servico.reenviar_estornos() == 1
    assert fluxo.servico.ordens.pendentes(pid) == []
    chamadas = [c for c in fluxo.fake.chamadas if c[0] == "estornar"]
    assert chamadas == [("estornar", ordem.chave)]  # a chave da ordem é a idempotência no provedor
    assert fluxo.servico.reenviar_estornos() == 0  # nada duplica


def test_a7_a_chave_do_estorno_nao_depende_de_contagem(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "desisti"})
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert ordem.chave.startswith(f"din/{pid}/cancelamento/")


# --- M1: valor pago conferido ----------------------------------------------------------------


def test_m1_evento_sem_valor_inteiro_nao_confirma_o_pagamento(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    instante = int(fluxo.amb.relogio.agora.timestamp())
    corpo = json.dumps(
        {
            "id": "evt_sem_valor",
            "type": "payment_intent.succeeded",
            "created": instante,
            "data": {
                "object": {
                    "id": cobranca["id"],
                    "metadata": {"pedido_id": pid},
                    "amount_received": "100000",  # texto, não inteiro
                }
            },
        },
        separators=(",", ":"),
    ).encode()
    cabecalhos = {"Stripe-Signature": fluxo.fake.assinar(corpo, instante)}

    r = fluxo.http.post("/v1/webhooks/stripe", content=corpo, headers=cabecalhos)

    assert r.status_code == 200  # sem 422 em loop
    assert fluxo.pedido(pid)["estado"] == "orcamento_aceito"
    assert fluxo.tipos(pid) == []
    assert len(fluxo.ctx.eventos_webhook.em_revisao()) == 1


# --- M3: charge.refunded concilia o reembolso feito por fora ---------------------------------


def test_m3_reembolso_feito_no_painel_do_provedor_entra_no_ledger_e_gera_alerta(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)

    r = fluxo.webhook(TipoEvento.ESTORNO_CONFIRMADO, cobranca["id"], valor_centavos=30_000)

    assert r.status_code == 200
    saldo = fluxo.saldo(pid)
    assert saldo["cliente_pagou_centavos"] == VALOR - 30_000
    assert saldo["retido_centavos"] == VALOR - 30_000
    assert fluxo.servico.cobrancas.obter(cobranca["id"]).estornado_centavos == 30_000
    (alerta,) = fluxo.ctx.eventos_webhook.em_revisao()
    assert "por fora" in alerta[1] and "conciliado" in alerta[1]
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_m3_confirmacao_do_estorno_que_o_trato_mandou_nao_lanca_de_novo(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "desisti"})
    antes = list(fluxo.ctx.ledger.lancamentos(pid))

    r = fluxo.webhook(TipoEvento.ESTORNO_CONFIRMADO, cobranca["id"], valor_centavos=VALOR)

    assert r.status_code == 200
    assert list(fluxo.ctx.ledger.lancamentos(pid)) == antes
    assert fluxo.ctx.eventos_webhook.em_revisao() == ()


def test_m3_reembolso_por_fora_de_valor_ja_repassado_fica_so_como_alerta(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)  # a custódia foi repartida: parte do profissional já está a liberar
    cobranca = fluxo.servico.cobrancas.do_pedido(pid)[0]
    liberado = fluxo.repasse(pid)
    fluxo.liquidar(pid, cobranca.id)  # o provedor já liquidou ao profissional
    assert liberado.valor_liquido_centavos > 0

    r = fluxo.webhook(TipoEvento.ESTORNO_CONFIRMADO, cobranca.id, valor_centavos=VALOR)

    assert r.status_code == 200  # nunca 5xx em loop
    (alerta,) = fluxo.ctx.eventos_webhook.em_revisao()
    assert "não foi lançado" in alerta[1]
