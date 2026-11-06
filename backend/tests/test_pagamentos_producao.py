import pytest

from trato.config import Config
from trato.pagamentos.montagem import escolher_provedor
from trato.pagamentos.provedor import ErroProvedor, ProvedorFake


def _config(ambiente: str, provedor: str) -> Config:
    return Config(trato_ambiente=ambiente, trato_provedor_pagamento=provedor)


def test_producao_recusa_provedor_falso():
    with pytest.raises(ErroProvedor):
        escolher_provedor(_config("producao", "fake"))


def test_desenvolvimento_aceita_provedor_falso():
    assert isinstance(escolher_provedor(_config("desenvolvimento", "fake")), ProvedorFake)
