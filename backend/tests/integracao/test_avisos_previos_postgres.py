"""BE-AVISOS-30 no Postgres local: a lista de destinatários dos avisos prévios e o envio
repetido ao mesmo tempo, sem duplicar o aviso."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

from trato.notificacoes.eventos import Evento
from trato.notificacoes.postgres import NotificacoesServicoPostgres

from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

MUDAR = "update public.usuarios set status = %s where id = %s"


def test_destinatarios_paginados_sem_anonimizado(pg):  # noqa: F811
    c = pg
    usuarios = c.pagto[1].usuarios
    cliente, outro = c.ids["cliente"], c.ids["cliente2"]
    todos = usuarios.ids_para_aviso(None, 1000)
    assert cliente in todos and outro in todos and todos == sorted(todos)
    paginado, ultimo = [], None
    while lote := usuarios.ids_para_aviso(ultimo, 2):
        paginado += lote
        ultimo = lote[-1]
    assert paginado == todos
    with c.local.admin() as con:
        con.execute(MUDAR, ("anonimizado", outro))
    try:
        assert outro not in usuarios.ids_para_aviso(None, 1000)
    finally:
        with c.local.admin() as con:
            con.execute(MUDAR, ("ativo", outro))


def test_envio_simultaneo_grava_um_aviso_so(pg):  # noqa: F811
    c = pg
    contexto = c.pagto[1]
    repo = NotificacoesServicoPostgres(contexto.usuarios._banco)
    tipo = Evento.AVISO_MUDANCA_TERMOS.value

    def criar(_):
        return repo.criar(
            c.ids["cliente"],
            tipo,
            "app",
            "Título",
            "Corpo",
            {},
            f"{tipo}:previo:teste:2027-01-31",
            contexto.agora(),
            True,
        )[1]

    with ThreadPoolExecutor(4) as grupo:
        criados = list(grupo.map(criar, range(4)))
    assert sorted(criados) == [False, False, False, True]
