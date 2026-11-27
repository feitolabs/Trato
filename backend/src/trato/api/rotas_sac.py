"""Atendimento ao usuário (Termos 25.3 a 25.5 e 20.5): abrir e acompanhar chamados.

Protocolo na hora e confirmação por app e e-mail. Conta suspensa ou bloqueada continua
entrando AQUI. Os prazos vêm da configuração e nunca passam dos do termo.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import Usuario
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, obter_contexto, usuario_do_suporte
from trato.disputas.prazos import adicionar_dias_uteis
from trato.financeiro import periodo
from trato.notificacoes.eventos import Evento
from trato.persistencia.chamados import ASSUNTO as ASSUNTO_RESERVADO
from trato.persistencia.sac import ENCERRADO, Chamado, Filtro, MensagemChamado

router = APIRouter(prefix="/v1/sac/chamados", tags=["atendimento"])

Categoria = Literal[
    "duvida", "reclamacao", "contestacao", "dados_pessoais", "seguranca", "outro"
]  # fmt: skip


def exigir_tabelas(contexto: Contexto) -> None:
    if not contexto.sac.disponivel():
        raise HTTPException(
            503, "O atendimento pelo app está indisponível. Escreva para o suporte por e-mail."
        )


def prazo_de_resposta(contexto: Contexto, categoria: str, agora: datetime) -> datetime:
    cfg = contexto.config.carregar()
    if categoria == "dados_pessoais":
        return agora + timedelta(days=min(15, cfg.sac_dados_pessoais_dias))
    return adicionar_dias_uteis(
        agora.astimezone(periodo.BRASILIA),
        min(5, cfg.sac_resposta_dias_uteis),
        cfg.disputas.feriados,
    )


def confirmar_ao_usuario(contexto: Contexto, chamado: Chamado) -> None:
    ate = chamado.responder_ate.astimezone(periodo.BRASILIA)
    avisar_partes(
        contexto,
        Evento.SAC_ABERTO,
        (chamado.usuario_id,),
        pedido_id=chamado.pedido_id,
        chave=f"sac:{chamado.id}:aberto",
        dados={"chamado_id": chamado.id},
        corpo=f"Seu protocolo é {chamado.protocolo}. Respondemos até {ate:%d/%m/%Y}.",
    )


class AbrirChamadoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    categoria: Categoria
    assunto: str = Field(min_length=3, max_length=200)
    texto: str = Field(min_length=1, max_length=4000)
    pedido_id: str | None = Field(None, max_length=64)


class MensagemIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    texto: str = Field(min_length=1, max_length=4000)


class ChamadoUsuarioOut(BaseModel):
    id: str
    protocolo: str
    categoria: str
    assunto: str
    status: str = Field(
        description="aberto | em_atendimento | aguardando_usuario | respondido | encerrado"
    )
    pedido_id: str | None = None
    canal: str
    criado_em: datetime
    responder_ate: datetime
    novo_prazo_ate: datetime | None = None
    motivo_extensao: str | None = None
    primeira_resposta_em: datetime | None = None
    encerrado_em: datetime | None = None
    contestacao_retencao: bool = Field(
        False, description="Chamado aberto pela contestação da retenção por cliente ausente."
    )


class MensagemUsuarioOut(BaseModel):
    id: str
    autor: str = Field(description="usuario | equipe | sistema")
    texto: str
    criada_em: datetime


class ChamadoDetalheOut(ChamadoUsuarioOut):
    mensagens: list[MensagemUsuarioOut] = Field(description="Cópia da conversa (25.3).")


class ListaChamadosOut(BaseModel):
    itens: list[ChamadoUsuarioOut]
    total: int
    limite: int
    deslocamento: int


def eh_contestacao_de_retencao(c: Chamado) -> bool:
    # O assunto é reservado: nem o usuário nem o painel abrem chamado com ele.
    return c.categoria == "contestacao" and c.assunto == ASSUNTO_RESERVADO


def _out(c: Chamado) -> ChamadoUsuarioOut:
    campos = ChamadoUsuarioOut.model_fields
    return ChamadoUsuarioOut(
        **{n: getattr(c, n) for n in campos if n != "contestacao_retencao"},
        contestacao_retencao=eh_contestacao_de_retencao(c),
    )


def _detalhe(contexto: Contexto, c: Chamado) -> ChamadoDetalheOut:
    return ChamadoDetalheOut(
        **_out(c).model_dump(),
        mensagens=[
            MensagemUsuarioOut(
                id=m.id or "", autor=m.autor_tipo, texto=m.texto, criada_em=m.criada_em
            )
            for m in contexto.sac.mensagens(c.id or "", com_internas=False)
        ],
    )


def _meu(contexto: Contexto, chamado_id: str, usuario: Usuario) -> Chamado:
    chamado = contexto.sac.obter(chamado_id)
    if chamado is None or str(chamado.usuario_id).replace("-", "") != usuario.id.replace("-", ""):
        raise HTTPException(404, "Chamado não encontrado.")
    return chamado


@router.post(
    "",
    response_model=ChamadoDetalheOut,
    status_code=201,
    summary="Abrir chamado (protocolo na hora)",
    description="`200` devolve o mesmo chamado num toque repetido (5 minutos).",
)
def abrir(
    corpo: AbrirChamadoIn,
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
):
    exigir_tabelas(contexto)
    assunto, texto = corpo.assunto.strip(), corpo.texto.strip()
    if len(assunto) < 3 or not texto:
        raise HTTPException(422, "Escreva o assunto e a mensagem.")
    if assunto.casefold() == ASSUNTO_RESERVADO.casefold():
        raise HTTPException(422, "Para contestar a retenção, use a opção dentro do pedido.")
    if corpo.pedido_id:
        pedido = contexto.pedidos.obter(corpo.pedido_id)
        if pedido is None or usuario.id not in (pedido.cliente_id, pedido.profissional_id):
            raise HTTPException(404, "Pedido não encontrado.")
    agora = contexto.agora()
    chamado, novo = contexto.sac.abrir(
        Chamado(
            categoria=corpo.categoria,
            assunto=assunto,
            canal="app",
            criado_em=agora,
            responder_ate=prazo_de_resposta(contexto, corpo.categoria, agora),
            usuario_id=usuario.id,
            pedido_id=corpo.pedido_id,
            prioridade="alta" if corpo.categoria == "seguranca" else "normal",
        ),
        MensagemChamado("usuario", texto, agora, autor_id=usuario.id),
    )
    if not novo:
        return JSONResponse(
            content=_detalhe(contexto, chamado).model_dump(mode="json"), status_code=200
        )
    confirmar_ao_usuario(contexto, chamado)
    return _detalhe(contexto, chamado)


@router.get("", response_model=ListaChamadosOut, summary="Meus chamados")
def meus(
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
) -> ListaChamadosOut:
    exigir_tabelas(contexto)
    itens, total = contexto.sac.listar(Filtro(usuario_id=usuario.id), limite, deslocamento)
    return ListaChamadosOut(
        itens=[_out(c) for c in itens], total=total, limite=limite, deslocamento=deslocamento
    )


@router.get("/{chamado_id}", response_model=ChamadoDetalheOut, summary="Chamado e conversa")
def ver(
    chamado_id: str,
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
) -> ChamadoDetalheOut:
    exigir_tabelas(contexto)
    return _detalhe(contexto, _meu(contexto, chamado_id, usuario))


@router.post(
    "/{chamado_id}/mensagens", response_model=ChamadoDetalheOut, summary="Responder no chamado"
)
def responder(
    chamado_id: str,
    corpo: MensagemIn,
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
) -> ChamadoDetalheOut:
    exigir_tabelas(contexto)
    chamado = _meu(contexto, chamado_id, usuario)
    texto = corpo.texto.strip()
    if not texto:
        raise HTTPException(422, "Escreva a mensagem.")
    anteriores = contexto.sac.mensagens(chamado_id, com_internas=False)
    ultima = anteriores[-1] if anteriores else None
    if chamado.status != ENCERRADO and not (  # toque repetido não duplica
        ultima and ultima.autor_tipo == "usuario" and ultima.texto == texto
    ):
        gravou = contexto.sac.mudar(
            chamado_id,
            {"status": "em_atendimento" if chamado.responsavel_id else "aberto"},
            MensagemChamado("usuario", texto, contexto.agora(), autor_id=usuario.id),
        )
        if not gravou:
            raise HTTPException(409, "Este chamado foi encerrado. Abra um novo.")
    elif chamado.status == ENCERRADO:
        raise HTTPException(409, "Este chamado foi encerrado. Abra um novo.")
    return _detalhe(contexto, _meu(contexto, chamado_id, usuario))
