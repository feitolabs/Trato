"""BE-LOTE-B-BANCO no Postgres LOCAL: erros novos do banco (122500 e 122600) e preservação do
envolvido sem pedido."""

from __future__ import annotations

import pytest

from trato.persistencia.erros import ContaAnonimizada, RegistrosPreservados
from trato.persistencia.incidentes import IncidentesPostgres

from .test_pagamento_postgres import linhas, migrations_novas, pedido_aceito, pg  # noqa: F401
from .test_tratinhos_encerramento_postgres import pessoa

pytestmark = pytest.mark.integracao


def preservar(c, envolvido) -> str:
    """Incidente sem pedido, com a pessoa só como envolvida e a medida de preservação."""
    analista = pessoa(c)
    with c.local.admin() as con:
        con.execute(
            "insert into public.equipe (usuario_id, papel, ativo) values (%s, 'seguranca', true)",
            (analista,),
        )
        ((incidente,),) = con.execute(
            "insert into public.incidentes_seguranca (tipo, descricao, canal, contato, "
            "envolvido_id, aberto_em, cautela_ate) values ('outro', 'Apuração', 'painel', "
            "'sem contato', %s, now(), now() + interval '24 hours') returning id::text",
            (envolvido,),
        ).fetchall()
        con.execute(
            "insert into public.incidente_medidas (incidente_id, tipo, descricao, origem, "
            "aplicada_por) values (%s, 'preservar_registros', 'Preservar', 'analista', %s)",
            (incidente, analista),
        )
    return incidente


def test_envolvido_sem_pedido_fica_preservado_e_o_erro_vira_adiamento(pg):  # noqa: F811
    repo = IncidentesPostgres(pg.banco)
    alvo, livre = pessoa(pg), pessoa(pg)
    preservar(pg, alvo)
    assert repo.usuario_preservado(alvo) is True and repo.usuario_preservado(livre) is False
    with pytest.raises(RegistrosPreservados), pg.banco.transacao() as con:
        con.execute("select privado.anonimizar_usuario(%s)", (alvo,))
    ((status,),) = linhas(pg, "select status from public.usuarios where id = %s", (alvo,))
    assert status != "anonimizado"  # a transação inteira voltou


def test_pedido_de_conta_anonimizada_vira_erro_claro(pg):  # noqa: F811
    pedido_aceito(pg)  # um pedido para copiar
    uid = pessoa(pg)
    with pg.local.admin() as con:
        con.execute("update public.usuarios set status = 'anonimizado' where id = %s", (uid,))
    with pytest.raises(ContaAnonimizada), pg.banco.transacao() as con:
        con.execute(
            "insert into public.pedidos (cliente_id, categoria_id, cidade_id, titulo, "
            "descricao) select %s, categoria_id, cidade_id, titulo, descricao "
            "from public.pedidos limit 1",
            (uid,),
        )


def test_sem_a_funcao_vale_a_regra_das_partes(pg):  # noqa: F811
    renomear = "alter function public.{}(uuid) rename to {}"
    with pg.local.admin() as con:
        con.execute(renomear.format("usuario_com_registros_preservados", "preservados_escondida"))
    try:
        assert IncidentesPostgres(pg.banco).usuario_preservado(pessoa(pg)) is None
    finally:
        with pg.local.admin() as con:
            con.execute(
                renomear.format("preservados_escondida", "usuario_com_registros_preservados")
            )
