"""`GET /v1/config/publica`: os prazos e limites que o app mostra em texto.

Vêm da versão vigente da tabela de configuração. Assim o app não escreve "5 orçamentos em 48 horas"
fixo: se o admin muda, a tela muda junto. Só leitura, sem dado pessoal: não exige login (o
onboarding mostra os números antes de a pessoa entrar).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/config", tags=["config"])


class ConfigPublicaOut(BaseModel):
    limite_orcamentos_por_pedido: int | None = None
    validade_pedido_horas: int | None = None
    prazo_confirmacao_cliente_horas: int | None = None
    prazo_retrabalho_atendimento_dias: int | None = None
    prazo_resposta_disputa_horas: int | None = None
    prazo_liberacao_dias: int | None = None


def _horas(valor) -> int | None:  # type: ignore[no-untyped-def]
    return int(valor.total_seconds() // 3600) if valor is not None else None


@router.get("/publica", response_model=ConfigPublicaOut, summary="Prazos e limites para as telas")
def config_publica(contexto: Contexto = Depends(obter_contexto)) -> ConfigPublicaOut:
    cfg = contexto.config.carregar()
    return ConfigPublicaOut(
        limite_orcamentos_por_pedido=cfg.limite_orcamentos_por_pedido,
        validade_pedido_horas=_horas(cfg.prazos_pedido.receber_orcamentos),
        prazo_confirmacao_cliente_horas=_horas(cfg.prazos_pedido.confirmacao_cliente),
        prazo_retrabalho_atendimento_dias=cfg.garantias.prazo_atendimento_dias,
        prazo_resposta_disputa_horas=cfg.disputas.prazo_resposta_horas,
        prazo_liberacao_dias=cfg.prazo_liberacao_dias,
    )
