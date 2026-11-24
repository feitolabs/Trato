"""Reagendamento: proposta de nova janela do atendimento, dentro do pedido.

Cliente ou profissional propõe; a outra parte aceita ou recusa (o proponente pode cancelar).
No máximo UMA proposta pendente por pedido (no Postgres, o índice único parcial da migration
20261123232000; em memória, a trava). Este módulo é só o armazenamento: quem decide é a rota.
"""

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Protocol

STATUS = ("pendente", "aceito", "recusado", "cancelado")


class PropostaPendente(Exception):
    """Já existe uma proposta aguardando resposta neste pedido."""


@dataclass(frozen=True)
class Reagendamento:
    id: str
    pedido_id: str
    proposto_por: str
    nova_janela_inicio: datetime
    nova_janela_fim: datetime
    motivo: str
    status: str
    criado_em: datetime
    respondido_por: str | None = None
    respondido_em: datetime | None = None


class RepositorioReagendamentos(Protocol):
    def propor(
        self,
        pedido_id: str,
        proposto_por: str,
        inicio: datetime,
        fim: datetime,
        motivo: str,
        agora: datetime,
    ) -> Reagendamento:
        """Cria a proposta pendente. Levanta `PropostaPendente` se já houver uma."""
        ...

    def obter(self, reagendamento_id: str) -> Reagendamento | None: ...

    def listar(self, pedido_id: str) -> list[Reagendamento]:
        """Mais recentes primeiro."""
        ...

    def contar_propostas(self, pedido_id: str, desde: datetime) -> int:
        """Quantas propostas o pedido recebeu desde `desde` (qualquer status)."""
        ...

    def responder(
        self, reagendamento_id: str, status: str, por: str, agora: datetime
    ) -> Reagendamento | None:
        """Fecha a proposta SE ainda estiver pendente (atômico). `None` = já respondida."""
        ...


class ReagendamentosEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Reagendamento] = {}
        self._ordem: list[str] = []
        self._trava = threading.Lock()

    def propor(
        self,
        pedido_id: str,
        proposto_por: str,
        inicio: datetime,
        fim: datetime,
        motivo: str,
        agora: datetime,
    ) -> Reagendamento:
        with self._trava:
            if any(
                r.pedido_id == pedido_id and r.status == "pendente" for r in self._itens.values()
            ):
                raise PropostaPendente
            nova = Reagendamento(
                id=str(uuid.uuid4()),
                pedido_id=pedido_id,
                proposto_por=proposto_por,
                nova_janela_inicio=inicio,
                nova_janela_fim=fim,
                motivo=motivo,
                status="pendente",
                criado_em=agora,
            )
            self._itens[nova.id] = nova
            self._ordem.append(nova.id)
            return nova

    def obter(self, reagendamento_id: str) -> Reagendamento | None:
        return self._itens.get(reagendamento_id)

    def listar(self, pedido_id: str) -> list[Reagendamento]:
        return [
            self._itens[i] for i in reversed(self._ordem) if self._itens[i].pedido_id == pedido_id
        ]

    def contar_propostas(self, pedido_id: str, desde: datetime) -> int:
        return sum(
            1 for r in self._itens.values() if r.pedido_id == pedido_id and r.criado_em >= desde
        )

    def responder(
        self, reagendamento_id: str, status: str, por: str, agora: datetime
    ) -> Reagendamento | None:
        with self._trava:
            atual = self._itens.get(reagendamento_id)
            if atual is None or atual.status != "pendente":
                return None
            novo = replace(atual, status=status, respondido_por=por, respondido_em=agora)
            self._itens[reagendamento_id] = novo
            return novo
