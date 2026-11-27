"""Rotas do usuário para pedido de revisão de avaliação (Termos 12.6 e 12.7)."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.disputas.prazos import adicionar_dias_uteis
from trato.persistencia.avaliacoes_moderacao import (
    PRAZO_REVISAO_PADRAO_DIAS_UTEIS,
    RevisaoAvaliacao,
)

router = APIRouter(prefix="/v1", tags=["avaliações"])

TipoRevisao = Literal["revisao", "contestacao_ocultacao"]


class AbrirRevisaoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    justificativa: str = Field(min_length=10, max_length=2000)
    tipo: TipoRevisao = "revisao"
    anexos: list[str] = Field(default_factory=list, max_length=10)


class RevisaoAvaliacaoUsuarioOut(BaseModel):
    id: str
    protocolo: str
    avaliacao_id: str
    tipo: TipoRevisao
    ocultacao_id: str | None = None
    justificativa: str
    anexos: list[str]
    canal: str
    status: str
    aberta_em: datetime
    responder_ate: datetime
    resposta: str | None = None
    decidida_em: datetime | None = None


class PaginaRevisoesUsuarioOut(BaseModel):
    itens: list[RevisaoAvaliacaoUsuarioOut]
    total: int
    limite: int
    deslocamento: int


def _out(r: RevisaoAvaliacao) -> RevisaoAvaliacaoUsuarioOut:
    return RevisaoAvaliacaoUsuarioOut(
        id=r.id,
        protocolo=r.protocolo,
        avaliacao_id=r.avaliacao_id,
        tipo=r.tipo,  # type: ignore[arg-type]
        ocultacao_id=r.ocultacao_id,
        justificativa=r.justificativa,
        anexos=list(r.anexos),
        canal=r.canal,
        status=r.status,
        aberta_em=r.aberta_em,
        responder_ate=r.responder_ate,
        resposta=r.resposta,
        decidida_em=r.decidida_em,
    )


def _exigir_tabelas(contexto: Contexto) -> None:
    if not contexto.avaliacoes_moderacao.disponivel():
        raise HTTPException(
            503,
            "Revisão de avaliações indisponível: as tabelas ainda não existem no banco de dados.",
        )


def _prazo_dias_uteis(contexto: Contexto) -> int:
    valor = contexto.config.parametro_inteiro("avaliacao_revisao_resposta_dias_uteis")
    if valor is not None and 1 <= valor <= 30:
        return valor
    return PRAZO_REVISAO_PADRAO_DIAS_UTEIS


@router.post(
    "/avaliacoes/{avaliacao_id}/revisoes",
    response_model=RevisaoAvaliacaoUsuarioOut,
    status_code=201,
    summary="Solicitar revisão de avaliação ou contestar ocultação (Termos 12.6 e 12.7)",
)
def abrir_revisao_avaliacao(
    avaliacao_id: str,
    corpo: AbrirRevisaoIn,
    resposta: Response,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> RevisaoAvaliacaoUsuarioOut:
    _exigir_tabelas(contexto)
    avaliacao = contexto.avaliacoes.obter_por_id(avaliacao_id)
    if avaliacao is None:
        raise HTTPException(404, "Avaliação não encontrada.")

    ocultacao_id: str | None = None
    if corpo.tipo == "revisao":
        if avaliacao.avaliado_id != usuario.id:
            raise HTTPException(403, "Só quem foi avaliado pode pedir revisão da avaliação.")
    else:
        if avaliacao.avaliador_id != usuario.id:
            raise HTTPException(403, "Só quem escreveu a avaliação pode contestar a ocultação.")
        ativa = contexto.avaliacoes_moderacao.ocultacao_ativa(avaliacao_id)
        if ativa is None:
            raise HTTPException(409, "Esta avaliação não tem ocultação ativa para contestar.")
        ocultacao_id = ativa.id

    agora = contexto.agora()
    responder_ate = adicionar_dias_uteis(agora, _prazo_dias_uteis(contexto))
    rev, eh_nova, _ = contexto.avaliacoes_moderacao.abrir_revisao(
        avaliacao_id=avaliacao_id,
        tipo=corpo.tipo,
        ocultacao_id=ocultacao_id,
        solicitante_id=usuario.id,
        justificativa=corpo.justificativa,
        anexos=tuple(corpo.anexos),
        canal="app",
        agora=agora,
        responder_ate=responder_ate,
    )
    if rev is None:
        raise HTTPException(409, "Não foi possível registrar o pedido de revisão.")
    if not eh_nova:
        resposta.status_code = 200
    return _out(rev)


@router.get(
    "/me/avaliacoes/revisoes",
    response_model=PaginaRevisoesUsuarioOut,
    summary="Listar meus pedidos de revisão de avaliação",
)
def listar_minhas_revisoes(
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> PaginaRevisoesUsuarioOut:
    _exigir_tabelas(contexto)
    itens, total = contexto.avaliacoes_moderacao.listar_revisoes_do_usuario(
        usuario.id, limite, deslocamento
    )
    return PaginaRevisoesUsuarioOut(
        itens=[_out(r) for r in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )
