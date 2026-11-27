"""Rotas do usuário para pedido de retorno de conta (Termos 20.9).

Quem pede o retorno está com a conta encerrada (status `bloqueado`): por isso as duas rotas usam
`usuario_do_suporte`, como medidas e atendimento.
"""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import Usuario
from trato.api.contexto import Contexto, obter_contexto, usuario_do_suporte
from trato.persistencia.retorno_conta import PedidoRetornoConta

router = APIRouter(prefix="/v1/me/conta", tags=["conta"])


class SolicitarRetornoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    justificativa: str = Field(min_length=10, max_length=4000)


class PedidoRetornoUsuarioOut(BaseModel):
    id: str
    protocolo: str
    medida_id: str
    justificativa_usuario: str
    canal: str
    status: str
    solicitado_em: datetime
    prazo_dias_aplicado: int
    elegivel_a_partir_de: datetime
    decisao_motivo: str | None = None
    decidido_em: datetime | None = None


class ListaRetornosUsuarioOut(BaseModel):
    itens: list[PedidoRetornoUsuarioOut]
    total: int


def _out(r: PedidoRetornoConta) -> PedidoRetornoUsuarioOut:
    return PedidoRetornoUsuarioOut(
        id=r.id,
        protocolo=r.protocolo,
        medida_id=r.medida_id,
        justificativa_usuario=r.justificativa_usuario,
        canal=r.canal,
        status=r.status,
        solicitado_em=r.solicitado_em,
        prazo_dias_aplicado=r.prazo_dias_aplicado,
        elegivel_a_partir_de=r.elegivel_a_partir_de,
        decisao_motivo=r.decisao_motivo,
        decidido_em=r.decidido_em,
    )


def _exigir_tabelas(contexto: Contexto) -> None:
    if not contexto.retorno_conta.disponivel():
        raise HTTPException(
            503,
            "Pedido de retorno indisponível: as tabelas ainda não existem no banco de dados.",
        )


@router.post(
    "/retorno",
    response_model=PedidoRetornoUsuarioOut,
    status_code=201,
    summary="Solicitar retorno da conta após encerramento sem infração grave (20.9)",
)
def solicitar_retorno_conta(
    corpo: SolicitarRetornoIn,
    resposta: Response,
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoRetornoUsuarioOut:
    _exigir_tabelas(contexto)
    ret, eh_novo, cod = contexto.retorno_conta.abrir_retorno(
        usuario.id, corpo.justificativa, "app", contexto.agora()
    )
    if cod == "infracao_grave":
        raise HTTPException(
            403, "Conta encerrada por infração grave não é elegível para pedido de retorno."
        )
    if cod == "sem_encerramento":
        raise HTTPException(409, "Não há encerramento de conta elegível para pedido de retorno.")
    if cod == "prazo_nao_cumprido":
        prazo = contexto.retorno_conta.prazo_dias_vigente()
        raise HTTPException(
            409, f"O prazo mínimo de {prazo} dias para solicitar o retorno ainda não foi cumprido."
        )
    if ret is None:
        raise HTTPException(409, "Não foi possível registrar o pedido de retorno.")
    if not eh_novo:
        resposta.status_code = 200
    return _out(ret)


@router.get(
    "/retorno",
    response_model=ListaRetornosUsuarioOut,
    summary="Consultar meus pedidos de retorno de conta",
)
def consultar_meus_retornos(
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
) -> ListaRetornosUsuarioOut:
    _exigir_tabelas(contexto)
    itens = contexto.retorno_conta.listar_retornos_do_usuario(usuario.id)
    return ListaRetornosUsuarioOut(itens=[_out(r) for r in itens], total=len(itens))
