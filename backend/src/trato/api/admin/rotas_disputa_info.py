"""Rotas admin de pedido de informação adicional em disputas (Termos 8.4)."""

from __future__ import annotations

from functools import partial
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from trato.api import disputa_pedidos_info as regras
from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.api.disputa_pedidos_info import PedidoInfoOut

router = APIRouter(prefix="/v1/admin/disputas", tags=["admin: disputas"])


class SolicitarInfoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    destinatario_papel: Literal["cliente", "profissional"]
    mensagem: str = Field(min_length=10, max_length=1000)


class EncerrarSemRespostaIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(min_length=10, max_length=500, description="Vai para a auditoria.")


@router.get(
    "/{disputa_id}/pedidos-informacao",
    response_model=list[PedidoInfoOut],
    summary="Listar pedidos de informação adicional da disputa",
)
def listar_pedidos_info(
    disputa_id: str,
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[PedidoInfoOut]:
    regras.exigir_tabela(contexto)
    did, _, pedido = regras.resolver_disputa_e_pedido(contexto, disputa_id)
    itens = contexto.disputa_pedidos_info.listar_da_disputa(did)
    return [regras.saida(contexto, x, pedido.id) for x in itens]


@router.post(
    "/{disputa_id}/pedidos-informacao",
    response_model=PedidoInfoOut,
    status_code=201,
    summary="Solicitar informação adicional a uma parte da disputa (prazo mínimo 10 dias úteis)",
)
def solicitar_info(
    disputa_id: str,
    corpo: SolicitarInfoIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoInfoOut:
    regras.exigir_tabela(contexto)
    with contexto.transacao():
        did, disputa, pedido = regras.resolver_disputa_e_pedido(contexto, disputa_id)
        if disputa.encerrada:
            raise HTTPException(409, "A disputa já está encerrada e não aceita novos pedidos.")
        destinatario_id = (
            pedido.cliente_id if corpo.destinatario_papel == "cliente" else pedido.profissional_id
        )
        if not destinatario_id:
            raise HTTPException(409, "O pedido não tem profissional vinculado para notificar.")
        agora = contexto.agora()
        ate = regras.prazo_original(contexto, agora)
        criado = contexto.disputa_pedidos_info.criar(
            did, operador.id, corpo.destinatario_papel, corpo.mensagem, agora, ate
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="disputa.pedido_informacao_solicitado",
            entidade="pedidos",
            entidade_id=pedido.id,
            antes={},
            depois={
                "pedido_info_id": criado.id,
                "disputa_id": did,
                "destinatario_papel": corpo.destinatario_papel,
                "responder_ate": ate.isoformat(),
            },
            motivo=corpo.mensagem[:500],
        )
        contexto.depois_do_commit(
            partial(regras.notificar_solicitacao, contexto, destinatario_id, pedido.id, criado)
        )
    return regras.saida(contexto, criado, pedido.id)


@router.post(
    "/{disputa_id}/pedidos-informacao/{pedido_info_id}/encerrar-sem-resposta",
    response_model=PedidoInfoOut,
    summary="Encerrar pedido de informação vencido sem resposta",
)
def encerrar_sem_resposta(
    disputa_id: str,
    pedido_info_id: str,
    corpo: EncerrarSemRespostaIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoInfoOut:
    regras.exigir_tabela(contexto)
    with contexto.transacao():
        did, _, pedido = regras.resolver_disputa_e_pedido(contexto, disputa_id)
        item = contexto.disputa_pedidos_info.obter(pedido_info_id)
        if item is None or item.disputa_id != did:
            raise HTTPException(404, "Pedido de informação não encontrado.")
        if item.respondido_em is not None:
            raise HTTPException(409, "Este pedido de informação já foi respondido.")
        if item.encerrado_sem_resposta_em is not None:
            raise HTTPException(409, "Este pedido de informação já foi encerrado sem resposta.")
        agora = contexto.agora()
        ate = regras.responder_ate_vigente(contexto, item)
        if agora <= ate:
            raise HTTPException(409, "O prazo para resposta ainda não venceu.")
        gravado = contexto.disputa_pedidos_info.encerrar_sem_resposta(item.id, agora)
        if gravado is None:
            raise HTTPException(409, "Este pedido de informação não pode mais ser encerrado.")
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="disputa.pedido_informacao_encerrado_sem_resposta",
            entidade="pedidos",
            entidade_id=pedido.id,
            antes={"status": "vencido"},
            depois={
                "pedido_info_id": gravado.id,
                "disputa_id": did,
                "encerrado_sem_resposta_em": agora.isoformat(),
            },
            motivo=corpo.motivo,
        )
    return regras.saida(contexto, gravado, pedido.id)
