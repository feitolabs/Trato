"""Rotas da exclusividade de 48h (profissional pede, cliente responde).

Ordem no pedido do profissional: papel (profissional aprovado, pelo `exigir_papel`) -> pedido
existe (404) -> atende a categoria e a região (403) -> função SQL, cujo resultado vira 201, 200
(`ja_existe`), 409 ou 422 com um `codigo` estável. O corpo de erro é o das outras rotas
(`{"detail": "<texto>"}`) mais o campo `codigo`.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, Request
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.avisos import avisar_exclusividade_oferta, avisar_exclusividade_resposta
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.exclusividades import (
    EM_ANDAMENTO,
    ERROS_SOLICITAR,
    TEXTO_SEM_COMPROMISSO,
    Exclusividade,
)
from trato.api.moedas import saldo_profissional
from trato.api.servicos import nome_abreviado
from trato.api.visibilidade import pedido_visivel_ao_profissional
from trato.pedidos.estados import Estado

router = APIRouter(prefix="/v1", tags=["exclusividade"])


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


class SolicitarExclusividadeIn(_Entrada):
    pedido_id: str = Field(min_length=1, max_length=64)
    chave_idempotencia: str = Field(
        min_length=1, max_length=100, description="Repetir a mesma chave devolve a mesma oferta."
    )


class ResponderExclusividadeIn(_Entrada):
    decisao: Literal["aceitar", "recusar"]


class ExclusividadeOut(BaseModel):
    id: str
    pedido_id: str
    cliente_id: str
    status: str
    moedas_cobradas: int
    criada_em: datetime
    responder_ate: datetime | None = None
    respondida_em: datetime | None = None
    expira_em: datetime | None = None
    encerrada_em: datetime | None = None
    saldo_restante: int | None = Field(None, description="Só na criação: saldo depois do débito.")


class ListaExclusividadesOut(BaseModel):
    itens: list[ExclusividadeOut]
    ativas_ou_pendentes: int
    limite_maximo: int
    saldo_profissional: int


class OfertaExclusividadeOut(BaseModel):
    id: str
    pedido_id: str
    profissional_id: str
    profissional_nome: str | None
    nota_publica: float | None
    status: str = Field(description="`aguardando_cliente` ou `ativa`.")
    responder_ate: datetime | None
    expira_em: datetime | None
    texto: str = Field(default=TEXTO_SEM_COMPROMISSO)


class RespostaExclusividadeOut(BaseModel):
    id: str
    pedido_id: str
    status: str = Field(description="`ativa` (aceitou) ou `recusada`.")
    expira_em: datetime | None = None
    pedido_estado: str
    outros_orcamentos_continuam_visiveis: bool = True


def _erro(status: int, codigo: str, mensagem: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": codigo})


def _out(item: Exclusividade, saldo_restante: int | None = None) -> ExclusividadeOut:
    return ExclusividadeOut(
        id=item.id,
        pedido_id=item.pedido_id,
        cliente_id=item.cliente_id,
        status=item.status,
        moedas_cobradas=item.moedas_cobradas,
        criada_em=item.criada_em,
        responder_ate=item.responder_ate,
        respondida_em=item.respondida_em,
        expira_em=item.expira_em,
        encerrada_em=item.encerrada_em,
        saldo_restante=saldo_restante,
    )


@router.post(
    "/profissional/exclusividades",
    response_model=ExclusividadeOut,
    status_code=201,
    summary="Pedir prioridade (exclusividade) num pedido aberto",
    description=(
        "Gasta Tratinhos da carteira do profissional (nunca o orçamento de desconto). `201` cria a "
        "oferta; `200` devolve a que já existe para a mesma chave. Erros: `403` não atende o "
        "pedido, `404` pedido, `409`/`422` com `codigo` (`saldo_insuficiente`, "
        "`limite_simultaneas`, `pedido_indisponivel`, `bloqueado_recusa`, `pedido_urgente`, "
        "`categoria_sem_exclusividade`, `proprio_pedido`)."
    ),
)
def solicitar_exclusividade(
    corpo: SolicitarExclusividadeIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
):
    pedido = contexto.pedidos.obter(corpo.pedido_id)
    if pedido is None:
        return _erro(404, "pedido_nao_encontrado", "Pedido não encontrado.")
    if pedido.cliente_id == usuario.id:
        return _erro(*ERROS_SOLICITAR["proprio_pedido"])
    if (
        pedido.estado is Estado.ABERTO
        and pedido_visivel_ao_profissional(contexto, pedido.id, usuario.id) is None
    ):
        return _erro(403, "fora_da_area", "Você não atende a categoria ou a região deste pedido.")
    cfg = contexto.moedas.config()
    try:
        r = contexto.exclusividades.solicitar(
            usuario.id,
            pedido.id,
            corpo.chave_idempotencia,
            contexto.agora(),
            cfg.exclusividade_custo_moedas,
            cfg.exclusividade_max_simultaneas,
            cfg.exclusividade_prazo_resposta_horas,
            cfg.exclusividade_bloqueio_recusa_dias,
        )
    except ValueError:  # chave de idempotência de outro profissional
        return _erro(422, "chave_invalida", "Chave de idempotência inválida.")
    except Exception:  # noqa: BLE001 - tabela/função ainda não existe ou banco fora
        return _erro(503, "indisponivel", "A prioridade está indisponível no momento.")
    if r.resultado == "ok":
        item = contexto.exclusividades.obter(r.exclusividade_id or "")
        if item is None:  # nunca deveria: a função acabou de criar
            return _erro(503, "indisponivel", "A prioridade está indisponível no momento.")
        avisar_exclusividade_oferta(request, contexto, exclusividade=item)
        return _out(item, r.saldo_restante)
    if r.resultado == "ja_existe":
        item = contexto.exclusividades.obter(r.exclusividade_id or "")
        if item is None:
            return _erro(503, "indisponivel", "A prioridade está indisponível no momento.")
        return JSONResponse(status_code=200, content=jsonable_encoder(_out(item, r.saldo_restante)))
    if r.resultado in ERROS_SOLICITAR:
        return _erro(*ERROS_SOLICITAR[r.resultado])
    return _erro(503, "indisponivel", "A prioridade está indisponível no momento.")


@router.get(
    "/profissional/exclusividades",
    response_model=ListaExclusividadesOut,
    summary="Minhas exclusividades, o limite e o saldo da minha carteira",
)
def minhas_exclusividades(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ListaExclusividadesOut:
    agora = contexto.agora()
    try:
        itens = contexto.exclusividades.do_profissional(usuario.id)
    except Exception:  # noqa: BLE001 - tabela ainda não existe: lista vazia
        itens = []
    return ListaExclusividadesOut(
        itens=[_out(i) for i in itens],
        ativas_ou_pendentes=sum(1 for i in itens if i.status in EM_ANDAMENTO),
        limite_maximo=contexto.moedas.config().exclusividade_max_simultaneas,
        saldo_profissional=saldo_profissional(contexto.moedas, usuario.id, agora),
    )


@router.get(
    "/pedidos/{pedido_id}/exclusividade",
    response_model=OfertaExclusividadeOut | None,
    summary="Oferta de exclusividade pendente ou ativa do meu pedido (cliente)",
    description='`null` quando não há. O texto fixo é "Sem compromisso".',
)
def oferta_do_pedido(
    pedido_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
):
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None or pedido.cliente_id != usuario.id:
        return _erro(404, "pedido_nao_encontrado", "Pedido não encontrado.")
    try:
        item = contexto.exclusividades.em_andamento_do_pedido(pedido.id)
    except Exception:  # noqa: BLE001 - tabela ainda não existe: sem oferta
        item = None
    if item is None:
        return None
    detalhe = contexto.usuarios.detalhe(item.profissional_id)
    return OfertaExclusividadeOut(
        id=item.id,
        pedido_id=item.pedido_id,
        profissional_id=item.profissional_id,
        profissional_nome=nome_abreviado(detalhe.nome) if detalhe else None,
        nota_publica=detalhe.nota_publica if detalhe else None,
        status=item.status,
        responder_ate=item.responder_ate,
        expira_em=item.expira_em,
    )


_ERROS_RESPONDER = {
    "ja_respondida": (409, "ja_respondida", "Você já respondeu a esta oferta."),
    "prazo_vencido": (
        409,
        "prazo_vencido",
        "O prazo para responder acabou. A oferta expirou e seus outros orçamentos seguem valendo.",
    ),
    "pedido_indisponivel": (
        409,
        "pedido_indisponivel",
        "Este pedido não está mais aberto, então a oferta foi cancelada.",
    ),
}


@router.post(
    "/pedidos/{pedido_id}/exclusividade/{exclusividade_id}/responder",
    response_model=RespostaExclusividadeOut,
    summary="Aceitar ou recusar a exclusividade (cliente)",
    description=(
        "Sem compromisso. Aceitar reserva o pedido por 48h para esse profissional; recusar "
        "devolve os Tratinhos dele e todos os orçamentos seguem visíveis."
    ),
)
def responder_exclusividade(
    pedido_id: str,
    exclusividade_id: str,
    corpo: ResponderExclusividadeIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
):
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None or pedido.cliente_id != usuario.id:
        return _erro(404, "pedido_nao_encontrado", "Pedido não encontrado.")
    try:
        item = contexto.exclusividades.obter(exclusividade_id)
    except Exception:  # noqa: BLE001
        return _erro(503, "indisponivel", "A prioridade está indisponível no momento.")
    if item is None or item.pedido_id != pedido.id:
        return _erro(404, "exclusividade_nao_encontrada", "Oferta não encontrada.")
    cfg = contexto.moedas.config()
    try:
        r = contexto.exclusividades.responder(
            item.id, usuario.id, corpo.decisao, contexto.agora(), cfg.exclusividade_duracao_horas
        )
    except Exception:  # noqa: BLE001 - função ainda não existe ou banco fora
        return _erro(503, "indisponivel", "A prioridade está indisponível no momento.")
    if r.resultado == "nao_encontrada":
        return _erro(404, "exclusividade_nao_encontrada", "Oferta não encontrada.")
    if r.resultado in _ERROS_RESPONDER:
        return _erro(*_ERROS_RESPONDER[r.resultado])
    if r.resultado != "ok":
        return _erro(503, "indisponivel", "A prioridade está indisponível no momento.")
    avisar_exclusividade_resposta(request, contexto, exclusividade=item, decisao=corpo.decisao)
    atual = contexto.pedidos.obter(pedido.id)
    return RespostaExclusividadeOut(
        id=item.id,
        pedido_id=pedido.id,
        status="ativa" if corpo.decisao == "aceitar" else "recusada",
        expira_em=r.expira_em,
        pedido_estado=(atual.estado.value if atual is not None else pedido.estado.value),
    )
