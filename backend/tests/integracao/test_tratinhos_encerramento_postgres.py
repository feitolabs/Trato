"""TERMOS-BE-1310 no Postgres local: preview, lançamento imutável 'ajuste', idempotência e
concorrência na tabela real `public.moedas_lancamentos`."""

from __future__ import annotations

import threading
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from trato.api.moedas import (
    CARTEIRA_CLIENTE,
    CARTEIRA_PROFISSIONAL,
    LancamentoMoeda,
    MoedasPostgres,
    saldo_total_disponivel,
    zerar_tratinhos_encerramento_voluntario,
)

from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401

pytestmark = pytest.mark.integracao


def pessoa(c) -> str:
    """Conta só de um teste: o livro é imutável e o banco é dividido entre os módulos."""
    uid = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (uid,))
        con.execute("insert into public.usuarios (id, nome) values (%s, 'Tratinhos')", (uid,))
    return uid


def _creditar(
    moedas: MoedasPostgres,
    uid: str,
    qtd: int,
    chave: str,
    agora: datetime,
    *,
    carteira: str = CARTEIRA_CLIENTE,
    expira_em: datetime | None = None,
) -> None:
    tipo = "bonus_avaliacao" if carteira == CARTEIRA_CLIENTE else "bonus_avaliacao_profissional"
    assert moedas.lancar(
        LancamentoMoeda(
            usuario_id=uid,
            tipo=tipo,
            quantidade=qtd,
            chave_idempotencia=chave,
            criada_em=agora,
            expira_em=expira_em,
            carteira=carteira,
        )
    )


def test_encerramento_voluntario_zera_tratinhos_no_postgres_sem_migration_nova(
    cenario,
    migrations_novas,  # noqa: F811
):
    _ = migrations_novas
    c = cenario
    moedas = MoedasPostgres(c.banco)
    uid = pessoa(c)
    agora = datetime.now(UTC)

    _creditar(
        moedas,
        uid,
        120,
        f"c-valido-{uuid.uuid4()}",
        agora,
        expira_em=agora + timedelta(days=60),
    )
    _creditar(
        moedas,
        uid,
        30,
        f"c-vencido-{uuid.uuid4()}",
        agora - timedelta(days=10),
        expira_em=agora - timedelta(days=1),
    )
    _creditar(
        moedas,
        uid,
        80,
        f"p-valido-{uuid.uuid4()}",
        agora,
        carteira=CARTEIRA_PROFISSIONAL,
        expira_em=agora + timedelta(days=60),
    )

    assert saldo_total_disponivel(moedas, uid, agora) == 200

    pedido_id = str(uuid.uuid4())
    zerado = zerar_tratinhos_encerramento_voluntario(moedas, uid, pedido_id, agora)
    assert zerado == 200
    assert saldo_total_disponivel(moedas, uid, agora) == 0

    assert zerar_tratinhos_encerramento_voluntario(moedas, uid, pedido_id, agora) == 0

    ajustes = linhas(
        c,
        "select carteira, tipo, quantidade from public.moedas_lancamentos "
        "where usuario_id = %s and tipo = 'ajuste' order by carteira",
        (uid,),
    )
    assert [tuple(r) for r in ajustes] == [
        ("cliente", "ajuste", -120),
        ("profissional", "ajuste", -80),
    ]


def test_concorrencia_e_saldo_zero_no_postgres(cenario, migrations_novas):  # noqa: F811
    _ = migrations_novas
    c = cenario
    moedas = MoedasPostgres(c.banco)
    uid = pessoa(c)
    agora = datetime.now(UTC)

    assert zerar_tratinhos_encerramento_voluntario(moedas, uid, str(uuid.uuid4()), agora) == 0
    assert linhas(c, "select id from public.moedas_lancamentos where usuario_id = %s", (uid,)) == []

    _creditar(
        moedas,
        uid,
        100,
        f"c-conc-{uuid.uuid4()}",
        agora,
        expira_em=agora + timedelta(days=30),
    )
    resultados: list[int] = []
    barreira = threading.Barrier(4)
    mesmo_pedido = str(uuid.uuid4())

    def rodar(i: int) -> None:
        barreira.wait()
        pid = mesmo_pedido if i < 2 else str(uuid.uuid4())
        resultados.append(zerar_tratinhos_encerramento_voluntario(moedas, uid, pid, agora))

    threads = [threading.Thread(target=rodar, args=(i,)) for i in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert sum(resultados) == 100
    assert saldo_total_disponivel(moedas, uid, agora) == 0
    ajustes = linhas(
        c,
        "select quantidade from public.moedas_lancamentos "
        "where usuario_id = %s and tipo = 'ajuste'",
        (uid,),
    )
    assert [r[0] for r in ajustes] == [-100]


def test_a4_falha_no_meio_desfaz_o_que_ja_zerou(cenario, migrations_novas, monkeypatch):  # noqa: F811
    """Falha na 2ª carteira, dentro da transação da exclusão: a 1ª também volta."""
    _ = migrations_novas
    moedas = MoedasPostgres(cenario.banco)
    uid = pessoa(cenario)
    agora = datetime.now(UTC)
    _creditar(moedas, uid, 50, f"a4-{uuid.uuid4()}", agora, expira_em=agora + timedelta(days=30))
    original = moedas.saldo

    def saldo(usuario, quando, carteira=CARTEIRA_CLIENTE):
        if carteira == CARTEIRA_PROFISSIONAL:
            raise RuntimeError("caiu")
        return original(usuario, quando, carteira)

    monkeypatch.setattr(moedas, "saldo", saldo)
    with pytest.raises(RuntimeError), cenario.banco.transacao():
        zerar_tratinhos_encerramento_voluntario(moedas, uid, str(uuid.uuid4()), agora)
    assert original(uid, agora) == 50
