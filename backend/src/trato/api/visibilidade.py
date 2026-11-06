"""Quem pode ver (e portanto orçar ou recusar) um pedido aberto."""

from __future__ import annotations

from trato.api.contexto import Contexto
from trato.api.repositorios import PedidoAberto

_PAGINA = 200


def pedido_visivel_ao_profissional(
    contexto: Contexto, pedido_id: str, profissional_id: str
) -> PedidoAberto | None:
    """O pedido aberto, se estiver na categoria e na região em que o profissional atua.

    É a mesma regra da lista de pedidos abertos. Percorre todas as páginas: um pedido além do
    centésimo da lista continua válido para orçar, abrir e recusar.
    """
    offset = 0
    while True:
        pagina = contexto.pedidos.listar_abertos(profissional_id, limite=_PAGINA, offset=offset)
        achado = next((p for p in pagina if p.id == pedido_id), None)
        if achado is not None:
            return achado
        if len(pagina) < _PAGINA:
            return None
        offset += _PAGINA
