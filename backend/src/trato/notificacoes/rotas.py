"""Rotas v1 de notificações, dispositivos de push, preferências e conversas (todas autenticadas).

`GET /v1/notificacoes` substitui a versão simples de `api/rotas_app.py`: este roteador é
registrado ANTES, então vale o daqui (mesmo formato de resposta, mais `canal`/`lida_em`).
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, FastAPI, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.notificacoes.canais import CANAIS_DE_NOTIFICACAO, canais_da_config
from trato.notificacoes.config import obter_config_notificacoes
from trato.notificacoes.eventos import MODELOS
from trato.notificacoes.ganchos import criar_gancho
from trato.notificacoes.mensagens import (
    ConversasAppEmMemoria,
    ConversasAppPostgres,
    ServicoMensagens,
)
from trato.notificacoes.postgres import NotificacoesServicoPostgres
from trato.notificacoes.repositorio import PLATAFORMAS, RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.persistencia.erros import DadosInvalidos

router = APIRouter(prefix="/v1", tags=["notificações"])

_PESSOAS = (PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)
_CATEGORIAS = {m.categoria.value for m in MODELOS.values()}
# SMS e WhatsApp não são canais de notificação comum (D14): ficam de fora das preferências.
_CANAIS_PREFERENCIA = ("app", "push", "email")


class NotificacaoOut(BaseModel):
    id: str
    tipo: str
    canal: str = "app"
    titulo: str
    corpo: str | None
    dados: dict
    criada_em: datetime
    lida: bool
    lida_em: datetime | None = None


class PreferenciasIO(BaseModel):
    model_config = ConfigDict(extra="forbid")

    categorias: dict[str, dict[str, bool]] = Field(
        description="categoria -> canal (app, push, email) -> ligado."
    )


class DispositivoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=8, max_length=4096)
    plataforma: str


class ConversaOut(BaseModel):
    id: str
    pedido_id: str
    outra_parte_id: str
    encerrada: bool
    nao_lidas: int
    ultima_mensagem: str | None
    ultima_em: datetime | None
    ultima_minha: bool | None


class LeituraOut(BaseModel):
    lida_em: datetime


class LeituraConversaOut(BaseModel):
    marcadas: int


# --- montagem dos serviços ------------------------------------------------------------------


def _servicos(request: Request, contexto: Contexto) -> tuple[ServicoNotificacoes, ServicoMensagens]:
    """Monta (uma vez por app) os serviços a partir do contexto: Postgres se houver banco."""
    guardado = getattr(request.app.state, "servicos_notificacoes", None)
    if guardado is None:
        guardado = montar_servicos(contexto)
        request.app.state.servicos_notificacoes = guardado
    return guardado


def montar_servicos(
    contexto: Contexto, servico: ServicoNotificacoes | None = None
) -> tuple[ServicoNotificacoes, ServicoMensagens]:
    config = obter_config_notificacoes()
    banco = contexto.extras.get("banco")
    if servico is None:
        repo = NotificacoesServicoPostgres(banco) if banco is not None else RepositorioEmMemoria()
        servico = ServicoNotificacoes(repo, canais_da_config(config), config, contexto.agora)
    mensagens = ServicoMensagens(
        ConversasAppPostgres(banco) if banco is not None else ConversasAppEmMemoria(contexto)
    )
    contexto.apos_transicao.append(criar_gancho(servico))
    return servico, mensagens


def ligar_ao_contexto(
    app: FastAPI, contexto: Contexto, servico: ServicoNotificacoes | None = None
) -> ServicoNotificacoes:
    """Monta os serviços já com este contexto (e o gancho das transições). Os testes e a fábrica
    usam isto para trocar os canais por fakes."""
    guardado = montar_servicos(contexto, servico)
    app.state.servicos_notificacoes = guardado
    return guardado[0]


def _servico(request: Request, contexto: Contexto = Depends(obter_contexto)) -> ServicoNotificacoes:
    return _servicos(request, contexto)[0]


def _mensagens(request: Request, contexto: Contexto = Depends(obter_contexto)) -> ServicoMensagens:
    return _servicos(request, contexto)[1]


def _saida(r) -> NotificacaoOut:  # noqa: ANN001
    return NotificacaoOut(
        id=r.id, tipo=r.tipo, canal=r.canal, titulo=r.titulo, corpo=r.corpo, dados=r.dados,
        criada_em=r.criada_em, lida=r.lida_em is not None, lida_em=r.lida_em,
    )  # fmt: skip


# --- notificações ---------------------------------------------------------------------------


@router.get("/notificacoes", response_model=list[NotificacaoOut], summary="Minhas notificações")
def listar_notificacoes(
    nao_lidas: bool = False,
    limite: Annotated[int, Query(ge=1, le=200)] = 50,
    usuario: Usuario = Depends(exigir_papel(*_PESSOAS)),
    servico: ServicoNotificacoes = Depends(_servico),
    contexto: Contexto = Depends(obter_contexto),
) -> list[NotificacaoOut]:
    itens = [_saida(r) for r in servico.repo.listar(usuario.id, nao_lidas, limite)]
    if contexto.extras.get("banco") is None:
        # Modo memória: quem ainda grava por `contexto.notificacoes` continua aparecendo.
        for n in contexto.notificacoes.listar(usuario.id, nao_lidas):
            itens.append(
                NotificacaoOut(
                    id=n.id,
                    tipo=n.tipo,
                    canal=n.canal,
                    titulo=n.titulo,
                    corpo=n.corpo,
                    dados=n.dados,
                    criada_em=n.criada_em,
                    lida=n.lida_em is not None,
                    lida_em=n.lida_em,
                )  # fmt: skip
            )
        itens.sort(key=lambda n: n.criada_em, reverse=True)
    return itens[:limite]


@router.get(
    "/notificacoes/preferencias", response_model=PreferenciasIO, summary="Minhas preferências"
)
def ver_preferencias(
    usuario: Usuario = Depends(exigir_papel(*_PESSOAS)),
    servico: ServicoNotificacoes = Depends(_servico),
) -> PreferenciasIO:
    return PreferenciasIO(categorias=servico.preferencias_efetivas(usuario.id))


@router.put(
    "/notificacoes/preferencias", response_model=PreferenciasIO, summary="Mudar preferências"
)
def mudar_preferencias(
    corpo: PreferenciasIO,
    usuario: Usuario = Depends(exigir_papel(*_PESSOAS)),
    servico: ServicoNotificacoes = Depends(_servico),
) -> PreferenciasIO:
    """Troca só o que veio; o resto continua como estava. SMS/WhatsApp não são preferência."""
    for categoria, canais in corpo.categorias.items():
        if categoria not in _CATEGORIAS:
            raise DadosInvalidos(f"Categoria desconhecida: {categoria}.")
        for canal in canais:
            if canal not in _CANAIS_PREFERENCIA:
                raise DadosInvalidos(f"Canal não configurável: {canal}.")
    atuais = servico.repo.preferencias(usuario.id)
    for categoria, canais in corpo.categorias.items():
        atuais.setdefault(categoria, {}).update(canais)
    servico.repo.salvar_preferencias(usuario.id, atuais, servico.agora())
    return PreferenciasIO(categorias=servico.preferencias_efetivas(usuario.id))


@router.post(
    "/notificacoes/{notificacao_id}/lida", response_model=NotificacaoOut, summary="Marcar como lida"
)
def marcar_notificacao_lida(
    notificacao_id: str,
    usuario: Usuario = Depends(exigir_papel(*_PESSOAS)),
    servico: ServicoNotificacoes = Depends(_servico),
) -> NotificacaoOut:
    return _saida(servico.repo.marcar_lida(notificacao_id, usuario.id, servico.agora()))


@router.post("/dispositivos", status_code=204, summary="Registrar token de push")
def registrar_dispositivo(
    corpo: DispositivoIn,
    usuario: Usuario = Depends(exigir_papel(*_PESSOAS)),
    servico: ServicoNotificacoes = Depends(_servico),
) -> None:
    if corpo.plataforma not in PLATAFORMAS:
        raise DadosInvalidos(f"Plataforma deve ser uma de: {', '.join(PLATAFORMAS)}.")
    servico.repo.registrar_dispositivo(
        usuario.id, corpo.token.strip(), corpo.plataforma, servico.agora()
    )


# --- conversas ------------------------------------------------------------------------------


@router.get("/conversas", response_model=list[ConversaOut], summary="Minhas conversas")
def listar_conversas(
    usuario: Usuario = Depends(exigir_papel(*_PESSOAS)),
    mensagens: ServicoMensagens = Depends(_mensagens),
) -> list[ConversaOut]:
    return [
        ConversaOut(
            id=c.id,
            pedido_id=c.pedido_id,
            outra_parte_id=c.outra_parte_id,
            encerrada=c.encerrada,
            nao_lidas=c.nao_lidas,
            ultima_mensagem=c.ultima_texto,
            ultima_em=c.ultima_em,
            ultima_minha=c.ultima_minha,
        )  # fmt: skip
        for c in mensagens.conversas(usuario.id)
    ]


@router.post(
    "/mensagens/{mensagem_id}/lida", response_model=LeituraOut, summary="Marcar mensagem como lida"
)
def marcar_mensagem_lida(
    mensagem_id: int,
    usuario: Usuario = Depends(exigir_papel(*_PESSOAS)),
    mensagens: ServicoMensagens = Depends(_mensagens),
    servico: ServicoNotificacoes = Depends(_servico),
) -> LeituraOut:
    return LeituraOut(lida_em=mensagens.repo.marcar_lida(mensagem_id, usuario.id, servico.agora()))


@router.post(
    "/conversas/{conversa_id}/lida",
    response_model=LeituraConversaOut,
    summary="Marcar a conversa toda como lida",
)
def marcar_conversa_lida(
    conversa_id: str,
    usuario: Usuario = Depends(exigir_papel(*_PESSOAS)),
    mensagens: ServicoMensagens = Depends(_mensagens),
    servico: ServicoNotificacoes = Depends(_servico),
) -> LeituraConversaOut:
    n = mensagens.repo.marcar_conversa_lida(conversa_id, usuario.id, servico.agora())
    return LeituraConversaOut(marcadas=n)


def registrar_rotas(app: FastAPI, contexto: Contexto | None = None) -> None:
    """Liga as rotas ao app. Chame ANTES de `criar_router()` para valer sobre o GET antigo.

    Com `contexto`, já monta os serviços e o gancho das transições; sem ele, tudo é montado
    na primeira requisição (e o gancho só vale daí em diante).
    """
    app.include_router(router)
    if contexto is not None:
        ligar_ao_contexto(app, contexto)


__all__ = ["CANAIS_DE_NOTIFICACAO", "ligar_ao_contexto", "registrar_rotas", "router"]
