"""Contestar a decisão da disputa, pelo cliente ou pelo profissional (Termos 8.7)."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api import contestacao_disputa as regras
from trato.api.ausencia_base import midia_do_pedido
from trato.api.auth import Usuario
from trato.api.contexto import Contexto, obter_contexto, usuario_do_proprio_pedido
from trato.api.servicos import carregar_pedido
from trato.persistencia.contestacoes_decisao import (
    AGUARDANDO_APROVACAO,
    EM_ANALISE,
    FINAIS,
    ContestacaoDecisao,
)

router = APIRouter(prefix="/v1/pedidos", tags=["contestação da decisão"])


class ContestarDecisaoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    o_que_faltou: str = Field(
        min_length=10, max_length=4000, description="O que a análise não considerou."
    )
    anexos: list[str] = Field(
        default_factory=list,
        max_length=10,
        description="`arquivo_id` de arquivos que a própria pessoa enviou neste pedido.",
    )


class ContestacaoDaParteOut(BaseModel):
    id: str
    protocolo: str
    minha: bool
    status: str = Field(description="aberta | em_analise | mantida | alterada | revertida")
    aberta_em: datetime
    responder_ate: datetime
    o_que_faltou: str | None = Field(None, description="Só na contestação de quem consulta.")
    anexos: list[str] = []
    resposta: str | None = None
    nova_decisao: str | None = None
    novo_valor_reembolso_centavos: int | None = None
    decidida_em: datetime | None = None


class ContestacoesDoPedidoOut(BaseModel):
    pode_contestar: bool
    contestar_ate: datetime | None = Field(None, description="null: não há disputa decidida.")
    itens: list[ContestacaoDaParteOut] = []


def _saida(item: ContestacaoDecisao, usuario_id: str) -> ContestacaoDaParteOut:
    minha = item.contestante_id == usuario_id
    final = item.status in FINAIS
    # A proposta que espera a segunda pessoa não aparece para as partes.
    status = EM_ANALISE if item.status == AGUARDANDO_APROVACAO else item.status
    return ContestacaoDaParteOut(
        id=item.id or "",
        protocolo=item.protocolo or "",
        minha=minha,
        status=status,
        aberta_em=item.aberta_em,
        responder_ate=item.responder_ate,
        o_que_faltou=item.o_que_faltou if minha else None,
        anexos=list(item.anexos) if minha else [],
        resposta=item.resposta if final else None,
        nova_decisao=item.nova_decisao if final else None,
        novo_valor_reembolso_centavos=item.novo_valor_reembolso_centavos if final else None,
        decidida_em=item.decidida_em,
    )


def anexos_da_parte(
    request: Request, pedido_id: str, usuario_id: str, anexos: list[str]
) -> tuple[str, ...] | None:
    """Só vale arquivo enviado pela própria parte neste pedido; None se algum não valer."""
    ids = tuple(dict.fromkeys(anexos))
    if not ids:
        return ()
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:
        return None
    for arquivo in ids:
        midia = midia_do_pedido(servico, arquivo, pedido_id)
        if midia is None or str(midia.enviada_por).replace("-", "") != usuario_id.replace("-", ""):
            return None
    return ids


def anexo_invalido() -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "detail": "Cada anexo precisa ter sido enviado pela própria parte, neste pedido.",
            "codigo": "anexo_invalido",
        },
    )


@router.get(
    "/{pedido_id}/disputa/contestacoes",
    response_model=ContestacoesDoPedidoOut,
    summary="Contestações da decisão e prazo para contestar",
)
def ver(
    pedido_id: str,
    usuario: Usuario = Depends(usuario_do_proprio_pedido),
    contexto: Contexto = Depends(obter_contexto),
):
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    try:
        if usuario.id not in (pedido.cliente_id, pedido.profissional_id):
            raise regras.Recusa("pedido_nao_encontrado")
        regras.exigir_tabelas(contexto)
    except regras.Recusa as erro:
        return erro.resposta()
    decidida = regras.decisao_da_disputa(contexto, pedido)
    if decidida is None:
        return ContestacoesDoPedidoOut(pode_contestar=False)
    itens = contexto.contestacoes_decisao.da_disputa(decidida.disputa_id)
    return ContestacoesDoPedidoOut(
        pode_contestar=contexto.agora() <= decidida.contestar_ate
        and all(c.contestante_id != usuario.id for c in itens),
        contestar_ate=decidida.contestar_ate,
        itens=[_saida(c, usuario.id) for c in itens],
    )


@router.post(
    "/{pedido_id}/disputa/contestacoes",
    response_model=ContestacaoDaParteOut,
    status_code=201,
    summary="Contestar a decisão da disputa (5 dias úteis)",
    description="Uma por parte. Reenviar o mesmo conteúdo responde 200 com a que já existe.",
)
def contestar(
    pedido_id: str,
    corpo: ContestarDecisaoIn,
    request: Request,
    response: Response,
    usuario: Usuario = Depends(usuario_do_proprio_pedido),
    contexto: Contexto = Depends(obter_contexto),
):
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    try:
        if usuario.id not in (pedido.cliente_id, pedido.profissional_id):
            raise regras.Recusa("pedido_nao_encontrado")
        regras.exigir_tabelas(contexto)
        decidida = regras.decisao_da_disputa(contexto, pedido)
        if decidida is None:
            raise regras.Recusa("sem_decisao")
        anexos = anexos_da_parte(request, pedido.id, usuario.id, corpo.anexos)
        if anexos is None:
            return anexo_invalido()
        item, criada = regras.abrir(
            contexto, decidida, usuario.id, corpo.o_que_faltou, anexos, "app", contexto.agora()
        )
    except regras.Recusa as erro:
        return erro.resposta()
    if not criada:
        response.status_code = 200
    return _saida(item, usuario.id)
