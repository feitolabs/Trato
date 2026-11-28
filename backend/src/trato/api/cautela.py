"""Medidas de cautela de um incidente (Termos 9.6) que o sistema cumpre enquanto o incidente
não é encerrado: bloqueio de contato entre as partes e preservação dos registros do pedido.
Suspender conta continua sendo decisão do analista (seção 20)."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

from fastapi import HTTPException

from trato.notificacoes.eventos import Evento
from trato.pedidos.estados import Pedido

log = logging.getLogger("trato.cautela")
CONTATO_BLOQUEADO = (
    "O contato entre as partes está bloqueado enquanto o Trato apura um relato (Termos 9.6)."
)
RELATO_RETIDO = (
    "Texto retido enquanto o contato entre as partes está bloqueado (Termos 9.6). O Trato analisa."
)
PRESERVACAO = "Há registros preservados por apuração em andamento (Termos 9.6)"


def _mesmo(a: str | None, b: str | None) -> bool:
    return bool(a and b) and a.replace("-", "") == b.replace("-", "")


def _pedidos(contexto: Any, medida: str) -> list[Pedido]:
    ids = contexto.incidentes.pedidos_sob_medida(medida)
    return [p for p in (contexto.pedidos.obter(i) for i in ids) if p is not None]


def contato_bloqueado(contexto: Any, um: str, outro: str) -> bool:
    """Vale para o par de pessoas, em qualquer pedido entre elas."""
    for p in _pedidos(contexto, "bloquear_contato"):
        partes = (p.cliente_id, p.profissional_id)
        if all(any(_mesmo(x, y) for y in partes) for x in (um, outro)):
            return True
    return False


def exigir_contato_livre(contexto: Any, pedido: Pedido, profissional_id: str) -> None:
    if contato_bloqueado(contexto, pedido.cliente_id, profissional_id):
        raise HTTPException(409, CONTATO_BLOQUEADO)


def registros_preservados(contexto: Any, usuario_id: str) -> bool:
    # O banco (122500) também protege o envolvido, mesmo sem pedido; sem a função, valem as
    # partes dos pedidos.
    no_banco = getattr(contexto.incidentes, "usuario_preservado", None)
    if no_banco is not None and no_banco(usuario_id):
        return True
    return any(
        _mesmo(usuario_id, p.cliente_id) or _mesmo(usuario_id, p.profissional_id)
        for p in _pedidos(contexto, "preservar_registros")
    )


def avisar_cautela_atrasada(contexto: Any, notificador: Any, agora: datetime) -> int:
    """Prazo vencido sem cautela adotada: avisa a equipe de segurança, uma vez por incidente."""
    if not contexto.incidentes.disponivel():
        return 0
    abertos, _ = contexto.incidentes.listar("aberto", None, 100, 0)
    atrasados = [i for i in abertos if i.cautela_adotada_em is None and agora > i.cautela_ate]
    equipe = contexto.incidentes.equipe_de_seguranca() if atrasados else []
    for item in atrasados:
        log.error("Incidente %s passou do prazo de cautela sem medida (9.6)", item.protocolo)
        for pessoa in equipe if notificador is not None else []:
            try:
                notificador.notificar(
                    Evento.INCIDENTE_CAUTELA_ATRASADA,
                    pessoa,
                    chave=f"incidente:{item.id}:cautela",
                    corpo=f"O incidente {item.protocolo} passou do prazo de 24 horas sem "
                    "cautela adotada. Abra o painel e decida as medidas.",
                )
            except Exception:  # noqa: BLE001 - aviso é secundário
                log.exception("Aviso de cautela atrasada falhou (%s)", item.protocolo)
    return len(atrasados)
