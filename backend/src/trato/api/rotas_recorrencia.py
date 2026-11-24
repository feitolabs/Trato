"""Serviço recorrente: propor, aceitar, pausar, retomar, cancelar, pular visita e reajustar.

Só as duas partes da série veem e mexem nela (terceiro recebe 404) e o outro lado aparece só
pelo nome curto. Nenhuma rota cobra: a visita vira um pedido (rotina do agendador) que o cliente
aprova e paga sozinho. Valores em centavos inteiros.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.recorrencias import (
    ST_ATIVA,
    ST_CANCELADA,
    ST_PAUSADA,
    ST_PROPOSTA,
    V_AGENDADA,
    V_CANCELADA,
    V_PULADA,
    JaExisteRecorrencia,
    Recorrencia,
    Visita,
    cancelar_pedido_da_visita,
    proxima_data_futura,
    somar_frequencia,
)
from trato.api.servicos import carregar_pedido
from trato.notificacoes.eventos import Evento
from trato.pedidos.estados import Estado

log = logging.getLogger(__name__)
router = APIRouter(prefix="/v1/recorrencias", tags=["recorrencias"])

_JA_RESPONDIDO = "Este serviço recorrente já foi respondido."
_PAPEIS = (PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)


class ProporRecorrenciaIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    pedido_origem_id: str = Field(min_length=1, max_length=64)
    frequencia: Literal["semanal", "quinzenal", "mensal"]
    proxima_visita_em: datetime
    valor_centavos: int | None = Field(
        default=None, gt=0, description="Centavos. Sem valor, vale o do serviço concluído."
    )


class ReajusteIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    valor_centavos: int = Field(gt=0, description="Novo valor por visita, em centavos.")


class AceitarReajusteIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    valor_centavos: int = Field(
        gt=0, description="O valor que o cliente viu (o proposto). Mudou? Responde 409."
    )


class VisitaOut(BaseModel):
    id: str
    data_prevista_em: datetime
    status: str = Field(description="agendada, confirmada_paga, pulada, expirada ou cancelada.")
    pedido_id: str | None = Field(
        default=None, description="Pedido da visita: o cliente aceita o orçamento e paga nele."
    )


class RecorrenciaOut(BaseModel):
    id: str
    status: str = Field(description="proposta, ativa, pausada ou cancelada.")
    frequencia: str
    valor_centavos: int
    valor_proposto_centavos: int | None = Field(
        default=None, description="Reajuste esperando o aceite do cliente (nunca é cobrado antes)."
    )
    proxima_visita_em: datetime
    meu_papel: str = Field(description="cliente ou profissional.")
    proposto_por_mim: bool
    outra_parte_nome: str | None = Field(description="Primeiro nome e inicial do sobrenome.")
    pedido_origem_id: str
    categoria_id: str | None = None
    criado_em: datetime


class RecorrenciaDetalheOut(RecorrenciaOut):
    visitas: list[VisitaOut]


def _nome_curto(contexto: Contexto, usuario_id: str) -> str | None:
    from trato.api.rotas_profissional_cadastro import _nome_abreviado

    detalhe = contexto.usuarios.detalhe(usuario_id)
    return _nome_abreviado(detalhe.nome) if detalhe is not None else None


def _out(contexto: Contexto, r: Recorrencia, usuario_id: str) -> RecorrenciaOut:
    sou_cliente = usuario_id == r.cliente_id
    outra = r.profissional_id if sou_cliente else r.cliente_id
    return RecorrenciaOut(
        id=r.id,
        status=r.status,
        frequencia=r.frequencia,
        valor_centavos=r.valor_centavos,
        valor_proposto_centavos=r.valor_proposto_centavos,
        proxima_visita_em=r.proxima_visita_em,
        meu_papel="cliente" if sou_cliente else "profissional",
        proposto_por_mim=r.proposto_por == usuario_id,
        outra_parte_nome=_nome_curto(contexto, outra),
        pedido_origem_id=r.pedido_origem_id,
        categoria_id=r.categoria_id,
        criado_em=r.criado_em,
    )


def _detalhe(contexto: Contexto, r: Recorrencia, usuario_id: str) -> RecorrenciaDetalheOut:
    visitas = [
        VisitaOut(
            id=v.id, data_prevista_em=v.data_prevista_em, status=v.status, pedido_id=v.pedido_id
        )
        for v in contexto.recorrencias.visitas(r.id)
    ]
    return RecorrenciaDetalheOut(**_out(contexto, r, usuario_id).model_dump(), visitas=visitas)


def _da_serie(contexto: Contexto, recorrencia_id: str, usuario: Usuario) -> Recorrencia:
    """A série, só para quem faz parte dela (terceiro e id inexistente: 404)."""
    r = contexto.recorrencias.obter(recorrencia_id)
    if r is None or usuario.id not in (r.cliente_id, r.profissional_id):
        raise HTTPException(404, "Serviço recorrente não encontrado.")
    return r


def _outra_parte(r: Recorrencia, usuario_id: str) -> str:
    return r.profissional_id if usuario_id == r.cliente_id else r.cliente_id


def _avisar(
    request: Request, contexto: Contexto, r: Recorrencia, destino: str, texto: str, chave: str
) -> None:
    """Aviso é secundário: sem notificador ou com falha, a rota segue."""
    try:
        from trato.api.avisos import servicos_de_notificacao

        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.RECORRENCIA_ATUALIZADA,
            destino,
            chave=f"recorrencia:{r.id}:{chave}",
            corpo=texto,
            dados={"recorrencia_id": r.id},
        )
    except Exception:  # noqa: BLE001
        log.warning("aviso de recorrência não enviado", exc_info=True)


def _cancelar_visitas_abertas(contexto: Contexto, r: Recorrencia, novo_status: str, por: str):
    """Visitas ainda 'agendada' saem da agenda; o pedido aberto de cada uma é cancelado."""
    for v in contexto.recorrencias.visitas(r.id):
        if v.status != V_AGENDADA:
            continue
        if contexto.recorrencias.mudar_visita(v.id, (V_AGENDADA,), novo_status, por):
            pedido = contexto.pedidos.obter(v.pedido_id) if v.pedido_id else None
            if pedido is not None:
                cancelar_pedido_da_visita(contexto, r, pedido)


@router.post(
    "",
    response_model=RecorrenciaOut,
    status_code=201,
    summary="Propor um serviço recorrente a partir de um serviço concluído",
)
def propor(
    corpo: ProporRecorrenciaIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaOut:
    pedido = carregar_pedido(contexto, corpo.pedido_origem_id, usuario)  # terceiro: 404
    if pedido.estado is not Estado.CONCLUIDO or not pedido.profissional_id:
        raise HTTPException(
            409, "O serviço recorrente só pode ser combinado depois que o serviço for concluído."
        )
    repo = contexto.recorrencias
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    valor = corpo.valor_centavos or (contrato.valor_centavos if contrato else 0)
    if valor <= 0:
        raise HTTPException(422, "Informe o valor de cada visita.")
    if valor > repo.config().valor_maximo_centavos:
        raise HTTPException(422, "O valor de cada visita passa do limite permitido.")
    agora = contexto.agora()
    if corpo.proxima_visita_em <= agora:
        raise HTTPException(422, "A data da primeira visita precisa ser no futuro.")
    nova = Recorrencia(
        id=str(uuid.uuid4()),
        cliente_id=pedido.cliente_id,
        profissional_id=pedido.profissional_id,
        pedido_origem_id=pedido.id,
        categoria_id=contrato.categoria_id if contrato else None,
        frequencia=corpo.frequencia,
        valor_centavos=valor,
        proxima_visita_em=corpo.proxima_visita_em,
        status=ST_PROPOSTA,
        proposto_por=usuario.id,
        criado_em=agora,
    )
    try:
        gravada = repo.criar(nova)
    except JaExisteRecorrencia:
        raise HTTPException(409, "Já existe um serviço recorrente para este pedido.") from None
    _avisar(
        request,
        contexto,
        gravada,
        _outra_parte(gravada, usuario.id),
        "A outra parte propôs um serviço recorrente. Veja e responda no app.",
        "proposta",
    )
    return _out(contexto, gravada, usuario.id)


@router.get(
    "",
    response_model=list[RecorrenciaOut],
    summary="Meus serviços recorrentes (como cliente ou como profissional)",
)
def listar(
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[RecorrenciaOut]:
    return [_out(contexto, r, usuario.id) for r in contexto.recorrencias.do_usuario(usuario.id)]


@router.get(
    "/{recorrencia_id}",
    response_model=RecorrenciaDetalheOut,
    summary="Um serviço recorrente com as visitas",
)
def detalhe(
    recorrencia_id: str,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    return _detalhe(contexto, _da_serie(contexto, recorrencia_id, usuario), usuario.id)


def _devolver(contexto: Contexto, recorrencia_id: str, usuario: Usuario) -> RecorrenciaDetalheOut:
    atual = contexto.recorrencias.obter(recorrencia_id)
    return _detalhe(contexto, atual, usuario.id)  # type: ignore[arg-type]


@router.post(
    "/{recorrencia_id}/aceitar",
    response_model=RecorrenciaDetalheOut,
    summary="Aceitar a proposta (só a outra parte): a série fica ativa",
)
def aceitar(
    recorrencia_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    if r.proposto_por == usuario.id:
        raise HTTPException(403, "Apenas a outra parte pode aceitar o serviço recorrente.")
    agora = contexto.agora()
    primeira = proxima_data_futura(r.proxima_visita_em, r.frequencia, agora)
    if not contexto.recorrencias.mudar_status(
        r.id, (ST_PROPOSTA,), ST_ATIVA, agora, proxima_visita_em=primeira
    ):
        raise HTTPException(409, _JA_RESPONDIDO)
    _avisar(request, contexto, r, r.proposto_por, "O serviço recorrente foi aceito.", "aceita")
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/recusar",
    response_model=RecorrenciaDetalheOut,
    summary="Recusar a proposta (só a outra parte)",
)
def recusar(
    recorrencia_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    if r.proposto_por == usuario.id:
        raise HTTPException(403, "Quem propôs cancela a proposta em vez de recusar.")
    if not contexto.recorrencias.mudar_status(
        r.id, (ST_PROPOSTA,), ST_CANCELADA, contexto.agora(), por=usuario.id
    ):
        raise HTTPException(409, _JA_RESPONDIDO)
    _avisar(request, contexto, r, r.proposto_por, "O serviço recorrente foi recusado.", "recusada")
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/pausar",
    response_model=RecorrenciaDetalheOut,
    summary="Pausar a série (não gera novas visitas); qualquer parte, sem multa",
)
def pausar(
    recorrencia_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    if not contexto.recorrencias.mudar_status(r.id, (ST_ATIVA,), ST_PAUSADA, contexto.agora()):
        raise HTTPException(409, "Só dá para pausar um serviço recorrente ativo.")
    _avisar(
        request,
        contexto,
        r,
        _outra_parte(r, usuario.id),
        "O serviço recorrente foi pausado.",
        "pausada",
    )
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/retomar",
    response_model=RecorrenciaDetalheOut,
    summary="Retomar uma série pausada na próxima data que ainda não passou",
)
def retomar(
    recorrencia_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    agora = contexto.agora()
    proxima = proxima_data_futura(r.proxima_visita_em, r.frequencia, agora)
    if not contexto.recorrencias.mudar_status(
        r.id, (ST_PAUSADA,), ST_ATIVA, agora, proxima_visita_em=proxima
    ):
        raise HTTPException(409, "Só dá para retomar um serviço recorrente pausado.")
    _avisar(
        request,
        contexto,
        r,
        _outra_parte(r, usuario.id),
        "O serviço recorrente foi retomado.",
        "retomada",
    )
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/cancelar",
    response_model=RecorrenciaDetalheOut,
    summary="Cancelar a série (qualquer parte, sem multa): as visitas em aberto saem da agenda",
)
def cancelar(
    recorrencia_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    if not contexto.recorrencias.mudar_status(
        r.id, (ST_PROPOSTA, ST_ATIVA, ST_PAUSADA), ST_CANCELADA, contexto.agora(), por=usuario.id
    ):
        raise HTTPException(409, "Este serviço recorrente já foi cancelado.")
    _cancelar_visitas_abertas(contexto, r, V_CANCELADA, usuario.id)
    _avisar(
        request,
        contexto,
        r,
        _outra_parte(r, usuario.id),
        "O serviço recorrente foi cancelado.",
        "cancelada",
    )
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/visitas/{visita_id}/pular",
    response_model=RecorrenciaDetalheOut,
    summary="Pular uma visita já gerada (qualquer parte, sem multa); a série continua",
)
def pular_visita(
    recorrencia_id: str,
    visita_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    visita = contexto.recorrencias.obter_visita(visita_id)
    if visita is None or visita.recorrencia_id != r.id:
        raise HTTPException(404, "Visita não encontrada.")
    if r.status not in (ST_ATIVA, ST_PAUSADA) or not contexto.recorrencias.mudar_visita(
        visita.id, (V_AGENDADA,), V_PULADA, usuario.id
    ):
        raise HTTPException(409, "Esta visita não pode mais ser pulada.")
    pedido = contexto.pedidos.obter(visita.pedido_id) if visita.pedido_id else None
    if pedido is not None:
        cancelar_pedido_da_visita(contexto, r, pedido)
    _avisar(
        request,
        contexto,
        r,
        _outra_parte(r, usuario.id),
        "Uma visita do serviço recorrente foi pulada.",
        f"pulada:{visita.id}",
    )
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/pular-proxima",
    response_model=RecorrenciaDetalheOut,
    summary="Pular a próxima visita antes de ela ser gerada (feriado, viagem)",
)
def pular_proxima(
    recorrencia_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    repo = contexto.recorrencias
    if r.status != ST_ATIVA:
        raise HTTPException(409, "Só dá para pular visitas de um serviço recorrente ativo.")
    agora = contexto.agora()
    with contexto.transacao():
        visita: Visita | None = repo.reservar_visita(r.id, r.proxima_visita_em, agora, V_PULADA)
        if visita is None:
            raise HTTPException(
                409, "A próxima visita já foi gerada: pule-a pela lista de visitas da série."
            )
        repo.mudar_visita(visita.id, (V_PULADA,), V_PULADA, usuario.id)
        repo.avancar(r.id, r.proxima_visita_em, somar_frequencia(r.proxima_visita_em, r.frequencia))
    _avisar(
        request,
        contexto,
        r,
        _outra_parte(r, usuario.id),
        "Uma visita do serviço recorrente foi pulada.",
        f"pulada:{visita.id}",
    )
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/reajuste",
    response_model=RecorrenciaDetalheOut,
    summary="Profissional propõe um novo valor por visita (só vale com o aceite do cliente)",
)
def propor_reajuste(
    recorrencia_id: str,
    corpo: ReajusteIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    if usuario.id != r.profissional_id:
        raise HTTPException(403, "Só o profissional propõe um novo valor.")
    if corpo.valor_centavos == r.valor_centavos:
        raise HTTPException(422, "O novo valor precisa ser diferente do valor atual.")
    if corpo.valor_centavos > contexto.recorrencias.config().valor_maximo_centavos:
        raise HTTPException(422, "O valor de cada visita passa do limite permitido.")
    if r.valor_proposto_centavos is not None:
        raise HTTPException(
            409, "Já existe um reajuste esperando resposta do cliente. Aguarde a resposta."
        )
    if not contexto.recorrencias.propor_reajuste(r.id, corpo.valor_centavos):
        atual = contexto.recorrencias.obter(r.id)
        if atual is not None and atual.valor_proposto_centavos is not None:
            raise HTTPException(
                409, "Já existe um reajuste esperando resposta do cliente. Aguarde a resposta."
            )
        raise HTTPException(409, "Só dá para reajustar um serviço recorrente ativo ou pausado.")
    _avisar(
        request,
        contexto,
        r,
        r.cliente_id,
        "O profissional propôs um novo valor para as próximas visitas. Aceite ou cancele no app.",
        f"reajuste:{corpo.valor_centavos}",
    )
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/reajuste/aceitar",
    response_model=RecorrenciaDetalheOut,
    summary="Cliente aceita o novo valor: vale a partir das próximas visitas",
)
def aceitar_reajuste(
    recorrencia_id: str,
    corpo: AceitarReajusteIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    if usuario.id != r.cliente_id:
        raise HTTPException(403, "Só o cliente aceita um novo valor.")
    if not contexto.recorrencias.aceitar_reajuste(r.id, corpo.valor_centavos):
        atual = contexto.recorrencias.obter(r.id)
        if (
            atual is not None
            and atual.valor_proposto_centavos is not None
            and atual.status in (ST_ATIVA, ST_PAUSADA)
        ):
            raise HTTPException(409, "O valor do reajuste mudou. Confira o novo valor.")
        raise HTTPException(409, "Não há reajuste esperando resposta.")
    _avisar(
        request, contexto, r, r.profissional_id, "O cliente aceitou o novo valor.", "reajuste_ok"
    )
    return _devolver(contexto, r.id, usuario)


@router.post(
    "/{recorrencia_id}/reajuste/recusar",
    response_model=RecorrenciaDetalheOut,
    summary="Cliente recusa o novo valor: a série segue no valor atual",
)
def recusar_reajuste(
    recorrencia_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(*_PAPEIS)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecorrenciaDetalheOut:
    r = _da_serie(contexto, recorrencia_id, usuario)
    if usuario.id != r.cliente_id:
        raise HTTPException(403, "Só o cliente responde a um novo valor.")
    if not contexto.recorrencias.recusar_reajuste(r.id):
        raise HTTPException(409, "Não há reajuste esperando resposta.")
    _avisar(
        request, contexto, r, r.profissional_id, "O cliente recusou o novo valor.", "reajuste_nao"
    )
    return _devolver(contexto, r.id, usuario)
