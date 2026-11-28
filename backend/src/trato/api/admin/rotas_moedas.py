"""Configuração das moedas do Trato no painel (valor do bônus, teto, mínimo, liga/desliga).

Mesma permissão dos cupons (promoções). Toda mudança vai para a auditoria com motivo.
"""

from __future__ import annotations

import uuid
from dataclasses import asdict, replace
from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.mudanca_moedas import ACAO_CONFIG, MudancaRecusada, autorizar
from trato.api.admin.papeis import Permissao
from trato.api.admin.rotas_avisos_previos import antecedencia_dias
from trato.api.contexto import Contexto, obter_contexto
from trato.api.moedas import (
    CARTEIRA_CLIENTE,
    CARTEIRA_PROFISSIONAL,
    TIPO_BONUS_CLIENTE,
    TIPO_BONUS_PROFISSIONAL,
    LancamentoMoeda,
    PendenteMoeda,
    dia_ref,
    mes_ref,
    vencimento_de_credito_novo,
)

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
    bonus_avaliacao_profissional_moedas: int
    exclusividade_custo_moedas: int
    exclusividade_duracao_horas: int
    exclusividade_max_simultaneas: int
    exclusividade_prazo_resposta_horas: int
    exclusividade_bloqueio_recusa_dias: int


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
    bonus_avaliacao_profissional_moedas: int | None = Field(default=None, ge=1, le=100_000)
    exclusividade_custo_moedas: int | None = Field(default=None, ge=1, le=100_000)
    exclusividade_duracao_horas: int | None = Field(default=None, ge=1, le=168)
    exclusividade_max_simultaneas: int | None = Field(default=None, ge=1, le=10)
    exclusividade_prazo_resposta_horas: int | None = Field(default=None, ge=1, le=168)
    exclusividade_bloqueio_recusa_dias: int | None = Field(default=None, ge=0, le=365)
    motivo: str = Field(min_length=10, max_length=500)
    aviso_referencia: str | None = Field(
        default=None,
        max_length=60,
        description="`referencia` do aviso dos Tratinhos. Só é exigida em mudança desfavorável.",
    )


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


