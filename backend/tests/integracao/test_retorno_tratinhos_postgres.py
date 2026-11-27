"""BE-ENCERRA-FIM no Postgres local: devolução dos Tratinhos pelo retorno APROVADO, aceita
pelo gatilho da migration 20261127092000. O prazo da 20.9 não muda."""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest

from trato.api.medidas import aplicar, restabelecer_por_retorno
from trato.api.moedas import MoedasPostgres
from trato.persistencia.medidas import Medida
from trato.persistencia.retorno_conta import RetornoContaPostgres

from .test_guarda_tratinhos_postgres import RESTAURADOS, pessoa
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)
from .test_retorno_conta_postgres import _criar_equipe_209
from .test_tratinhos_encerramento_postgres import _creditar


def cenario(c, sem_falta):
    contexto = c.pagto[1]
    analista, lider = _criar_equipe_209(c)
    usuario = pessoa(c)
    inicio = contexto.agora() - timedelta(days=95)
    _creditar(
        MoedasPostgres(c.banco),
        usuario,
        70,
        f"retorno-{uuid.uuid4()}",
        inicio - timedelta(days=10),
        expira_em=inicio + timedelta(days=10),
    )
    medida, _ = aplicar(
        contexto,
        Medida(
            usuario_id=usuario,
            tipo="encerramento",
            motivo="Encerramento administrativo para teste de retorno.",
            clausulas=("20.9",),
            inicio_em=inicio,
            efeito="Conta encerrada.",
            como_contestar="Canal oficial.",
            aplicada_por=analista,
            sem_falta=sem_falta,
        ),
    )
    return contexto, usuario, medida, lider


def aprovar(c, usuario, medida, lider, dias):
    contexto = c.pagto[1]
    retorno = RetornoContaPostgres(c.banco)
    pedido, _, codigo = retorno.abrir_retorno(
        usuario,
        "Quero voltar a usar a minha conta.",
        "app",
        medida.inicio_em + timedelta(days=dias),
    )
    assert codigo == "ok" and pedido is not None, codigo
    feito, codigo = retorno.decidir_retorno(
        pedido.id, "aprovado", lider, "Análise concluída sem risco.", False, contexto.agora()
    )
    assert codigo == "ok" and feito is not None, codigo
    return feito


@pytest.mark.parametrize("sem_falta", [True, None])
def test_retorno_aprovado_devolve_uma_vez(pg, sem_falta):  # noqa: F811
    contexto, usuario, medida, lider = cenario(pg, sem_falta)
    # Pedido no 90º dia exato: o único que a 20.9 (a partir de 90) e a guarda (até 90) aceitam.
    ret = aprovar(pg, usuario, medida, lider, 90)
    feitos = [
        restabelecer_por_retorno(contexto, ret.medida_id, ret.solicitado_em) for _ in range(2)
    ]
    assert feitos == [70, 0]
    assert linhas(pg, RESTAURADOS, (usuario,)) == [(70, "cliente")]
    assert contexto.medidas.obter(medida.id).sem_falta is True


def test_pedido_depois_do_90o_dia_nao_devolve(pg):  # noqa: F811
    contexto, usuario, medida, lider = cenario(pg, True)
    ret = aprovar(pg, usuario, medida, lider, 91)
    assert restabelecer_por_retorno(contexto, ret.medida_id, ret.solicitado_em) == 0
    assert linhas(pg, RESTAURADOS, (usuario,)) == []


def test_retorno_por_falta_nao_devolve(pg):  # noqa: F811
    contexto, usuario, medida, lider = cenario(pg, False)
    ret = aprovar(pg, usuario, medida, lider, 90)
    assert restabelecer_por_retorno(contexto, ret.medida_id, ret.solicitado_em) == 0
    assert linhas(pg, RESTAURADOS, (usuario,)) == []
