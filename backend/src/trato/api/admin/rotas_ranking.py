"""Pesos do ranking de profissionais na busca (média ponderada e nota composta).

Ler exige `config_ver`; alterar exige `config_aprovar`. Toda mudança vai para a auditoria, com
motivo. A conta do ranking fica em `profissional/ranking.py`; aqui só mudam os números.
"""

from __future__ import annotations

from dataclasses import asdict

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.profissional.ranking import ConfigRanking

router = APIRouter(prefix="/v1/admin/ranking", tags=["admin: ranking"])


class ConfigRankingOut(BaseModel):
    nota_prior: float
    prior_avaliacoes: int
    volume_referencia: int
    peso_nota: int
    peso_volume: int
    peso_verificacao: int
    peso_disponivel: int


class ConfigRankingIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    nota_prior: float = Field(ge=0, le=5)
    prior_avaliacoes: int = Field(ge=0, le=1000)
    volume_referencia: int = Field(ge=1, le=10_000)
    peso_nota: int = Field(ge=0, le=1000)
    peso_volume: int = Field(ge=0, le=1000)
    peso_verificacao: int = Field(ge=0, le=1000)
    peso_disponivel: int = Field(ge=0, le=1000)
    motivo: str = Field(min_length=10, max_length=500)


@router.get("/config", response_model=ConfigRankingOut, summary="Pesos do ranking")
def ver_config(
    _: Operador = Depends(exigir(Permissao.CONFIG_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> ConfigRankingOut:
    return ConfigRankingOut(**asdict(contexto.ranking.config()))


@router.put("/config", response_model=ConfigRankingOut, summary="Alterar os pesos do ranking")
def alterar_config(
    corpo: ConfigRankingIn,
    operador: Operador = Depends(exigir(Permissao.CONFIG_APROVAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ConfigRankingOut:
    pesos = (corpo.peso_nota, corpo.peso_volume, corpo.peso_verificacao, corpo.peso_disponivel)
    if sum(pesos) <= 0:
        raise HTTPException(422, "Pelo menos um peso precisa ser maior que zero.")
    antes = contexto.ranking.config()
    novo = ConfigRanking(**corpo.model_dump(exclude={"motivo"}))
    contexto.ranking.salvar_config(novo)
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="ranking.config_alterada",
        entidade="ranking_config",
        antes=asdict(antes),
        depois=asdict(novo),
        motivo=corpo.motivo,
    )
    return ConfigRankingOut(**asdict(novo))
