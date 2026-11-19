"""Configuração das moedas do Trato no painel (valor do bônus, teto, mínimo, liga/desliga).

Mesma permissão dos cupons (promoções). Toda mudança vai para a auditoria com motivo.
"""

from __future__ import annotations

from dataclasses import asdict, replace

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/admin/moedas", tags=["admin: moedas"])


class ConfigMoedasOut(BaseModel):
    ativo: bool
    bonus_avaliacao_moedas: int
    valor_moeda_centavos: int
    teto_mensal_moedas: int
    min_servico_centavos: int
    max_bonus_por_profissional_mes: int
    validade_dias: int | None


class ConfigMoedasIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    ativo: bool
    bonus_avaliacao_moedas: int = Field(ge=0, le=100_000)
    valor_moeda_centavos: int = Field(ge=0, le=10_000)
    teto_mensal_moedas: int = Field(ge=0, le=1_000_000)
    min_servico_centavos: int = Field(ge=0, le=100_000_000)
    max_bonus_por_profissional_mes: int = Field(ge=0, le=100)
    validade_dias: int | None = Field(default=None, gt=0, le=3650)
    motivo: str = Field(min_length=10, max_length=500)


@router.get("/config", response_model=ConfigMoedasOut, summary="Configuração das moedas")
def ver_config(
    _: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> ConfigMoedasOut:
    return ConfigMoedasOut(**asdict(contexto.moedas.config()))


@router.put("/config", response_model=ConfigMoedasOut, summary="Alterar a configuração das moedas")
def alterar_config(
    corpo: ConfigMoedasIn,
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ConfigMoedasOut:
    antes = contexto.moedas.config()
    novo = replace(antes, **corpo.model_dump(exclude={"motivo"}))
    contexto.moedas.salvar_config(novo)
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="moedas.config_alterada",
        entidade="moedas_config",
        antes=asdict(antes),
        depois=asdict(novo),
        motivo=corpo.motivo,
    )
    return ConfigMoedasOut(**asdict(novo))
