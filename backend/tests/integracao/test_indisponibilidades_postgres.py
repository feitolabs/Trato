"""BE-INDISPONIBILIDADE-22.3-A no Postgres local (migration 20261127205000): sem sobreposição
em corrida, encerramento único e histórico preservado."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

from trato.persistencia.indisponibilidades import Janela, JanelaSobreposta

from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    migrations_novas,
    pg,
)

H = timedelta(hours=1)


def test_abre_uma_em_corrida_encerra_uma_vez_e_filtra(pg):  # noqa: F811
    repo = pg.pagto[1].indisponibilidades
    assert repo.disponivel()
    # Datas antigas: o banco é compartilhado e não apaga; assim não cobre prazo de outro teste.
    agora = datetime(2001, 1, 10, tzinfo=UTC)
    janela = Janela("app", agora - 2 * H, "Aplicativo fora do ar.", "operador-teste")
    saidas, recusas = [], []

    def abrir(minutos: int) -> None:
        try:
            saidas.append(
                repo.criar(
                    Janela(
                        "app",
                        janela.inicio_em + timedelta(minutes=minutos),
                        janela.motivo,
                        janela.criada_por,
                    )
                )
            )
        except JanelaSobreposta:
            recusas.append(minutos)

    fios = [threading.Thread(target=abrir, args=(m,)) for m in range(5)]
    for fio in fios:
        fio.start()
    for fio in fios:
        fio.join()
    assert (len(saidas), len(recusas)) == (1, 4)
    aberta = saidas[0][0]
    assert [j.id for j in repo.listar(abertas=True)] == [aberta.id]
    assert repo.encerrar(aberta.id, agora, "operador-teste").fim_em == agora
    assert repo.encerrar(aberta.id, agora, "operador-teste") is None
    assert repo.listar(abertas=True) == []
    assert repo.listar(desde=agora) == []
    assert [j.id for j in repo.listar(desde=agora - H)] == [aberta.id]
