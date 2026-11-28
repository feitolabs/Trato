"""BE-M6-PARIDADE: a conta do backend é a da função SQL `moedas_restauracao_devida` (133600),
nos casos fechados e em históricos sorteados. Postgres LOCAL descartável."""

from __future__ import annotations

import random
import sys
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from trato.api.medidas import aplicar
from trato.api.moedas import LancamentoMoeda, MoedasPostgres
from trato.persistencia.medidas import Medida

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))
from casos_restauracao import CASOS, com_sufixo  # noqa: E402

from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401
from .test_tratinhos_encerramento_postgres import pessoa

pytestmark = pytest.mark.integracao
D = timedelta(days=1)
DEVIDA = "select public.moedas_restauracao_devida(%s, 'cliente', %s)"


def encerrar(c, usuario, inicio):
    medida, _ = aplicar(
        c.pagto[1],
        Medida(
            usuario_id=usuario,
            tipo="encerramento",
            motivo="Encerramento para a paridade.",
            clausulas=("20.8",),
            inicio_em=inicio,
            efeito="Segue a cláusula 20.6.",
            como_contestar="Pelo atendimento.",
            aplicada_por=c.ids["equipe1"],
            sem_falta=False,  # com falta começa na data dada (sem falta espera o aviso, 20.8)
        ),
    )
    return medida


def montar(c, itens, agora):
    moedas = MoedasPostgres(c.banco)
    uid = pessoa(c)
    sufixo = uuid.uuid4().hex[:6]
    for q, tipo, criada, vence, chave in itens:
        assert moedas.lancar(
            LancamentoMoeda(
                uid,
                tipo,
                q,
                com_sufixo(chave, sufixo),
                agora + criada * D,
                expira_em=None if vence is None else agora + vence * D,
            )
        )
    inicio = agora - 40 * D
    return moedas, uid, encerrar(c, uid, inicio), inicio


def conferir(c, moedas, uid, medida, inicio, quando):
    sql = linhas(c, DEVIDA, (medida.id, quando))[0][0]
    python = moedas.restauracao_devida(medida.id, uid, "cliente", inicio, quando)
    assert python == sql, (uid, quando, python, sql)
    return python


def test_casos_fechados(pg, equipe):  # noqa: F811
    agora = datetime.now(UTC)
    for nome, (itens, devido) in CASOS.items():
        moedas, uid, medida, inicio = montar(pg, itens, agora)
        assert conferir(pg, moedas, uid, medida, inicio, agora) == devido, nome


def historico(sorteio, n):
    itens, usos, t = [], [], -100
    for k in range(sorteio.randint(2, 12)):
        t = min(t + sorteio.choice([0, 1, 7, 20]), -1)
        r = sorteio.random()
        if r < 0.4 or (not usos and r > 0.7):
            vence = sorteio.choice([None, -45, -35, -20, -5, 30])
            itens.append((sorteio.choice([5, 20, 50]), "ajuste", t, vence, f"L{n}-{k}"))
        elif r <= 0.7:
            excl = sorteio.random() < 0.4
            ref, q = f"{n}-{k}", sorteio.choice([5, 20, 40])
            tipo = "exclusividade_uso" if excl else "uso"
            prefixo = "exclusividade-uso:" if excl else "uso:"
            itens.append((-q, tipo, t, None, prefixo + ref))
            usos.append((ref, q, excl))
        else:
            ref, q, excl = sorteio.choice(usos)
            tipo = "exclusividade_estorno" if excl else "estorno"
            volta = sorteio.choice([q, q, max(q // 2, 1)])
            chave = f"exclusividade-estorno:{ref}:{k}" if excl else f"estorno-uso:{ref}:{k}:0"
            itens.append((volta, tipo, t, sorteio.choice([-45, -35, -20, -5, 30]), chave))
    return itens


def test_historicos_sorteados(pg, equipe):  # noqa: F811
    sorteio = random.Random(11)  # noqa: S311 - dados de teste reproduzíveis
    agora = datetime.now(UTC)
    positivos = 0
    for n in range(60):
        moedas, uid, medida, inicio = montar(pg, historico(sorteio, n), agora)
        for dia in (-40, -20, -4, 60):
            positivos += conferir(pg, moedas, uid, medida, inicio, agora + dia * D) > 0
    assert positivos > 10
