"""Contestação de cartão (chargeback) e repasse que falhou, pelo webhook assinado (fake + memória)."""

from __future__ import annotations

from test_fluxo_pagamento_e2e import VALOR, Fluxo, fluxo  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.financeiro.contestacoes import StatusContestacao
from trato.pagamentos.provedor import TipoEvento

TAXA = 7_500


def _contestar(fluxo: Fluxo, cobranca_id: str, status: str, tipo: str, valor: int | None = None):  # noqa: F811
    return fluxo.webhook(
        TipoEvento.CONTESTACAO,
        cobranca_id,
        tipo_stripe=tipo,
        status_contestacao=status,
        objeto_id="dp_teste_1",
        evento_id=f"evt_{tipo}_{status}",
        valor_centavos=valor if valor is not None else VALOR + TAXA,
    )


def test_contestacao_aberta_fica_registrada_com_prazo_e_nao_mexe_no_dinheiro(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    antes = list(fluxo.ctx.ledger.lancamentos(pid))

    r = _contestar(fluxo, cobranca["id"], "needs_response", "charge.dispute.created")

    assert r.status_code == 200
    c = fluxo.ctx.contestacoes.obter("dp_teste_1")
    assert c.status is StatusContestacao.ABERTA and c.pedido_id == pid
    assert c.prazo_provas is not None and c.motivo_legivel == "Cliente diz que não fez a compra"
    assert list(fluxo.ctx.ledger.lancamentos(pid)) == antes
    assert fluxo.ctx.eventos_webhook.em_revisao() == ()


def test_contestacao_perdida_devolve_o_servico_no_ledger_uma_vez_so(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    _contestar(fluxo, cobranca["id"], "needs_response", "charge.dispute.created", VALOR)
    _contestar(fluxo, cobranca["id"], "under_review", "charge.dispute.updated", VALOR)

    r = _contestar(fluxo, cobranca["id"], "lost", "charge.dispute.closed", VALOR)
    # O provedor manda outro "closed" (evento diferente): não lança de novo.
    fluxo.webhook(
        TipoEvento.CONTESTACAO, cobranca["id"], tipo_stripe="charge.dispute.updated",
        status_contestacao="lost", objeto_id="dp_teste_1", evento_id="evt_outro",
        valor_centavos=VALOR,
    )  # fmt: skip

    assert r.status_code == 200
    c = fluxo.ctx.contestacoes.obter("dp_teste_1")
    assert c.status is StatusContestacao.PERDIDA and c.encerrada_em is not None
    saldo = fluxo.saldo(pid)
    assert saldo["retido_centavos"] == 0
    assert saldo["taxa_trato_centavos"] == TAXA  # a taxa não volta, como no reembolso
    assert fluxo.servico.cobrancas.obter(cobranca["id"]).estornado_centavos == VALOR
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_contestacao_ganha_nao_mexe_no_ledger(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    antes = list(fluxo.ctx.ledger.lancamentos(pid))
    _contestar(fluxo, cobranca["id"], "needs_response", "charge.dispute.created")

    _contestar(fluxo, cobranca["id"], "won", "charge.dispute.closed")

    assert fluxo.ctx.contestacoes.obter("dp_teste_1").status is StatusContestacao.GANHA
    assert list(fluxo.ctx.ledger.lancamentos(pid)) == antes


def test_contestacao_perdida_de_valor_ja_repassado_vira_alerta(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    cobranca = fluxo.servico.cobrancas.do_pedido(pid)[0]
    fluxo.liquidar(pid, cobranca.id)

    r = _contestar(fluxo, cobranca.id, "lost", "charge.dispute.closed", VALOR)

    assert r.status_code == 200  # nunca 5xx em loop
    (alerta,) = fluxo.ctx.eventos_webhook.em_revisao()
    assert "perdida" in alerta[1] and "não foi lançado" in alerta[1]


def test_repasse_liberado_com_contestacao_aberta_avisa_o_financeiro(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    cobranca = fluxo.servico.cobrancas.do_pedido(pid)[0]
    _contestar(fluxo, cobranca.id, "needs_response", "charge.dispute.created")

    fluxo.liquidar(pid, cobranca.id)

    (alerta,) = fluxo.ctx.eventos_webhook.em_revisao()
    assert "contestação de cartão aberta" in alerta[1]


def test_payout_que_falhou_fica_em_revisao_com_o_motivo_do_provedor(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    cobranca = fluxo.servico.cobrancas.do_pedido(pid)[0]
    repasse = fluxo.repasse(pid)

    r = fluxo.webhook(
        TipoEvento.REPASSE_FALHOU,
        cobranca.id,
        repasse_id=repasse.id,
        valor_centavos=repasse.valor_liquido_centavos,
        motivo_falha="Conta encerrada no banco.",
    )

    assert r.status_code == 200
    (alerta,) = fluxo.ctx.eventos_webhook.em_revisao()
    assert alerta[0].tipo == "payout.failed"
    assert "Conta encerrada no banco." in alerta[1] and repasse.id in alerta[1]


# --- Painel: contestações, alertas e consulta ao provedor --------------------------------------


def _painel(fluxo: Fluxo):  # noqa: F811
    """O AdminContexto do conftest vem sem pedidos e config: o financeiro precisa dos dois."""
    from trato.api.admin.memoria import (
        ConfigAdminEmMemoria,
        PedidosAdminEmMemoria,
        UsuariosAdminEmMemoria,
    )

    admin = fluxo.amb.admin
    admin.pedidos = PedidosAdminEmMemoria(fluxo.ctx, UsuariosAdminEmMemoria(admin.auditoria))
    admin.config = ConfigAdminEmMemoria(admin.auditoria)
    return admin


def test_painel_lista_contestacao_aberta_com_horas_ate_o_prazo(fluxo: Fluxo):  # noqa: F811
    _painel(fluxo)
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    _contestar(fluxo, cobranca["id"], "needs_response", "charge.dispute.created")

    r = fluxo.chamar("GET", "/v1/admin/financeiro/contestacoes?status=em_aberto", "t-financeiro")

    assert r.status_code == 200, r.text
    (item,) = r.json()
    assert item["id"] == "dp_teste_1" and item["pedido_id"] == pid
    assert item["horas_para_prazo"] == 7 * 24  # o fake põe o prazo 7 dias depois da abertura
    assert item["repasse_liberado"] is False
    proibido = fluxo.chamar("GET", "/v1/admin/financeiro/contestacoes", "t-n1")
    assert proibido.status_code == 403


def test_alertas_mostram_pagamento_parado_repasse_que_falhou_e_evento_em_revisao(fluxo: Fluxo):  # noqa: F811
    _painel(fluxo)
    parado = fluxo.aceitar()
    cobranca_parada = fluxo.cobrar(parado)
    fluxo.amb.relogio.avancar(minutes=31)
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    cobranca = fluxo.servico.cobrancas.do_pedido(pid)[0]
    fluxo.webhook(
        TipoEvento.REPASSE_FALHOU, cobranca.id, repasse_id=fluxo.repasse(pid).id,
        valor_centavos=fluxo.repasse(pid).valor_liquido_centavos,
    )  # fmt: skip

    r = fluxo.chamar("GET", "/v1/admin/financeiro/alertas", "t-financeiro")

    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["minutos_pagamento_parado"] == 30 and corpo["provedor_ligado"] is True
    assert [p["cobranca_id"] for p in corpo["pagamentos_parados"]] == [cobranca_parada["id"]]
    assert corpo["pagamentos_parados"][0]["minutos_parado"] >= 31
    (falha,) = corpo["repasses_com_falha"]
    assert falha["tipo"] == "payout.failed" and "repasse falhou" in falha["motivo"]
    assert corpo["eventos_em_revisao"] == []
    eventos = fluxo.chamar("GET", "/v1/admin/webhooks/eventos", "t-financeiro").json()["itens"]
    assert any(e["revisao"] and "repasse falhou" in e["revisao"] for e in eventos)


def test_consultar_no_provedor_orienta_reenviar_o_aviso_e_nao_marca_pago(fluxo: Fluxo):  # noqa: F811
    admin = _painel(fluxo)
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    fluxo.fake.marcar_paga(cobranca["id"])  # pago no provedor; o webhook não chegou

    r = fluxo.chamar(
        "POST", f"/v1/admin/financeiro/cobrancas/{cobranca['id']}/consultar", "t-financeiro"
    )

    assert r.status_code == 200, r.text
    assert r.json()["status_no_provedor"] == "paga"
    assert r.json()["status_no_trato"] == "aguardando"
    assert "Reenvie" in r.json()["orientacao"]
    assert fluxo.pedido(pid)["estado"] == "orcamento_aceito"  # nada virou pago (D13)
    (registro,), _ = admin.auditoria.listar(FiltroAuditoria(acao="pagamento.consultado"), 10, 0)
    assert registro.ator_id == "eq-fin"
