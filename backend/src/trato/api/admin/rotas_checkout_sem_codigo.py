"""Fila e decisão do Check-out sem o Código Final (Termos 5.7). Permissão
`checkout_sem_codigo_tratar`: mediador, líder de suporte e administrador."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api import checkout_sem_codigo as regras
from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.checkout_sem_codigo import Caso

router = APIRouter(prefix="/v1/admin/checkout-sem-codigo", tags=["admin: check-out sem código"])


class CasoOut(BaseModel):
    id: str
    pedido_id: str
    cliente_id: str
    profissional_id: str | None
    check_out_em: datetime
    contatado_em: datetime | None
    canal: str | None = Field(description="Ex.: `app+email` (aviso) ou o canal do contato manual.")
    responder_ate: datetime | None = Field(
        description="Já com a prorrogação 22.3; null sem contato."
    )
    vencido: bool = Field(
        description="Passou de responder_ate sem resposta. Nada acontece sozinho."
    )


class ContatoManualIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    canal: Literal["telefone", "whatsapp", "email", "outro"]
    motivo: str = Field(min_length=10, max_length=500, description="Vai para a auditoria.")


class DecidirCasoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    decisao: Literal["liberar", "estornar"]
    motivo: str = Field(min_length=10, max_length=500, description="Justificativa obrigatória.")
    chave_idempotencia: str = Field(
        min_length=8, max_length=120, description="Chave única para evitar decisão duplicada."
    )


class DecisaoCasoOut(BaseModel):
    id: str
    pedido_id: str
    estado_pedido: str
    decisao: Literal["liberar", "estornar"]
    analista_id: str
    justificativa: str
    decidido_em: datetime
    chave_idempotencia: str
    idempotente: bool = Field(
        False, description="True quando a mesma chave repetiu uma decisão já gravada."
    )


def _saida(contexto: Contexto, caso: Caso) -> CasoOut:
    pedido = contexto.pedidos.obter(caso.pedido_id)
    ate = regras.responder_ate(contexto, caso)
    return CasoOut(
        id=caso.id,
        pedido_id=caso.pedido_id,
        cliente_id=pedido.cliente_id,
        profissional_id=pedido.profissional_id,
        check_out_em=caso.check_out_em,
        contatado_em=caso.contatado_em,
        canal=caso.canal,
        responder_ate=ate,
        vencido=ate is not None and contexto.agora() > ate,
    )


def _exigir_tabela(contexto: Contexto) -> None:
    if not contexto.checkout_sem_codigo.disponivel():
        raise HTTPException(503, "A fila do check-out sem código ainda não está disponível.")


def _exigir_fase2(contexto: Contexto) -> None:
    _exigir_tabela(contexto)
    if not contexto.checkout_sem_codigo.fase2_disponivel():
        raise HTTPException(
            503, "A decisão de check-out sem código ainda não está disponível no banco."
        )


@router.get("", response_model=Pagina[CasoOut], summary="Casos abertos (vencidos primeiro)")
def fila(
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.CHECKOUT_SEM_CODIGO_TRATAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[CasoOut]:
    _exigir_tabela(contexto)
    repo = contexto.checkout_sem_codigo
    # Só o que o pedido ainda tem como vigente: cancelado, em disputa ou concluído sai.
    atuais = [c for c in repo.em_aberto() if repo.vigente(c.pedido_id) == c.check_out_em]
    itens = [_saida(contexto, c) for c in atuais]
    # Vencidos, depois os sem contato (alguém precisa agir), depois pelo prazo.
    itens.sort(
        key=lambda i: (
            0 if i.vencido else 1 if i.contatado_em is None else 2,
            (i.responder_ate or i.check_out_em).timestamp(),
        )
    )
    return Pagina(
        itens=itens[deslocamento : deslocamento + limite],
        total=len(itens),
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/{caso_id}/contato",
    response_model=CasoOut,
    summary="Registrar o contato feito à mão (vale o primeiro; começa o prazo)",
)
def registrar_contato_manual(
    caso_id: str,
    corpo: ContatoManualIn,
    operador: Operador = Depends(exigir(Permissao.CHECKOUT_SEM_CODIGO_TRATAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CasoOut:
    _exigir_tabela(contexto)
    repo = contexto.checkout_sem_codigo
    with contexto.transacao():
        caso = repo.obter(caso_id)
        if caso is None:
            raise HTTPException(404, "Caso não encontrado.")
        if (
            caso.respondido_em
            or caso.decidido_em
            or repo.vigente(caso.pedido_id) != caso.check_out_em
        ):
            raise HTTPException(409, "Este caso não está mais aberto.")
        gravado = regras.registrar_contato(contexto, caso, corpo.canal)
        if gravado is None:
            raise HTTPException(409, "O contato deste caso já foi registrado.")
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="checkout_sem_codigo.contato_manual",
            entidade="pedidos",
            entidade_id=caso.pedido_id,
            antes={},
            depois={
                "caso_id": caso.id,
                "canal": corpo.canal,
                "responder_ate": gravado.responder_ate.isoformat(),
            },
            motivo=corpo.motivo,
        )
    return _saida(contexto, gravado)


@router.post(
    "/{caso_id}/decisao",
    response_model=DecisaoCasoOut,
    summary="Decidir check-out sem código (liberar ao profissional ou estornar ao cliente)",
)
def decidir_caso(
    caso_id: str,
    corpo: DecidirCasoIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.CHECKOUT_SEM_CODIGO_TRATAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> DecisaoCasoOut:
    _exigir_fase2(contexto)
    servico = getattr(request.app.state, "servico_pagamento", None)
    decidido, pedido, idempotente = regras.efetivar_decisao(
        contexto,
        admin,
        servico,
        operador,
        caso_id,
        corpo.decisao,
        corpo.motivo,
        corpo.chave_idempotencia,
    )
    return DecisaoCasoOut(
        id=decidido.id,
        pedido_id=decidido.pedido_id,
        estado_pedido=pedido.estado.value,
        decisao=decidido.decisao,  # type: ignore[arg-type]
        analista_id=decidido.analista_id or "",
        justificativa=decidido.justificativa or "",
        decidido_em=decidido.decidido_em,  # type: ignore[arg-type]
        chave_idempotencia=decidido.chave_idempotencia or corpo.chave_idempotencia,
        idempotente=idempotente,
    )
