"""BE-GUARDA-TRATINHOS no Postgres local (migration 20261127092000): marca `sem_falta`,
devolução única na reversão, recusa do banco sem quebrar a transação e banco sem a migration."""

from __future__ import annotations

import threading
import uuid
from datetime import timedelta

from trato.api.medidas import aplicar, restabelecer_por_retorno, reverter
from trato.api.moedas import MoedasPostgres, restaurar_tratinhos
from trato.persistencia.medidas import Medida

from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)
from .test_tratinhos_encerramento_postgres import _creditar, pessoa

# O que o backend procura para saber se a migration existe, com o gatilho que usa a coluna.
SEM_A_MIGRATION = (
    "alter table public.medidas_conta disable trigger medidas_conta_sem_falta_trg",
    "alter table public.medidas_conta rename column sem_falta to sem_falta_guardada",
    "alter function public.moedas_restauracao_devida(uuid, text, timestamptz) "
    "rename to moedas_restauracao_guardada",
)
COM_A_MIGRATION = (
    "alter function public.moedas_restauracao_guardada(uuid, text, timestamptz) "
    "rename to moedas_restauracao_devida",
    "alter table public.medidas_conta rename column sem_falta_guardada to sem_falta",
    "alter table public.medidas_conta enable trigger medidas_conta_sem_falta_trg",
)
RESTAURADOS = (
    "select quantidade, carteira from public.moedas_lancamentos "
    "where usuario_id = %s and tipo = 'restauracao'"
)


def encerrar(c, usuario, sem_falta, motivo):
    contexto = c.pagto[1]
    inicio = contexto.agora() - timedelta(days=40)
    moedas = MoedasPostgres(c.banco)
    _creditar(
        moedas,
        usuario,
        70,
        f"guarda-{uuid.uuid4()}",
        inicio - timedelta(days=10),
        expira_em=inicio + timedelta(days=10),
    )
    medida, _ = aplicar(
        contexto,
        Medida(
            usuario_id=usuario,
            tipo="encerramento",
            motivo=motivo,
            clausulas=("20.8",),
            inicio_em=inicio,
            efeito="Segue a cláusula 20.6.",
            como_contestar="Pelo atendimento.",
            aplicada_por=c.ids["equipe1"],
            sem_falta=sem_falta,
        ),
    )
    return medida


def test_banco_sem_a_migration_grava_e_reverte_sem_devolver(pg, equipe):  # noqa: F811
    """Esconde a coluna e a função em vez de rodar o rollback, que só passa sem restauração no
    livro (e então este teste dependeria da ordem dos módulos)."""
    with pg.local.admin() as con, con.transaction():
        for comando in SEM_A_MIGRATION:
            con.execute(comando)
    try:
        contexto = pg.pagto[1]
        usuario = pessoa(pg)
        medida = encerrar(pg, usuario, True, "Encerramento antes da migration.")
        assert contexto.medidas.obter(medida.id).sem_falta is None
        assert restabelecer_por_retorno(contexto, medida.id, medida.inicio_em) == 0
        assert reverter(contexto, medida, pg.ids["equipe1"])
        assert linhas(pg, RESTAURADOS, (usuario,)) == []
    finally:
        with pg.local.admin() as con, con.transaction():
            for comando in COM_A_MIGRATION:
                con.execute(comando)


def test_marca_recusa_do_banco_e_devolucao_unica(pg, equipe):  # noqa: F811
    contexto = pg.pagto[1]
    usuario = pessoa(pg)
    medida = encerrar(pg, usuario, False, "Encerramento por falta do usuário.")
    assert contexto.medidas.obter(medida.id).sem_falta is False
    moedas = MoedasPostgres(pg.banco)
    # Sem reversão nem retorno aprovado o banco recusa, e a transação de fora continua de pé.
    with contexto.transacao():
        assert (
            restaurar_tratinhos(moedas, medida.id, usuario, medida.inicio_em, contexto.agora()) == 0
        )
        assert contexto.medidas.obter(medida.id) is not None
    assert reverter(contexto, medida, pg.ids["equipe1"])
    erros: list[BaseException] = []

    def repetir():
        try:
            restaurar_tratinhos(moedas, medida.id, usuario, medida.inicio_em, contexto.agora())
        except BaseException as erro:  # noqa: BLE001 - conferido abaixo
            erros.append(erro)

    tarefas = [threading.Thread(target=repetir) for _ in range(4)]
    for t in tarefas:
        t.start()
    for t in tarefas:
        t.join()
    assert not erros, erros
    assert linhas(pg, RESTAURADOS, (usuario,)) == [(70, "cliente")]
    assert moedas.saldo(usuario, contexto.agora()) >= 70


def test_sem_resposta_e_lida_como_nao_informada(pg, equipe):  # noqa: F811
    contexto = pg.pagto[1]
    usuario = pessoa(pg)
    medida = encerrar(pg, usuario, None, "Encerramento sem resposta no painel.")
    assert contexto.medidas.obter(medida.id).sem_falta is None
    assert contexto.medidas.mudar(medida.id, {"sem_falta": True})
    assert contexto.medidas.obter(medida.id).sem_falta is True
    assert reverter(contexto, medida, pg.ids["equipe1"])
