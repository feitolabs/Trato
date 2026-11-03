"""Guarda o id do registro de auditoria gravado na requisição atual (cabeçalho `X-Auditoria-Id`)."""

from __future__ import annotations

from contextvars import ContextVar

# Ids gravados durante a requisição atual. A lista é criada pelo middleware (antes da rota rodar) e
# a rota só acrescenta: assim o id chega ao cabeçalho `X-Auditoria-Id` mesmo quando a rota síncrona
# roda em outra thread. Fora de uma requisição (testes, scripts) não há lista e nada acontece.
_IDS_DA_REQUISICAO: ContextVar[list[int] | None] = ContextVar("ids_auditoria", default=None)


def iniciar_captura_de_ids() -> list[int]:
    """Chamado pelo middleware no início de cada requisição."""
    ids: list[int] = []
    _IDS_DA_REQUISICAO.set(ids)
    return ids


def anotar_id_gravado(registro_id: int) -> None:
    ids = _IDS_DA_REQUISICAO.get()
    if ids is not None:
        ids.append(registro_id)
