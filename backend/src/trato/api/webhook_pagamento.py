"""Manipuladores do webhook de pagamento (D13): só o parceiro confirma que o cliente pagou.

Regras:
- "Pago" (e o lançamento da cobrança no ledger) só nasce aqui, de um evento com assinatura
  válida (a rota já verificou). O aviso do cliente no app só leva o pedido a
  `aguardando_confirmacao`.
- Evento fora de ordem: a confirmação pode chegar antes do aviso do cliente (vale do mesmo
  jeito) ou antes de o pedido aceitar o orçamento (`EventoForaDeOrdem`: a rota responde 409
  e o provedor reenvia depois).
- Reenvio: a rota já descarta o mesmo `evento_id`; aqui, um evento diferente sobre pedido já
  pago não repete nada (a chave do ledger é a referência do pagamento).
- Valor divergente do contrato: nada vira pago; o evento fica guardado para análise.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from trato.api.exclusividades import encerrar_na_contratacao
from trato.api.repositorios import EventoWebhook
from trato.api.validade import momento_da_confirmacao, orcamento_vencido
from trato.financeiro.ledger import CLIENTE, CUSTODIA, Lancamento, TipoLancamento
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Estado, Papel, ProvaPagamento

if TYPE_CHECKING:
    from trato.api.contexto import Contexto

SISTEMA = Ator(Papel.SISTEMA, "webhook")

TIPO_PAGAMENTO_CONFIRMADO = "payment_intent.succeeded"
TIPO_PAGAMENTO_RECUSADO = "payment_intent.payment_failed"


class EventoForaDeOrdem(Exception):
    """O evento chegou cedo demais para o estado do pedido; tentar de novo mais tarde."""


def _objeto(evento: EventoWebhook) -> dict[str, Any]:
    dados = evento.payload.get("data")
    objeto = dados.get("object") if isinstance(dados, dict) else None
    return objeto if isinstance(objeto, dict) else {}


def _pedido_id(objeto: dict[str, Any]) -> str | None:
    metadados = objeto.get("metadata")
    valor = metadados.get("pedido_id") if isinstance(metadados, dict) else None
    return valor if isinstance(valor, str) and valor else None


def confirmar_pagamento(evento: EventoWebhook, contexto: Contexto) -> None:
    objeto = _objeto(evento)
    pedido_id = _pedido_id(objeto)
    referencia = objeto.get("id")
    valor = objeto.get("amount_received", objeto.get("amount"))
    if pedido_id is None or not isinstance(referencia, str) or not referencia:
        return  # evento que não é nosso (sem pedido): guardado, sem efeito
    pedido = contexto.pedidos.obter(pedido_id)
    contrato = contexto.contratos.obter_do_pedido(pedido_id)
    if pedido is None:
        return
    if pedido.referencia_pagamento is not None:
        return  # já pago: reenvio por outro evento do mesmo pagamento não repete nada
    if any(e.acao is Acao.EXPIRAR_PAGAMENTO for e in contexto.pedidos.eventos(pedido.id)):
        # Sem o serviço de pagamento não há cobrança que diga de qual contrato é o dinheiro:
        # não contrata e deixa para o financeiro.
        contexto.eventos_webhook.marcar_revisao(
            evento, f"pagamento em pedido que já perdeu um prazo de pagamento ({referencia})"
        )
        return
    if pedido.estado not in (Estado.ORCAMENTO_ACEITO, Estado.AGUARDANDO_CONFIRMACAO):
        raise EventoForaDeOrdem(f"Pedido {pedido_id} ainda não aceita pagamento.")
    if (
        contrato is None
        or isinstance(valor, bool)
        or not isinstance(valor, int)
        or valor != contrato.valor_centavos
    ):
        return  # valor não confere com o contrato: não vira pago
    agora = contexto.agora()
    confirmado_em = momento_da_confirmacao(evento.payload, agora)
    if orcamento_vencido(contexto, contrato.orcamento_id, confirmado_em):
        # Manipulador sem serviço de pagamento: não contrata e deixa para o financeiro devolver.
        contexto.eventos_webhook.marcar_revisao(
            evento, f"pagamento depois da validade do orçamento ({referencia}): devolver"
        )
        return
    transicao = estados.transicionar(
        pedido, Acao.CONFIRMAR_PAGAMENTO, SISTEMA, agora, ProvaPagamento(referencia)
    )
    contexto.ledger.lancar_varios(
        [
            Lancamento(
                f"cobranca:{pedido_id}:{referencia}",
                pedido_id,
                TipoLancamento.COBRANCA,
                CLIENTE,
                CUSTODIA,
                valor,
                agora,
                evento_webhook_id=evento.evento_id,  # o lançamento aponta o evento (espelho)
            )
        ]
    )
    contexto.pedidos.salvar(transicao.pedido, transicao.evento)
    encerrar_na_contratacao(contexto, pedido_id, transicao.pedido.profissional_id)


def recusar_pagamento(evento: EventoWebhook, contexto: Contexto) -> None:
    pedido_id = _pedido_id(_objeto(evento))
    pedido = contexto.pedidos.obter(pedido_id) if pedido_id else None
    if pedido is None or pedido.estado is not Estado.AGUARDANDO_CONFIRMACAO:
        return  # fora de ordem (já pago) ou sem aviso do cliente: nada a desfazer
    transicao = estados.transicionar(pedido, Acao.RECUSAR_PAGAMENTO, SISTEMA, contexto.agora())
    contexto.pedidos.salvar(transicao.pedido, transicao.evento)


def manipuladores_padrao() -> dict[str, Any]:
    return {
        TIPO_PAGAMENTO_CONFIRMADO: confirmar_pagamento,
        TIPO_PAGAMENTO_RECUSADO: recusar_pagamento,
    }
