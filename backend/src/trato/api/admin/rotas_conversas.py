"""Leitura das conversas de um pedido pela equipe (Termos 11.3).

Não há leitura de rotina: só com um dos motivos do termo, com o vínculo conferido no pedido,
motivo escrito, permissão `conversas_ler` e o acesso gravado na auditoria ANTES do texto sair.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import PapelEquipe, Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.api.denuncias import marcador
from trato.pedidos.estados import Pedido

router = APIRouter(prefix="/v1/admin/pedidos", tags=["admin: conversas"])

Base = Literal[
    "relato", "disputa", "denuncia", "incidente", "fraude", "ordem_judicial",
    "autorizacao_usuario",
]  # fmt: skip


class LeituraIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=1000)
    base: Base
    referencia: str | None = Field(
        None,
        max_length=120,
        description="Número do processo (ordem_judicial) ou protocolo SAC (autorizacao_usuario).",
    )


class MensagemLidaOut(BaseModel):
    id: int
    autor_id: str
    texto: str = Field(description="Original, como foi escrito (prova).")
    texto_exibido: str = Field(description="O que a outra parte vê no app.")
    mascarada: bool
    enviada_em: datetime


class ConversaLidaOut(BaseModel):
    conversa_id: str
    profissional_id: str
    mensagens: list[MensagemLidaOut]


class LeituraOut(BaseModel):
    pedido_id: str
    base: str
    conversas: list[ConversaLidaOut]


def _vinculo(
    contexto: Contexto, pedido: Pedido, corpo: LeituraIn, participantes: list[str]
) -> bool:
    referencia = (corpo.referencia or "").strip()
    if corpo.base == "ordem_judicial":
        return len(referencia) >= 5
    if corpo.base in ("disputa", "relato") and contexto.disputas.obter(pedido.id) is not None:
        return True
    if corpo.base == "disputa":
        return False
    if corpo.base == "relato" and contexto.garantias.retrabalhos(pedido.id):
        return True
    if corpo.base == "fraude" and contexto.contestacoes.perdidas_do_pedido(pedido.id):
        return True
    if corpo.base in ("denuncia", "fraude"):
        alertas = getattr(contexto.denuncias, "alertas", None)  # memória
        if alertas is not None and any(a.pedido_id == pedido.id for a in alertas.values()):
            return True
    if corpo.base == "autorizacao_usuario" and not referencia:
        return False
    return contexto.chamados.vinculo(corpo.base, pedido.id, participantes, referencia or None)


def _das_partes(
    contexto: Contexto, pedido: Pedido, corpo: LeituraIn, achadas: list[tuple[str, str]]
) -> list[tuple[str, str]]:
    def chave(valor: str | None) -> str:
        return str(valor or "").replace("-", "")

    envolvidos = {chave(pedido.profissional_id)} - {""}
    candidatos = [p for _, p in achadas]
    if corpo.base != "ordem_judicial":
        referencia = (corpo.referencia or "").strip() or None
        envolvidos |= {
            chave(p)
            for p in contexto.chamados.partes_do_vinculo(
                corpo.base, pedido.id, referencia, candidatos
            )
        }
        alertas = getattr(contexto.denuncias, "alertas", None)  # memória
        if corpo.base in ("denuncia", "fraude") and alertas is not None:
            for a in alertas.values():
                if a.pedido_id != pedido.id:
                    continue
                envolvidos |= {
                    chave(p)
                    for p in candidatos
                    if p == a.usuario_id or marcador(p, a.usuario_id) in a.detalhes
                }
    return [(c, p) for c, p in achadas if chave(p) in envolvidos]


@router.post(
    "/{pedido_id}/conversas/leitura",
    response_model=LeituraOut,
    summary="Ler as mensagens de um pedido, com motivo e base (auditado)",
)
def ler_conversas(
    pedido_id: str,
    corpo: LeituraIn,
    operador: Operador = Depends(exigir(Permissao.CONVERSAS_LER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> LeituraOut:
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        raise HTTPException(422, "Explique o motivo da leitura.")
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    if corpo.base == "ordem_judicial" and operador.membro.papel is not PapelEquipe.ADMINISTRADOR:
        raise HTTPException(403, "Leitura por ordem judicial: só um administrador.")
    achadas = contexto.conversas.do_pedido(pedido.id)
    participantes = [
        u for u in (pedido.cliente_id, pedido.profissional_id, *(p for _, p in achadas)) if u
    ]
    if not _vinculo(contexto, pedido, corpo, participantes):
        raise HTTPException(
            409, "Este pedido não tem o vínculo que essa base exige: nada foi lido."
        )
    # Só as conversas entre as partes do vínculo: o cliente com o profissional contratado, ou com
    # o profissional que o fato (denúncia, incidente, chamado) envolve.
    achadas = _das_partes(contexto, pedido, corpo, achadas)
    with contexto.transacao():  # a auditoria grava primeiro; se falhar, nada é devolvido
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="dado_pessoal.conversa_lida",
            entidade="pedidos",
            entidade_id=pedido.id,
            antes={},
            depois={
                "base": corpo.base,
                "referencia": corpo.referencia,
                "conversas": [c for c, _ in achadas],
            },
            motivo=motivo,
        )
    conversas = []
    for conversa, profissional in achadas:
        originais = contexto.conversas.originais(conversa)
        conversas.append(
            ConversaLidaOut(
                conversa_id=conversa,
                profissional_id=profissional,
                mensagens=[
                    MensagemLidaOut(
                        id=m.id,
                        autor_id=m.autor_id,
                        texto=originais.get(m.id, m.texto),
                        texto_exibido=m.texto,
                        mascarada=m.mascarada,
                        enviada_em=m.enviada_em,
                    )
                    for m in contexto.conversas.listar(conversa)
                ],
            )
        )
    return LeituraOut(pedido_id=pedido.id, base=corpo.base, conversas=conversas)
