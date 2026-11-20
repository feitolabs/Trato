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
from trato.api.moedas import dia_ref, mes_ref

router = APIRouter(prefix="/v1/admin/moedas", tags=["admin: moedas"])


class ConfigMoedasOut(BaseModel):
    ativo: bool
    bonus_avaliacao_moedas: int
    valor_moeda_centavos: int
    teto_mensal_moedas: int
    min_servico_centavos: int
    max_bonus_por_profissional_mes: int
    max_desconto_percentual: int
    validade_dias: int | None
    orcamento_mensal_desconto_centavos: int
    aviso_percentual: int
    teto_desconto_cliente_mes_centavos: int
    teto_diario_desconto_centavos: int
    dias_liberacao_bonus: int
    max_reservas_abertas: int
    reserva_minutos: int


class ConfigMoedasIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    ativo: bool
    bonus_avaliacao_moedas: int = Field(ge=0, le=100_000)
    valor_moeda_centavos: int = Field(ge=0, le=10_000)
    teto_mensal_moedas: int = Field(ge=0, le=1_000_000)
    min_servico_centavos: int = Field(ge=0, le=100_000_000)
    max_bonus_por_profissional_mes: int = Field(ge=0, le=100)
    max_desconto_percentual: int = Field(ge=0, le=100)
    validade_dias: int | None = Field(default=None, gt=0, le=3650)
    orcamento_mensal_desconto_centavos: int | None = Field(default=None, ge=0, le=100_000_000)
    aviso_percentual: int | None = Field(default=None, ge=0, le=100)
    teto_desconto_cliente_mes_centavos: int | None = Field(default=None, ge=0, le=10_000_000)
    teto_diario_desconto_centavos: int | None = Field(default=None, ge=0, le=10_000_000)
    dias_liberacao_bonus: int | None = Field(default=None, ge=0, le=365)
    max_reservas_abertas: int | None = Field(default=None, ge=1, le=20)
    reserva_minutos: int | None = Field(default=None, ge=1, le=1440)
    motivo: str = Field(min_length=10, max_length=500)


@router.get("/config", response_model=ConfigMoedasOut, summary="Configuração das moedas")
def ver_config(
    _: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> ConfigMoedasOut:
    return ConfigMoedasOut(**asdict(contexto.moedas.config()))


class OrcamentoMoedasOut(BaseModel):
    mes_ref: str
    orcamento_centavos: int
    usado_centavos: int
    percentual_usado: float
    aviso: bool
    dia_ref: str
    usado_dia_centavos: int
    teto_dia_centavos: int


@router.get("/orcamento", response_model=OrcamentoMoedasOut, summary="Orçamento de desconto do mês")
def ver_orcamento(
    _: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> OrcamentoMoedasOut:
    cfg = contexto.moedas.config()
    mes = mes_ref(contexto.agora())
    dia = dia_ref(contexto.agora())
    usado = contexto.moedas.orcamento_usado(mes)
    orcamento = cfg.orcamento_mensal_desconto_centavos
    percentual = round(usado * 100 / orcamento, 2) if orcamento > 0 else 100.0
    aviso = usado * 100 >= cfg.aviso_percentual * orcamento if orcamento > 0 else True
    return OrcamentoMoedasOut(
        mes_ref=mes.isoformat(),
        orcamento_centavos=orcamento,
        usado_centavos=usado,
        percentual_usado=percentual,
        aviso=aviso,
        dia_ref=dia.isoformat(),
        usado_dia_centavos=contexto.moedas.orcamento_usado_dia(dia),
        teto_dia_centavos=cfg.teto_diario_desconto_centavos,
    )


@router.put("/config", response_model=ConfigMoedasOut, summary="Alterar a configuração das moedas")
def alterar_config(
    corpo: ConfigMoedasIn,
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ConfigMoedasOut:
    antes = contexto.moedas.config()
    dados = corpo.model_dump(exclude={"motivo"})
    for campo in (
        "orcamento_mensal_desconto_centavos",
        "aviso_percentual",
        "teto_desconto_cliente_mes_centavos",
        "teto_diario_desconto_centavos",
        "dias_liberacao_bonus",
        "max_reservas_abertas",
        "reserva_minutos",
    ):
        if dados[campo] is None:  # não enviado: mantém o valor atual (não volta ao padrão)
            del dados[campo]
    novo = replace(antes, **dados)
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
