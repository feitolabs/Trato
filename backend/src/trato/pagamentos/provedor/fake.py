"""Provedor falso, determinístico, para teste e desenvolvimento. Não fala com a rede.

Os eventos saem no mesmo formato do Stripe (`Stripe-Signature` com HMAC-SHA256) e são
assinados com o segredo de TESTE informado na criação, então passam pelo receptor de webhook
de verdade.
"""

from __future__ import annotations

import hashlib
import hmac
import json
from collections.abc import Mapping, Sequence
from dataclasses import replace
from datetime import datetime
from typing import Any

from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.provedor.base import (
    CobrancaProvedor,
    ErroProvedor,
    EstornoProvedor,
    EventoProvedor,
    MovimentoProvedor,
    PreparoCartao,
    StatusCobranca,
    TipoEvento,
)
from trato.pagamentos.provedor.stripe_formato import interpretar_evento_stripe
from trato.pagamentos.webhook import verificar_assinatura

SEGREDO_DE_TESTE = "segredo-de-teste-do-provedor-fake"
INSTANTE_PADRAO = 1_793_275_200  # 2026-10-29T12:00:00Z; só um valor fixo para ser determinístico

_TIPO_STRIPE = {
    TipoEvento.PAGAMENTO_CONFIRMADO: "payment_intent.succeeded",
    TipoEvento.PAGAMENTO_FALHOU: "payment_intent.payment_failed",
    TipoEvento.ESTORNO_CONFIRMADO: "charge.refunded",
    TipoEvento.LIQUIDACAO: "payout.paid",
    TipoEvento.CONTESTACAO: "charge.dispute.created",
    TipoEvento.REPASSE_FALHOU: "payout.failed",
}


def _curto(texto: str) -> str:
    return hashlib.sha256(texto.encode()).hexdigest()[:16]


