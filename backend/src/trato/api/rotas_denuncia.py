"""POST /v1/denuncias: cliente ou profissional denuncia um perfil ou o chat de um pedido.

A denúncia vira um alerta na fila de risco do painel (tipo `denuncia_perfil` ou `denuncia_chat`).
Quem denuncia o chat precisa ser parte do pedido (terceiro recebe 404) e o denunciado é a outra
parte. Ninguém denuncia a si mesmo.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.denuncias import marcador
from trato.api.servicos import carregar_pedido
from trato.seguranca.config import obter_config_seguranca
from trato.seguranca.texto_livre import limpar_texto

router = APIRouter(prefix="/v1", tags=["denuncias"])

# Graves retêm o valor ainda não liberado do pedido até a análise (8.8 e 9.6).
MOTIVOS_GRAVES = ("assedio", "fraude", "dano")
# Denúncia de PERFIL: 1 por alvo a cada 24 h e no máximo 10 por dia por denunciante.
PERFIL_MAX_POR_DIA = 10
JANELA_PERFIL = timedelta(hours=24)


class DenunciaIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    alvo_tipo: Literal["perfil", "chat"]
    denunciado_id: str = Field(min_length=1, max_length=64)
    pedido_id: str | None = Field(default=None, max_length=64)
    motivo: Literal["assedio", "fraude", "dano", "cobranca_fora", "perfil_falso", "outro"]
    detalhes: str = Field(min_length=5, max_length=500)


class DenunciaOut(BaseModel):
    id: str
    status: str = "recebida"
    mensagem: str = "Denúncia enviada para análise da nossa equipe."


@router.post(
    "/denuncias",
    response_model=DenunciaOut,
    status_code=201,
    summary="Denunciar um perfil ou o comportamento no chat de um pedido",
)
def denunciar(
    corpo: DenunciaIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> DenunciaOut:
    if corpo.denunciado_id == usuario.id:
        raise HTTPException(422, "Você não pode denunciar a si mesmo.")
    pedido_id: str | None = None
    if corpo.alvo_tipo == "chat":
        if not corpo.pedido_id:
            raise HTTPException(422, "Informe o pedido da conversa denunciada.")
        pedido = carregar_pedido(contexto, corpo.pedido_id, usuario)  # terceiro: 404
        if corpo.denunciado_id not in {pedido.cliente_id, pedido.profissional_id}:
            raise HTTPException(422, "A pessoa denunciada precisa ser parte deste pedido.")
        pedido_id = pedido.id
    elif contexto.usuarios.detalhe(corpo.denunciado_id) is None:
        raise HTTPException(404, "Perfil não encontrado.")
    agora = contexto.agora()
    if corpo.alvo_tipo == "perfil":
        desde = agora - JANELA_PERFIL
        mesmo_alvo = marcador(usuario.id, corpo.denunciado_id)
        if contexto.denuncias.contar("denuncia_perfil", mesmo_alvo, desde) > 0:
            raise HTTPException(
                409, "Você já denunciou este perfil nas últimas 24 horas. Aguardamos a análise."
            )
        if contexto.denuncias.contar("denuncia_perfil", marcador(usuario.id), desde) >= (
            PERFIL_MAX_POR_DIA
        ):
            raise HTTPException(
                429,
                "Você atingiu o limite de denúncias de perfil por dia. Tente de novo amanhã.",
            )
    texto = limpar_texto(corpo.detalhes, "detalhes", 500, obter_config_seguranca())
    detalhes = (
        f"Denúncia de {corpo.alvo_tipo} ({corpo.motivo})"
        f"{marcador(usuario.id, corpo.denunciado_id)} {texto}"
    )
    alerta_id = contexto.denuncias.registrar(
        corpo.denunciado_id,
        pedido_id,
        f"denuncia_{corpo.alvo_tipo}",
        "alta" if corpo.motivo in MOTIVOS_GRAVES else "media",
        detalhes,
        agora,
    )
    return DenunciaOut(id=alerta_id)
