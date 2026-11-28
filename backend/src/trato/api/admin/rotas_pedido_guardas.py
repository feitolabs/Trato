"""Guarda de Pedido e situação da retenção no painel (Termos 14.8 e 16.3).

Permissão `pedido_guardas_gerenciar`: DPO, jurídico, segurança e administrador (os mesmos papéis
que o banco aceita). Abrir e encerrar são auditados. Nada aqui apaga nem anonimiza.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.erros import RegraDoBanco
from trato.persistencia.pedido_guardas import GuardaPedido

router = APIRouter(prefix="/v1/admin/pedidos", tags=["admin: guarda de pedido"])
_PERMISSAO = Permissao.PEDIDO_GUARDAS_GERENCIAR


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(min_length=10, max_length=1000)


class AbrirGuardaIn(_Entrada):
    tipo: Literal["processo", "investigacao"]


class EncerrarGuardaIn(_Entrada):
    pass


class GuardaPedidoOut(BaseModel):
    id: str
    pedido_id: str
    tipo: Literal["processo", "investigacao"]
    motivo: str
    aberta: bool
    criada_por: str
    criada_em: datetime
    encerrada_em: datetime | None = None
    encerrada_por: str | None = None


class RetencaoPedidoOut(BaseModel):
    pedido_id: str
    situacao: Literal["sem_marco", "no_prazo", "bloqueado", "vencido"]
    concluido_em: datetime | None = None
    prazo_anos: int
    guarda_ate: datetime | None = None
    bloqueios: list[str] = Field(
        description="disputa_aberta, contestacao_disputa_aberta, contestacao_nota_aberta, "
        "pagamento_contestado, incidente_nao_encerrado, preservacao_9_6, guarda_pedido, "
        "guarda_usuario. Podem vir mesmo com `no_prazo` ou `sem_marco`."
    )


def _saida(g: GuardaPedido) -> GuardaPedidoOut:
    return GuardaPedidoOut(**vars(g), aberta=g.encerrada_em is None)


def _exigir_pedido(contexto: Contexto, pedido_id: str) -> None:
    if not contexto.pedido_guardas.disponivel():
        raise HTTPException(503, "A guarda de Pedido ainda não está disponível no banco.")
    if contexto.pedidos.obter(pedido_id) is None:
        raise HTTPException(404, "Pedido não encontrado.")


def _auditar(
    admin: AdminContexto, operador: Operador, acao: str, g: GuardaPedido, motivo: str
) -> None:
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=f"retencao.guarda_pedido_{acao}",
        entidade="pedido_guardas",
        entidade_id=g.id,
        antes={},
        depois={"pedido_id": g.pedido_id, "tipo": g.tipo, "aberta": g.encerrada_em is None},
        motivo=motivo,
    )


def _recusa_do_banco() -> HTTPException:
    return HTTPException(403, "O banco só aceita DPO, jurídico, segurança ou administrador ativo.")


@router.get(
    "/{pedido_id}/guardas",
    response_model=list[GuardaPedidoOut],
    summary="Guardas do pedido (abertas e encerradas)",
)
def listar_guardas(
    pedido_id: str,
    _: Operador = Depends(exigir(_PERMISSAO)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[GuardaPedidoOut]:
    _exigir_pedido(contexto, pedido_id)
    return [_saida(g) for g in contexto.pedido_guardas.listar(pedido_id)]


@router.post(
    "/{pedido_id}/guardas",
    response_model=GuardaPedidoOut,
    status_code=201,
    summary="Abrir guarda de Pedido",
    description="Repetir com o mesmo tipo e motivo enquanto aberta devolve 200 com a mesma.",
)
def abrir_guarda(
    pedido_id: str,
    corpo: AbrirGuardaIn,
    response: Response,
    operador: Operador = Depends(exigir(_PERMISSAO)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> GuardaPedidoOut:
    _exigir_pedido(contexto, pedido_id)
    try:
        with contexto.transacao():
            guarda, nova = contexto.pedido_guardas.abrir(
                pedido_id, corpo.tipo, corpo.motivo, operador.id
            )
            if nova:
                _auditar(admin, operador, "aberta", guarda, corpo.motivo)
    except RegraDoBanco:
        raise _recusa_do_banco() from None
    if not nova:
        response.status_code = 200
    return _saida(guarda)


@router.post(
    "/{pedido_id}/guardas/{guarda_id}/encerrar",
    response_model=GuardaPedidoOut,
    summary="Encerrar guarda de Pedido",
    description="Repetir devolve 200 com a guarda já encerrada, sem nova auditoria.",
)
def encerrar_guarda(
    pedido_id: str,
    guarda_id: str,
    corpo: EncerrarGuardaIn,
    operador: Operador = Depends(exigir(_PERMISSAO)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> GuardaPedidoOut:
    _exigir_pedido(contexto, pedido_id)
    try:
        with contexto.transacao():
            guarda, encerrou = contexto.pedido_guardas.encerrar(pedido_id, guarda_id, operador.id)
            if guarda is None:
                raise HTTPException(404, "Guarda não encontrada neste pedido.")
            if encerrou:
                _auditar(admin, operador, "encerrada", guarda, corpo.motivo)
    except RegraDoBanco:
        raise _recusa_do_banco() from None
    return _saida(guarda)


@router.get(
    "/{pedido_id}/retencao",
    response_model=RetencaoPedidoOut,
    summary="Situação da retenção dos registros do pedido (só leitura)",
)
def situacao_da_retencao(
    pedido_id: str,
    _: Operador = Depends(exigir(_PERMISSAO)),
    contexto: Contexto = Depends(obter_contexto),
) -> RetencaoPedidoOut:
    _exigir_pedido(contexto, pedido_id)
    s = contexto.pedido_guardas.situacao(pedido_id)
    if s is None:
        raise HTTPException(404, "Pedido não encontrado.")
    return RetencaoPedidoOut(**(vars(s) | {"bloqueios": list(s.bloqueios)}))