class ProvedorFake:
    nome = "fake"

    def __init__(self, segredo: str = SEGREDO_DE_TESTE) -> None:
        self._segredo = segredo
        self._cobrancas: dict[str, CobrancaProvedor] = {}
        self._por_chave: dict[str, str] = {}
        self._estornos: dict[str, EstornoProvedor] = {}
        self._estornado: dict[str, int] = {}
        self.clientes_das_cobrancas: dict[str, str] = {}
        self.chamadas: list[tuple[str, str]] = []  # (operação, chave) para os testes olharem
        self._movimentos: list[MovimentoProvedor] = []

    # --- interface ---------------------------------------------------------------------

    def criar_cobranca(
        self,
        *,
        valor_centavos: int,
        meio: MeioPagamento,
        chave_idempotencia: str,
        metadados: Mapping[str, str],
        parcelas: int = 1,
        cliente_externo: str | None = None,
    ) -> CobrancaProvedor:
        self.chamadas.append(("criar_cobranca", chave_idempotencia))
        if cliente_externo:
            self.clientes_das_cobrancas[chave_idempotencia] = cliente_externo
        if chave_idempotencia in self._por_chave:
            return self._cobrancas[self._por_chave[chave_idempotencia]]
        if isinstance(valor_centavos, bool) or not isinstance(valor_centavos, int):
            raise ErroProvedor("valor deve ser inteiro em centavos")
        if valor_centavos <= 0:
            raise ErroProvedor("valor deve ser maior que zero")
        cobranca_id = f"pi_fake_{_curto(chave_idempotencia)}"
        instrucao = (
            f"pix-copia-e-cola-fake-{cobranca_id}"
            if meio is MeioPagamento.PIX
            else f"{cobranca_id}_cliente_fake"
        )
        cobranca = CobrancaProvedor(
            cobranca_id, valor_centavos, meio, StatusCobranca.AGUARDANDO, dict(metadados), instrucao
        )
        self._cobrancas[cobranca_id] = cobranca
        self._por_chave[chave_idempotencia] = cobranca_id
        return cobranca

    def consultar_cobranca(self, cobranca_id: str) -> CobrancaProvedor:
        try:
            return self._cobrancas[cobranca_id]
        except KeyError as erro:
            raise ErroProvedor(f"cobrança {cobranca_id} não existe") from erro

    def estornar(
        self, cobranca_id: str, valor_centavos: int | None, chave_idempotencia: str
    ) -> EstornoProvedor:
        self.chamadas.append(("estornar", chave_idempotencia))
        if chave_idempotencia in self._estornos:
            return self._estornos[chave_idempotencia]
        cobranca = self.consultar_cobranca(cobranca_id)
        if cobranca.status is not StatusCobranca.PAGA:
            raise ErroProvedor("só se estorna cobrança paga")
        resta = cobranca.valor_centavos - self._estornado.get(cobranca_id, 0)
        valor = resta if valor_centavos is None else valor_centavos
        if not 0 < valor <= resta:
            raise ErroProvedor("valor do estorno fora do que resta da cobrança")
        self._estornado[cobranca_id] = self._estornado.get(cobranca_id, 0) + valor
        estorno = EstornoProvedor(f"re_fake_{_curto(chave_idempotencia)}", cobranca_id, valor, True)
        self._estornos[chave_idempotencia] = estorno
        return estorno

    def preparar_cartao(self, usuario_id: str) -> PreparoCartao:
        self.chamadas.append(("preparar_cartao", usuario_id))
        return PreparoCartao(f"cus_fake_{_curto(usuario_id)}", f"ek_test_fake_{_curto(usuario_id)}")

    def segredo_webhook(self) -> str:
        return self._segredo

    def validar_webhook(
        self, corpo: bytes, cabecalho: str | None, agora: int | None = None
    ) -> EventoProvedor:
        verificar_assinatura(corpo, cabecalho, self._segredo, agora=agora)
        evento = self.interpretar_evento(json.loads(corpo))
        if evento is None:
            raise ErroProvedor("tipo de evento que o Trato não usa")
        return evento

    def interpretar_evento(self, payload: Mapping[str, Any]) -> EventoProvedor | None:
        return interpretar_evento_stripe(payload)

    def movimentos(self, desde: datetime, ate: datetime) -> Sequence[MovimentoProvedor]:
        return tuple(m for m in self._movimentos if desde <= m.criado_em < ate)

    # --- simulação (só existe no fake) --------------------------------------------------

    def registrar_movimento(self, movimento: MovimentoProvedor) -> None:
        """Põe uma linha no extrato falso (o fake não inventa extrato sozinho)."""
        self._movimentos.append(movimento)

    def evento_assinado(
        self,
        tipo: TipoEvento,
        cobranca_id: str,
        *,
        evento_id: str | None = None,
        instante: int = INSTANTE_PADRAO,
        pedido_id: str | None = None,
        valor_centavos: int | None = None,
        segredo: str | None = None,
        repasse_id: str | None = None,
        objeto_id: str | None = None,
        tipo_stripe: str | None = None,
        status_contestacao: str = "needs_response",
        motivo_falha: str = "Conta bancária recusou o pagamento.",
    ) -> tuple[bytes, dict[str, str]]:
        """Corpo e cabeçalhos de um webhook, como o provedor mandaria. Não muda o estado."""
        cobranca = self.consultar_cobranca(cobranca_id)
        metadados = dict(cobranca.metadados)
        if pedido_id is not None:
            metadados["pedido_id"] = pedido_id
        valor = cobranca.valor_centavos if valor_centavos is None else valor_centavos
        objeto: dict[str, Any] = {
            "id": cobranca_id,
            "amount": valor,
            "currency": "brl",
            "metadata": metadados,
        }
        if tipo is TipoEvento.ESTORNO_CONFIRMADO:
            objeto = {
                "id": f"ch_fake_{_curto(cobranca_id)}",
                "payment_intent": cobranca_id,
                "amount_refunded": valor,
                "currency": "brl",
                "metadata": metadados,
            }
        elif tipo is TipoEvento.CONTESTACAO:
            objeto = {
                "id": objeto_id or f"dp_fake_{_curto(cobranca_id)}",
                "object": "dispute",
                "payment_intent": cobranca_id,
                "amount": valor,
                "currency": "brl",
                "reason": "fraudulent",
                "status": status_contestacao,
                "created": instante,
                "evidence_details": {"due_by": instante + 7 * 86_400},
                "metadata": {},
            }
        elif tipo is TipoEvento.REPASSE_FALHOU:
            metadados["cobranca_id"] = cobranca_id
            if repasse_id is not None:
                metadados["repasse_id"] = repasse_id
            objeto = {
                "id": objeto_id or f"po_fake_{_curto(cobranca_id)}",
                "amount": valor,
                "failure_message": motivo_falha,
                "metadata": metadados,
            }
        elif tipo is TipoEvento.LIQUIDACAO:
            metadados["cobranca_id"] = cobranca_id
            if repasse_id is not None:
                metadados["repasse_id"] = repasse_id
            objeto = {
                "id": objeto_id or f"po_fake_{_curto(cobranca_id)}",
                "amount": valor,
                "metadata": metadados,
            }
        nome = tipo_stripe or _TIPO_STRIPE[tipo]
        evento_id = evento_id or f"evt_fake_{nome}_{_curto(cobranca_id)}"
        corpo = json.dumps(
            {
                "id": evento_id,
                "type": nome,
                "created": instante,
                "data": {"object": objeto},
            },
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
        return corpo, {"Stripe-Signature": self.assinar(corpo, instante, segredo)}

    def assinar(self, corpo: bytes, instante: int, segredo: str | None = None) -> str:
        chave = (segredo or self._segredo).encode()
        v1 = hmac.new(chave, f"{instante}.".encode() + corpo, hashlib.sha256).hexdigest()
        return f"t={instante},v1={v1}"

    def marcar_paga(self, cobranca_id: str) -> None:
        self._mudar(cobranca_id, StatusCobranca.PAGA)

    def marcar_falha(self, cobranca_id: str) -> None:
        self._mudar(cobranca_id, StatusCobranca.FALHOU)

    def _mudar(self, cobranca_id: str, status: StatusCobranca) -> None:
        self._cobrancas[cobranca_id] = replace(self.consultar_cobranca(cobranca_id), status=status)
