"""O banco devolve o aditivo com o id do pedido em hex; a rota traz o do pedido com hífens.
Antes, aprovar o aditivo dava 404 "Aditivo não encontrado" por comparar os dois como texto."""

from __future__ import annotations

import uuid

from trato.pagamentos.orquestrador import _mesmo_id


def test_mesmo_id_ignora_hifen_e_caixa():
    u = uuid.uuid4()
    assert _mesmo_id(u.hex, str(u))
    assert _mesmo_id(str(u), u.hex.upper())
    assert not _mesmo_id(u.hex, str(uuid.uuid4()))
