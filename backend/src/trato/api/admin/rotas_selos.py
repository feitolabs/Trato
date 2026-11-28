"""Selo do profissional no painel (Termos 10.3). Retirar e pedir reconferência: `selo_retirar`
(cadastro, segurança e administrador). Regularizar: `selo_regularizar` (cadastro e
administrador). O motivo é imutável, vai ao profissional e não pode ter dado pessoal."""

from __future__ import annotations

import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import (
    AdminContexto,
    Operador,
    exigir,
    obter_admin,
    proteger_conta_da_equipe,
)
from trato.api.admin.papeis import Permissao
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, obter_contexto
from trato.notificacoes.eventos import Evento
from trato.persistencia.selos import ChaveDeOutroEvento
from trato.seguranca.mascaramento import mascarar

router = APIRouter(prefix="/v1/admin/profissionais", tags=["admin: selo do profissional"])
COMO_CONTESTAR = "Para contestar, fale com o atendimento pelo aplicativo ou pelo SAC."
_CPF = re.compile(r"\d{3}\.?\d{3}\.?\d{3}-?\d{2}")
_ERROS = {
    "sem_selo": (409, "Este profissional não tem selo para retirar."),
    "sem_retirada_aberta": (409, "Não há retirada de selo para regularizar."),
    "operador_invalido": (403, "Seu papel na equipe não permite isso."),
    "profissional_nao_encontrado": (404, "Profissional não encontrado."),
}
_ACOES = {
    "retirar": (
        "profissional.selo_retirado",
        Evento.SELO_RETIRADO,
        "O seu selo de verificação foi retirado até a regularização. Até lá você não envia "
        "orçamentos novos.",
    ),
    "reconferencia": (
        "profissional.selo_reconferencia_pedida",
        Evento.SELO_RECONFERENCIA,
        "O Trato pediu uma nova conferência da sua identidade.",
    ),
    "regularizar": (
        "profissional.selo_regularizado",
        Evento.SELO_REGULARIZADO,
        "O seu selo de verificação foi regularizado.",
    ),
}


class SeloIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(
        min_length=10,
        max_length=1000,
        description="O profissional lê e não dá para apagar: sem CPF, contato ou dado sensível.",
    )
    chave_idempotencia: str = Field(min_length=8, max_length=100)


class SeloOut(BaseModel):
    resultado: str = Field(description="ok | ja_existe")
    evento_id: str
    nivel_verificacao: str
    retirada_aberta: bool


def _executar(
    operacao: str,
    usuario_id: str,
    corpo: SeloIn,
    operador: Operador,
    admin: AdminContexto,
    contexto: Contexto,
) -> SeloOut:
    if not contexto.selos.disponivel():
        raise HTTPException(503, "O histórico do selo ainda não está disponível no banco.")
    if _CPF.search(corpo.motivo) or mascarar(corpo.motivo).exibido != corpo.motivo:
        raise HTTPException(422, "Tire CPF, telefone, e-mail ou link do motivo.")
    proteger_conta_da_equipe(admin, operador, usuario_id)
    acao, evento, texto = _ACOES[operacao]
    try:
        with contexto.transacao():
            r = contexto.selos.aplicar(
                operacao,
                usuario_id,
                operador.id,
                corpo.motivo,
                corpo.chave_idempotencia,
                contexto.agora(),
            )
            if r.resultado == "ok":
                admin.auditoria.registrar(
                    ator_id=operador.id,
                    acao=acao,
                    entidade="perfis_profissional",
                    entidade_id=usuario_id,
                    antes={},
                    depois={"evento_id": r.evento_id, "nivel": r.nivel},
                    motivo=corpo.motivo,
                )
                avisar_partes(
                    contexto,
                    evento,
                    (usuario_id,),
                    pedido_id=None,
                    chave=f"selo:{r.evento_id}",
                    corpo=f"{texto} Motivo: {corpo.motivo} {COMO_CONTESTAR}",
                )
    except ChaveDeOutroEvento:
        raise HTTPException(422, "Chave de idempotência já usada em outra operação.") from None
    if r.resultado in _ERROS:
        raise HTTPException(*_ERROS[r.resultado])
    return SeloOut(
        resultado=r.resultado,
        evento_id=r.evento_id or "",
        nivel_verificacao=r.nivel or "",
        retirada_aberta=contexto.selos.retirada_aberta(usuario_id),
    )


@router.post("/{usuario_id}/selo/retirar", response_model=SeloOut, summary="Retirar o selo")
def retirar(
    usuario_id: str,
    corpo: SeloIn,
    operador: Operador = Depends(exigir(Permissao.SELO_RETIRAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> SeloOut:
    return _executar("retirar", usuario_id, corpo, operador, admin, contexto)


@router.post(
    "/{usuario_id}/selo/reconferencia",
    response_model=SeloOut,
    summary="Pedir nova conferência (não muda o nível)",
)
def pedir_reconferencia(
    usuario_id: str,
    corpo: SeloIn,
    operador: Operador = Depends(exigir(Permissao.SELO_RETIRAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> SeloOut:
    return _executar("reconferencia", usuario_id, corpo, operador, admin, contexto)


@router.post(
    "/{usuario_id}/selo/regularizar",
    response_model=SeloOut,
    summary="Regularizar: devolve o nível de antes da retirada",
)
def regularizar(
    usuario_id: str,
    corpo: SeloIn,
    operador: Operador = Depends(exigir(Permissao.SELO_REGULARIZAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> SeloOut:
    return _executar("regularizar", usuario_id, corpo, operador, admin, contexto)
