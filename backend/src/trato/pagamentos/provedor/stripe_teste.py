"""Provedor Stripe em MODO TESTE.

- Só aceita chave `sk_test_`/`rk_test_`: chave de produção é recusada na criação.
- A chave e o segredo do webhook vêm do .env (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`).
- O acesso à rede é um `transporte` injetado. Os testes passam um transporte simulado; só
  `transporte_urllib` fala com a internet, e ele só é usado por `ProvedorStripeTeste.do_env()`.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from typing import Any

from trato.config import obter_config
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.provedor.base import (
    CobrancaProvedor,
    ErroProvedor,
    EstornoProvedor,
    EventoProvedor,
    PreparoCartao,
    StatusCobranca,
)
from trato.pagamentos.provedor.stripe_formato import interpretar_evento_stripe
from trato.pagamentos.webhook import verificar_assinatura

URL_BASE = "https://api.stripe.com"
# Versão da API exigida pela chave efêmera: tem de ser a do SDK do app (flutter_stripe).
VERSAO_API_CHAVE_EFEMERA = "2024-06-20"
Resposta = tuple[int, Mapping[str, Any]]
# (método, caminho, campos do formulário, cabeçalhos extras) -> (status HTTP, JSON)
Transporte = Callable[[str, str, Mapping[str, str], Mapping[str, str]], Resposta]


def transporte_urllib(
    chave_secreta: str, url_base: str = URL_BASE, tempo: float = 20.0
) -> Transporte:
    """Transporte real (HTTP). Não é usado nos testes."""

    def enviar(
        metodo: str, caminho: str, campos: Mapping[str, str], cabecalhos: Mapping[str, str]
    ) -> Resposta:
        dados = urllib.parse.urlencode(campos).encode() if metodo == "POST" else None
        url = url_base + caminho
        if metodo == "GET" and campos:
            url += "?" + urllib.parse.urlencode(campos)
        pedido = urllib.request.Request(  # noqa: S310 - URL https fixa do Stripe
            url,
            data=dados,
            method=metodo,
            headers={"Authorization": f"Bearer {chave_secreta}", **cabecalhos},
        )
        try:
            with urllib.request.urlopen(pedido, timeout=tempo) as resposta:  # noqa: S310
                return resposta.status, json.loads(resposta.read())
        except urllib.error.HTTPError as erro:
            try:
                return erro.code, json.loads(erro.read())
            except ValueError:
                return erro.code, {}
        except OSError as erro:
            raise ErroProvedor("sem resposta do Stripe") from erro

    return enviar


class ProvedorStripeTeste:
    nome = "stripe_teste"

    def __init__(self, chave_secreta: str, segredo_webhook: str, transporte: Transporte) -> None:
        if not chave_secreta.startswith(("sk_test_", "rk_test_")):
            raise ErroProvedor("Use uma chave de MODO TESTE do Stripe (sk_test_...).")
        if not segredo_webhook:
            raise ErroProvedor("STRIPE_WEBHOOK_SECRET não configurado.")
        self._segredo = segredo_webhook
        self._transporte = transporte

    @classmethod
    def do_env(cls) -> ProvedorStripeTeste:
        """Lê `STRIPE_SECRET_KEY` e `STRIPE_WEBHOOK_SECRET` do .env e liga a rede de verdade."""
        config = obter_config()
        chave = config.stripe_secret_key.get_secret_value()
        return cls(chave, config.stripe_webhook_secret.get_secret_value(), transporte_urllib(chave))

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
        if parcelas != 1:
            raise ErroProvedor("Parcelamento ainda não está ligado nesta integração.")
        # A API atual do Stripe recusa `payment_method_types`: meios vêm do painel (31/10/2026).
        campos = {
            "amount": str(valor_centavos),
            "currency": "brl",
            "automatic_payment_methods[enabled]": "true",
            "automatic_payment_methods[allow_redirects]": "never",
        }
        if meio is MeioPagamento.PIX:
            campos |= {
                "payment_method_data[type]": "pix",
                "confirm": "true",
            }
        else:
            # Captura e 3DS explícitos (B7): o Stripe pede autenticação quando o banco exige.
            campos |= {
                "capture_method": "automatic",
                "payment_method_options[card][request_three_d_secure]": "automatic",
            }
            if cliente_externo:
                # Com o cliente, a folha de cartão lista os cartões salvos e guarda o novo.
                campos |= {
                    "customer": cliente_externo,
                    "setup_future_usage": "on_session",
                }
        campos |= {f"metadata[{k}]": v for k, v in metadados.items()}
        corpo = self._chamar("POST", "/v1/payment_intents", campos, chave_idempotencia)
        return self._cobranca(corpo, meio)

    def preparar_cartao(self, usuario_id: str) -> PreparoCartao:
        """Acha (ou cria) o cliente deste usuário no Stripe e gera a chave efêmera dele."""
        achados = self._chamar(
            "GET",
            "/v1/customers/search",
            {"query": f"metadata['trato_usuario_id']:'{usuario_id}'", "limit": "1"},
        ).get("data") or []
        if achados:
            cliente_id = str(achados[0]["id"])
        else:
            criado = self._chamar(
                "POST",
                "/v1/customers",
                {"metadata[trato_usuario_id]": usuario_id},
                f"cliente/{usuario_id}",
            )
            cliente_id = str(criado["id"])
        chave = self._chamar(
            "POST",
            "/v1/ephemeral_keys",
            {"customer": cliente_id},
            None,
            {"Stripe-Version": VERSAO_API_CHAVE_EFEMERA},
        )
        return PreparoCartao(cliente_id, str(chave["secret"]))

    def consultar_cobranca(self, cobranca_id: str) -> CobrancaProvedor:
        corpo = self._chamar("GET", f"/v1/payment_intents/{cobranca_id}", {})
        eh_pix = "pix" in corpo.get("payment_method_types", [])
        return self._cobranca(corpo, MeioPagamento.PIX if eh_pix else MeioPagamento.CARTAO)

    def estornar(
        self, cobranca_id: str, valor_centavos: int | None, chave_idempotencia: str
    ) -> EstornoProvedor:
        campos = {"payment_intent": cobranca_id}
        if valor_centavos is not None:
            campos["amount"] = str(valor_centavos)
        corpo = self._chamar("POST", "/v1/refunds", campos, chave_idempotencia)
        return EstornoProvedor(
            str(corpo["id"]),
            cobranca_id,
            int(corpo["amount"]),
            confirmado=corpo.get("status") == "succeeded",
        )

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

    # --- detalhes ----------------------------------------------------------------------

    def _chamar(
        self,
        metodo: str,
        caminho: str,
        campos: Mapping[str, str],
        chave: str | None = None,
        extras: Mapping[str, str] | None = None,
    ) -> Mapping[str, Any]:
        cabecalhos = {**(extras or {}), **({"Idempotency-Key": chave} if chave else {})}
        status, corpo = self._transporte(metodo, caminho, campos, cabecalhos)
        if status >= 400:
            erro = corpo.get("error", {}) if isinstance(corpo, Mapping) else {}
            raise ErroProvedor(f"Stripe recusou ({status}): {erro.get('message', 'sem detalhe')}")
        return corpo

    @staticmethod
    def _cobranca(corpo: Mapping[str, Any], meio: MeioPagamento) -> CobrancaProvedor:
        status = {
            "succeeded": StatusCobranca.PAGA,
            "canceled": StatusCobranca.CANCELADA,
        }.get(str(corpo.get("status")), StatusCobranca.AGUARDANDO)
        if status is StatusCobranca.AGUARDANDO and corpo.get("last_payment_error"):
            status = StatusCobranca.FALHOU
        instrucao = corpo.get("client_secret")
        pix = (corpo.get("next_action") or {}).get("pix_display_qr_code") or {}
        if pix.get("data"):
            instrucao = pix["data"]
        return CobrancaProvedor(
            str(corpo["id"]),
            int(corpo["amount"]),
            meio,
            status,
            {str(k): str(v) for k, v in (corpo.get("metadata") or {}).items()},
            instrucao,
        )
