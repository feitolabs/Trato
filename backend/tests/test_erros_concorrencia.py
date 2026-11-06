import psycopg.errors as pg
import pytest

from trato.persistencia.erros import BancoIndisponivel, ConflitoDeEstado, traduzir


@pytest.mark.parametrize("erro", [pg.SerializationFailure, pg.DeadlockDetected, pg.LockNotAvailable])
def test_disputa_pelo_mesmo_registro_vira_conflito_e_nao_banco_fora_do_ar(erro):
    assert isinstance(traduzir(erro("x")), ConflitoDeEstado)


def test_conexao_perdida_continua_sendo_banco_indisponivel():
    assert isinstance(traduzir(pg.ConnectionFailure("x")), BancoIndisponivel)
