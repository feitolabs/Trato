"""BE-CONFIG-PRAZOS no Postgres local: o parâmetro lido é o da versão vigente."""

from __future__ import annotations

from trato.persistencia.config import ConfigPostgres

from .test_ausencia_cliente_postgres import _no_passado

CHAVE = "lgpd_pedido_resposta_dias"


def test_le_o_parametro_publicado_e_none_sem_ele(cenario):
    config = ConfigPostgres(cenario.banco)
    assert config.parametro_inteiro(CHAVE) is None
    _no_passado(
        cenario,
        "insert into public.config_parametros (versao_id, chave, valor) "
        "select id, %s, 6 from public.config_versoes where status = 'vigente'",
        (CHAVE,),
    )
    try:
        assert config.parametro_inteiro(CHAVE) == 6
    finally:
        _no_passado(cenario, "delete from public.config_parametros where chave = %s", (CHAVE,))
    assert config.parametro_inteiro(CHAVE) is None