@router.put(
    "/config",
    response_model=ConfigMoedasOut,
    summary="Alterar a configuração das moedas",
    responses={409: {"description": "Mudança desfavorável ainda não permitida (13.11)."}},
)
def alterar_config(
    corpo: ConfigMoedasIn,
    operador: Operador = Depends(exigir(Permissao.MOEDAS_CONFIGURAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ConfigMoedasOut | JSONResponse:
    # uma alteração por vez: conferir contra uma configuração velha deixaria piorar sem aviso
    with contexto.moedas.trava("config"):
        return _aplicar(corpo, operador, admin, contexto)


def _aplicar(
    corpo: ConfigMoedasIn, operador: Operador, admin: AdminContexto, contexto: Contexto
) -> ConfigMoedasOut | JSONResponse:
    antes = contexto.moedas.config()
    dados = corpo.model_dump(exclude={"motivo", "aviso_referencia"})
    for campo in (
        "orcamento_mensal_desconto_centavos",
        "aviso_percentual",
        "teto_desconto_cliente_mes_centavos",
        "teto_diario_desconto_centavos",
        "dias_liberacao_bonus",
        "max_reservas_abertas",
        "reserva_minutos",
        "bonus_avaliacao_profissional_moedas",
        "exclusividade_custo_moedas",
        "exclusividade_duracao_horas",
        "exclusividade_max_simultaneas",
        "exclusividade_prazo_resposta_horas",
        "exclusividade_bloqueio_recusa_dias",
    ):
        if dados[campo] is None:  # não enviado: mantém o valor atual (não volta ao padrão)
            del dados[campo]
    novo = replace(antes, **dados)
    try:
        aviso = autorizar(
            contexto,
            admin.auditoria,
            antes,
            novo,
            corpo.aviso_referencia,
            antecedencia_dias(contexto, "tratinhos"),
        )
    except MudancaRecusada as erro:
        return JSONResponse(status_code=409, content=erro.corpo)
    contexto.moedas.salvar_config(novo)
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=ACAO_CONFIG,
        entidade="moedas_config",
        antes=asdict(antes),
        depois=asdict(novo) | ({"aviso": aviso} if aviso else {}),
        motivo=corpo.motivo,
    )
    return ConfigMoedasOut(**asdict(novo))


# --- Operações de Tratinhos por usuário (Termos I.3, 12.10, 13.9 e I.10) -----------------------

ACAO_CONCEDER = "moedas.conceder_compensacao"
ACAO_CANCELAR_FRAUDE = "moedas.cancelar_fraude"


class PendenteMoedaAdminOut(BaseModel):
    chave_idempotencia: str
    pedido_id: str | None
    quantidade: int
    liberar_em: datetime
    criada_em: datetime
    tipo_lancamento: str
    status: str


class LancamentoMoedaAdminOut(BaseModel):
    tipo: str
    quantidade: int
    carteira: str
    chave_idempotencia: str
    criada_em: datetime
    expira_em: datetime | None
    referencia_id: str | None


class MoedasUsuarioAdminOut(BaseModel):
    usuario_id: str
    saldo_cliente: int
    saldo_profissional: int
    pendentes_cliente: list[PendenteMoedaAdminOut]
    pendentes_profissional: list[PendenteMoedaAdminOut]
    extrato_cliente: list[LancamentoMoedaAdminOut]
    extrato_profissional: list[LancamentoMoedaAdminOut]


class ConcederMoedasIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    carteira: Literal["cliente", "profissional"] = CARTEIRA_CLIENTE
    quantidade: int = Field(gt=0, le=1_000_000)
    validade_dias: int | None = Field(default=None, gt=0, le=3650)
    motivo: str = Field(min_length=10, max_length=500)
    chave_idempotencia: str | None = Field(default=None, min_length=4, max_length=120)
    referencia_id: str | None = Field(default=None, max_length=120)


class ConcederMoedasOut(BaseModel):
    usuario_id: str
    carteira: str
    quantidade: int
    expira_em: datetime
    chave_idempotencia: str
    idempotente: bool
    saldo_atual: int


class CancelarFraudeMoedasIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    carteira: Literal["cliente", "profissional"] = CARTEIRA_CLIENTE
    quantidade: int = Field(default=0, ge=0, le=1_000_000)
    cancelar_pendentes: bool = False
    motivo: str = Field(min_length=10, max_length=500)
    chave_idempotencia: str | None = Field(default=None, min_length=4, max_length=120)
    referencia_id: str | None = Field(default=None, max_length=120)


class CancelarFraudeMoedasOut(BaseModel):
    usuario_id: str
    carteira: str
    quantidade_debitada: int
    pendentes_cancelados: int
    chave_idempotencia: str
    idempotente: bool
    saldo_atual: int


def _pendente_out(p: PendenteMoeda) -> PendenteMoedaAdminOut:
    return PendenteMoedaAdminOut(
        chave_idempotencia=p.chave_idempotencia,
        pedido_id=p.pedido_id,
        quantidade=p.quantidade,
        liberar_em=p.liberar_em,
        criada_em=p.criada_em,
        tipo_lancamento=p.tipo_lancamento,
        status=p.status,
    )


def _lancamento_out(item: LancamentoMoeda) -> LancamentoMoedaAdminOut:
    return LancamentoMoedaAdminOut(
        tipo=item.tipo,
        quantidade=item.quantidade,
        carteira=item.carteira,
        chave_idempotencia=item.chave_idempotencia,
        criada_em=item.criada_em,
        expira_em=item.expira_em,
        referencia_id=item.referencia_id,
    )


def _motivo_limpo(texto: str) -> str:
    limpo = texto.strip()
    if len(limpo) < 10:
        raise HTTPException(422, "Informe um motivo com pelo menos 10 caracteres.")
    return limpo


@router.get(
    "/usuarios/{usuario_id}",
    response_model=MoedasUsuarioAdminOut,
    summary="Saldo, pendentes e extrato de Tratinhos de um usuário",
)
def ver_moedas_usuario(
    usuario_id: str,
    limite: int = Query(default=30, ge=1, le=200),
    _: Operador = Depends(exigir(Permissao.MOEDAS_CONFIGURAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> MoedasUsuarioAdminOut:
    agora = contexto.agora()
    repo = contexto.moedas
    return MoedasUsuarioAdminOut(
        usuario_id=usuario_id,
        saldo_cliente=repo.saldo(usuario_id, agora, CARTEIRA_CLIENTE),
        saldo_profissional=repo.saldo(usuario_id, agora, CARTEIRA_PROFISSIONAL),
        pendentes_cliente=[
            _pendente_out(p) for p in repo.pendentes_do_usuario(usuario_id, TIPO_BONUS_CLIENTE)
        ],
        pendentes_profissional=[
            _pendente_out(p) for p in repo.pendentes_do_usuario(usuario_id, TIPO_BONUS_PROFISSIONAL)
        ],
        extrato_cliente=[
            _lancamento_out(x) for x in repo.extrato(usuario_id, limite, CARTEIRA_CLIENTE)
        ],
        extrato_profissional=[
            _lancamento_out(x) for x in repo.extrato(usuario_id, limite, CARTEIRA_PROFISSIONAL)
        ],
    )


@router.post(
    "/usuarios/{usuario_id}/conceder",
    response_model=ConcederMoedasOut,
    summary="Conceder Tratinhos como compensação (Termos I.3)",
)
def conceder_moedas(
    usuario_id: str,
    corpo: ConcederMoedasIn,
    operador: Operador = Depends(exigir(Permissao.MOEDAS_CONFIGURAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ConcederMoedasOut:
    motivo = _motivo_limpo(corpo.motivo)
    repo = contexto.moedas
    sufixo = (corpo.chave_idempotencia or "").strip() or uuid.uuid4().hex
    chave = f"admin-conceder:{usuario_id}:{corpo.carteira}:{sufixo}"
    with repo.trava(f"admin-moedas:{usuario_id}:{corpo.carteira}"):
        agora = contexto.agora()
        expira_em = (
            agora + timedelta(days=corpo.validade_dias)
            if corpo.validade_dias is not None
            else vencimento_de_credito_novo(repo.config(), agora)
        )
        saldo_antes = repo.saldo(usuario_id, agora, corpo.carteira)
        gravou = repo.lancar(
            LancamentoMoeda(
                usuario_id=usuario_id,
                tipo="ajuste",
                quantidade=corpo.quantidade,
                chave_idempotencia=chave,
                criada_em=agora,
                referencia_id=corpo.referencia_id,
                expira_em=expira_em,
                carteira=corpo.carteira,
            )
        )
        saldo_depois = repo.saldo(usuario_id, agora, corpo.carteira)
        if gravou:
            admin.auditoria.registrar(
                ator_id=operador.id,
                acao=ACAO_CONCEDER,
                entidade="moedas_lancamentos",
                entidade_id=usuario_id,
                antes={"carteira": corpo.carteira, "saldo": saldo_antes},
                depois={
                    "carteira": corpo.carteira,
                    "saldo": saldo_depois,
                    "quantidade": corpo.quantidade,
                    "expira_em": expira_em.isoformat(),
                    "chave_idempotencia": chave,
                    "referencia_id": corpo.referencia_id,
                },
                motivo=motivo,
            )
    return ConcederMoedasOut(
        usuario_id=usuario_id,
        carteira=corpo.carteira,
        quantidade=corpo.quantidade,
        expira_em=expira_em,
        chave_idempotencia=chave,
        idempotente=not gravou,
        saldo_atual=saldo_depois,
    )


@router.post(
    "/usuarios/{usuario_id}/cancelar-fraude",
    response_model=CancelarFraudeMoedasOut,
    summary="Cancelar Tratinhos por fraude (Termos 12.10, 13.9 e I.10)",
    responses={409: {"description": "Quantidade solicitada excede o saldo disponível."}},
)
def cancelar_moedas_fraude(
    usuario_id: str,
    corpo: CancelarFraudeMoedasIn,
    operador: Operador = Depends(exigir(Permissao.MOEDAS_CONFIGURAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CancelarFraudeMoedasOut:
    motivo = _motivo_limpo(corpo.motivo)
    if corpo.quantidade == 0 and not corpo.cancelar_pendentes:
        raise HTTPException(422, "Informe quantidade maior que zero ou marque cancelar_pendentes.")
    repo = contexto.moedas
    sufixo = (corpo.chave_idempotencia or "").strip() or uuid.uuid4().hex
    chave = f"admin-fraude:{usuario_id}:{corpo.carteira}:{sufixo}"
    with repo.trava(f"admin-moedas:{usuario_id}:{corpo.carteira}"):
        agora = contexto.agora()
        saldo_antes = repo.saldo(usuario_id, agora, corpo.carteira)
        if corpo.quantidade > 0 and repo.existe(chave):
            return CancelarFraudeMoedasOut(
                usuario_id=usuario_id,
                carteira=corpo.carteira,
                quantidade_debitada=corpo.quantidade,
                pendentes_cancelados=0,
                chave_idempotencia=chave,
                idempotente=True,
                saldo_atual=saldo_antes,
            )
        if corpo.quantidade > saldo_antes:
            raise HTTPException(
                409,
                f"Saldo insuficiente na carteira {corpo.carteira} "
                f"(disponível: {saldo_antes}, solicitado: {corpo.quantidade}).",
            )
        quantidade_debitada = 0
        if corpo.quantidade > 0:
            gravou = repo.lancar(
                LancamentoMoeda(
                    usuario_id=usuario_id,
                    tipo="ajuste",
                    quantidade=-corpo.quantidade,
                    chave_idempotencia=chave,
                    criada_em=agora,
                    referencia_id=corpo.referencia_id,
                    carteira=corpo.carteira,
                )
            )
            if gravou:
                quantidade_debitada = corpo.quantidade
        pendentes_cancelados = 0
        if corpo.cancelar_pendentes:
            tipo_pend = (
                TIPO_BONUS_CLIENTE
                if corpo.carteira == CARTEIRA_CLIENTE
                else TIPO_BONUS_PROFISSIONAL
            )
            for pend in repo.pendentes_do_usuario(usuario_id, tipo_pend):
                if repo.marcar_pendente(pend.chave_idempotencia, "cancelado"):
                    pendentes_cancelados += 1
        saldo_depois = repo.saldo(usuario_id, agora, corpo.carteira)
        if quantidade_debitada > 0 or pendentes_cancelados > 0:
            admin.auditoria.registrar(
                ator_id=operador.id,
                acao=ACAO_CANCELAR_FRAUDE,
                entidade="moedas_lancamentos",
                entidade_id=usuario_id,
                antes={"carteira": corpo.carteira, "saldo": saldo_antes},
                depois={
                    "carteira": corpo.carteira,
                    "saldo": saldo_depois,
                    "quantidade_debitada": quantidade_debitada,
                    "pendentes_cancelados": pendentes_cancelados,
                    "chave_idempotencia": chave,
                    "referencia_id": corpo.referencia_id,
                },
                motivo=motivo,
            )
    return CancelarFraudeMoedasOut(
        usuario_id=usuario_id,
        carteira=corpo.carteira,
        quantidade_debitada=quantidade_debitada,
        pendentes_cancelados=pendentes_cancelados,
        chave_idempotencia=chave,
        idempotente=False,
        saldo_atual=saldo_depois,
    )
