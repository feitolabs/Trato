"""Evidência de reenvio offline: `offline_capturada_em` no check-in/check-out.

O app guarda a ação sem internet e a reenvia depois. A hora que vale é SEMPRE a do servidor (a
foto leva a hora em que o servidor a recebeu, `uploads/provas.py`). O campo só diz quando o
aparelho diz que capturou: é evidência para a mediação, nunca entra em prazo, regra nem dinheiro.
Limites em `TRATO_UP_OFFLINE_*`. Fora da janela, a ação é recusada com 422.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from fastapi import HTTPException
from pydantic import AwareDatetime, TypeAdapter, ValidationError

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto
from trato.pedidos.estados import Acao, Pedido
from trato.uploads.config import ConfigUploads

CAMPO = "offline_capturada_em"
ACOES = frozenset({Acao.FAZER_CHECK_IN, Acao.FAZER_CHECK_OUT})
_DATA = TypeAdapter(AwareDatetime)


def separar(
    acao: Acao, bruto: dict[str, Any] | None, agora: datetime, config: ConfigUploads
) -> tuple[dict[str, Any] | None, datetime | None]:
    """Tira o campo da prova (as regras não o conhecem) e confere a janela."""
    if acao not in ACOES or not bruto or CAMPO not in bruto:
        return bruto, None
    resto = {k: v for k, v in bruto.items() if k != CAMPO}
    valor = bruto[CAMPO]
    if valor is None:
        return resto, None
    try:
        capturada = _DATA.validate_python(valor)
    except ValidationError:
        raise HTTPException(422, f"{CAMPO} precisa ser uma data com fuso (ISO 8601).") from None
    if capturada > agora + timedelta(seconds=config.offline_tolerancia_futuro_s):
        raise HTTPException(422, f"{CAMPO} está no futuro.")
    if agora - capturada > timedelta(hours=config.offline_janela_max_horas):
        raise HTTPException(
            422,
            f"{CAMPO} fora da janela de {config.offline_janela_max_horas} horas: "
            "refaça a ação com o aparelho conectado.",
        )
    return resto, capturada


def registrar(
    contexto: Contexto,
    usuario: Usuario,
    pedido: Pedido,
    acao: Acao,
    capturada_em: datetime,
    recebida_em: datetime,
) -> None:
    """Grava a evidência na auditoria (Postgres) ou em `extras["evidencias_offline"]` (memória)."""
    dados = {
        "acao": acao.value,
        "capturada_em_informada": capturada_em.isoformat(),
        "recebida_em_servidor": recebida_em.isoformat(),
    }
    auditoria = contexto.extras.get("auditoria")
    if auditoria is not None:
        auditoria.registrar(
            ator_id=usuario.id,
            ator_tipo="profissional" if usuario.papel is PapelUsuario.PROFISSIONAL else "cliente",
            acao="evidencia_offline",
            entidade="pedido",
            entidade_id=pedido.id,
            depois=dados,
        )
        return
    contexto.extras.setdefault("evidencias_offline", []).append(
        {"pedido_id": pedido.id, "ator_id": usuario.id, **dados}
    )
