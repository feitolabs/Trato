"""Migration `mensagens_entregue_em` contra o Postgres local descartável (nunca o Supabase)."""

from __future__ import annotations

import psycopg
import pytest

from .pg_local import RAIZ
from .test_fluxo_postgres import abrir_pedido

pytestmark = pytest.mark.integracao

ROLLBACK = RAIZ / "supabase" / "rollback" / "mensagens_entregue_em_rollback.sql"


def _mensagem(c):
    pedido = abrir_pedido(c)
    conversa = c.contexto.conversas.abrir(pedido, c.ids["profissional"])
    return c.contexto.conversas.enviar(conversa, c.ids["profissional"], "Oi, tudo bem?")


def _ler(c, mid):
    with c.local.admin() as con:
        return con.execute(
            "select entregue_em, lida_em from public.mensagens where id = %s", (mid,)
        ).fetchone()


def test_mensagem_nasce_sem_entregue_nem_lida(cenario):
    mid = _mensagem(cenario)
    assert tuple(_ler(cenario, mid)) == (None, None)


def test_entregue_em_preenche_uma_vez_e_nao_muda(cenario):
    mid = _mensagem(cenario)
    with cenario.local.admin() as con:
        con.execute("update public.mensagens set entregue_em = now() where id = %s", (mid,))
        primeira = con.execute(
            "select entregue_em from public.mensagens where id = %s", (mid,)
        ).fetchone()[0]
        with pytest.raises(psycopg.errors.RestrictViolation):
            con.execute(
                "update public.mensagens set entregue_em = now() + interval '1 hour' where id = %s",
                (mid,),
            )
    assert _ler(cenario, mid)[0] == primeira and _ler(cenario, mid)[1] is None


def test_ler_implica_receber(cenario):
    mid = _mensagem(cenario)
    with cenario.local.admin() as con:
        con.execute("update public.mensagens set lida_em = now() where id = %s", (mid,))
    entregue, lida = _ler(cenario, mid)
    assert lida is not None and entregue == lida


def test_lida_depois_de_entregue_mantem_as_duas_datas(cenario):
    mid = _mensagem(cenario)
    with cenario.local.admin() as con:
        con.execute(
            "update public.mensagens set entregue_em = now() - interval '5 minutes' where id = %s",
            (mid,),
        )
        con.execute("update public.mensagens set lida_em = now() where id = %s", (mid,))
    entregue, lida = _ler(cenario, mid)
    assert entregue < lida


def test_resto_da_mensagem_continua_imutavel(cenario):
    mid = _mensagem(cenario)
    with cenario.local.admin() as con:
        with pytest.raises(psycopg.errors.RestrictViolation):
            con.execute("update public.mensagens set corpo = 'outra' where id = %s", (mid,))
    with cenario.local.admin() as con:
        with pytest.raises(psycopg.errors.RestrictViolation):
            con.execute("delete from public.mensagens where id = %s", (mid,))


def test_lida_nao_volta_atras(cenario):
    mid = _mensagem(cenario)
    with cenario.local.admin() as con:
        con.execute("update public.mensagens set lida_em = now() where id = %s", (mid,))
    with cenario.local.admin() as con:
        with pytest.raises(psycopg.errors.RestrictViolation):
            con.execute("update public.mensagens set lida_em = null where id = %s", (mid,))


def test_rollback_volta_ao_gatilho_antigo_sem_a_coluna(cenario):
    """Aplica o rollback DENTRO de uma transação e desfaz no fim (não estraga os outros testes)."""
    with cenario.local.admin() as con:
        with pytest.raises(_Desfazer):
            with con.transaction():
                con.execute(ROLLBACK.read_text(encoding="utf-8"))
                colunas = {
                    r[0]
                    for r in con.execute(
                        "select column_name from information_schema.columns "
                        "where table_schema = 'public' and table_name = 'mensagens'"
                    )
                }
                assert "entregue_em" not in colunas and "lida_em" in colunas
                raise _Desfazer
    with cenario.local.admin() as con:  # depois do rollback da transação, a coluna segue lá
        assert (
            con.execute(
                "select count(*) from information_schema.columns where table_name = 'mensagens' "
                "and column_name = 'entregue_em'"
            ).fetchone()[0]
            == 1
        )


class _Desfazer(Exception):
    pass
