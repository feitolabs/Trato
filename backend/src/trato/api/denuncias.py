"""Denúncias de perfil ou de chat: entram direto na fila de risco do painel (`alertas_risco`).

Sem tabela nova. A tabela tem `severidade` limitada a baixa/media/alta/critica e um índice único
`(pedido_id, tipo)` para alertas com pedido: uma segunda denúncia do mesmo tipo no mesmo pedido
NÃO cria outro alerta, soma o texto ao que ainda está aberto (se o alerta já foi resolvido, a nova
denúncia vira alerta novo, sem o vínculo de pedido, com o pedido citado no texto).
"""

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from typing import Protocol

SEVERIDADES = ("baixa", "media", "alta", "critica")


@dataclass(frozen=True)
class AlertaDenuncia:
    id: str
    usuario_id: str
    pedido_id: str | None
    tipo: str
    severidade: str
    detalhes: str
    resolvido: bool = False


class RepositorioDenuncias(Protocol):
    def registrar(
        self,
        denunciado_id: str,
        pedido_id: str | None,
        tipo: str,
        severidade: str,
        detalhes: str,
    ) -> str:
        """Cria (ou soma ao alerta aberto do mesmo pedido e tipo). Devolve o id do alerta."""
        ...


class DenunciasEmMemoria:
    def __init__(self) -> None:
        self.alertas: dict[str, AlertaDenuncia] = {}
        self._trava = threading.Lock()

    def registrar(
        self,
        denunciado_id: str,
        pedido_id: str | None,
        tipo: str,
        severidade: str,
        detalhes: str,
    ) -> str:
        with self._trava:
            if pedido_id is not None:
                for a in self.alertas.values():
                    if a.pedido_id != pedido_id or a.tipo != tipo:
                        continue
                    if a.resolvido:
                        detalhes = f"Pedido {pedido_id}: {detalhes}"
                        pedido_id = None
                        break
                    melhor = (
                        "alta"
                        if severidade == "alta" and a.severidade in ("baixa", "media")
                        else a.severidade
                    )
                    self.alertas[a.id] = replace(
                        a, severidade=melhor, detalhes=f"{a.detalhes}\n---\n{detalhes}"
                    )
                    return a.id
            novo = AlertaDenuncia(
                str(uuid.uuid4()), denunciado_id, pedido_id, tipo, severidade, detalhes
            )
            self.alertas[novo.id] = novo
            return novo.id
