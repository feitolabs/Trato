"""Denúncias de perfil ou de chat: entram direto na fila de risco do painel (`alertas_risco`).

Sem tabela nova. A tabela tem `severidade` limitada a baixa/media/alta/critica e um índice único
`(pedido_id, tipo)` para alertas com pedido: uma segunda denúncia do mesmo tipo no mesmo pedido
NÃO cria outro alerta, soma o texto ao que ainda está aberto (se o alerta já foi resolvido, a nova
denúncia vira alerta novo, sem o vínculo de pedido, com o pedido citado no texto). O texto somado
nunca passa de `TETO_DETALHES` caracteres.

O texto de cada denúncia traz quem denunciou e quem foi denunciado no formato
`... por <denunciante> contra <denunciado>: <texto>`; os limites de frequência contam por esse
trecho (sem coluna nova).
"""

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Protocol

SEVERIDADES = ("baixa", "media", "alta", "critica")
TETO_DETALHES = 2000
SEPARADOR = "\n---\n"


def marcador(denunciante_id: str, denunciado_id: str | None = None) -> str:
    """Trecho do texto que identifica o par (ou só o denunciante, sem `denunciado_id`)."""
    if denunciado_id is None:
        return f" por {denunciante_id} contra "
    return f" por {denunciante_id} contra {denunciado_id}:"


@dataclass(frozen=True)
class AlertaDenuncia:
    id: str
    usuario_id: str
    pedido_id: str | None
    tipo: str
    severidade: str
    detalhes: str
    resolvido: bool = False
    criado_em: datetime | None = None


class RepositorioDenuncias(Protocol):
    def registrar(
        self,
        denunciado_id: str,
        pedido_id: str | None,
        tipo: str,
        severidade: str,
        detalhes: str,
        agora: datetime,
    ) -> str:
        """Cria (ou soma ao alerta aberto do mesmo pedido e tipo). Devolve o id do alerta."""
        ...

    def contar(self, tipo: str, trecho: str, desde: datetime) -> int:
        """Quantos alertas do tipo, criados desde `desde`, trazem `trecho` no texto."""
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
        agora: datetime,
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
                    junto = f"{a.detalhes}{SEPARADOR}{detalhes}"[:TETO_DETALHES]
                    self.alertas[a.id] = replace(a, severidade=melhor, detalhes=junto)
                    return a.id
            novo = AlertaDenuncia(
                str(uuid.uuid4()),
                denunciado_id,
                pedido_id,
                tipo,
                severidade,
                detalhes[:TETO_DETALHES],
                criado_em=agora,
            )
            self.alertas[novo.id] = novo
            return novo.id

    def contar(self, tipo: str, trecho: str, desde: datetime) -> int:
        return sum(
            1
            for a in self.alertas.values()
            if a.tipo == tipo
            and a.criado_em is not None
            and a.criado_em >= desde
            and trecho in a.detalhes
        )
