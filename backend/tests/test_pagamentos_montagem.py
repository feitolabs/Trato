# ruff: noqa: S106  (chaves de teste inventadas, não são segredos)
import pytest

from trato.config import Config
from trato.pagamentos.montagem import escolher_provedor
from trato.pagamentos.provedor import ErroProvedor, ProvedorFake


def test_padrao_e_o_provedor_falso():
    assert isinstance(escolher_provedor(Config(_env_file=None)), ProvedorFake)


def test_stripe_so_em_modo_teste():
    with pytest.raises(ErroProvedor):  # sem chave
        escolher_provedor(Config(_env_file=None, trato_provedor_pagamento="stripe"))
    with pytest.raises(ErroProvedor):  # chave real é recusada
        escolher_provedor(
            Config(
                _env_file=None,
                trato_provedor_pagamento="stripe",
                stripe_secret_key="sk_live_x",
                stripe_webhook_secret="whsec_x",
            )
        )
    ok = escolher_provedor(
        Config(
            _env_file=None,
            trato_provedor_pagamento="stripe",
            stripe_secret_key="sk_test_x",
            stripe_webhook_secret="whsec_x",
        )
    )
    assert ok.nome == "stripe_teste"


def test_nome_invalido():
    with pytest.raises(ErroProvedor):
        escolher_provedor(Config(_env_file=None, trato_provedor_pagamento="boleto"))
