"""TERMOS-M1 no Postgres LOCAL descartável: saldo por crédito, devolução proporcional e
concorrência. Nunca toca no Supabase."""

from __future__ import annotations

import threading
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from trato.api.moedas import (
    LancamentoMoeda,
    MoedasPostgres,
    debitar_uso_moedas,
    devolver_uso_moedas,
)

pytestmark = pytest.mark.integracao

DIA = timedelta(days=1)


@pytest.fixture
def conta(cenario):
    """(repositório, usuário novo, pedido, instante base)."""
    uid = str(uuid.uuid4())
    with cenario.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (uid,))
        con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, "Moedas"))
    return MoedasPostgres(cenario.banco), uid, str(uuid.uuid4()), datetime.now(UTC)


def creditar(repo, uid, quantidade, agora, dias):
    assert repo.lancar(
        LancamentoMoeda(
            uid,
            "bonus_avaliacao",
            quantidade,
            uuid.uuid4().hex,
            agora,
            expira_em=agora + dias * DIA,
        )
    )


def test_gasto_nao_e_descontado_de_novo_no_vencimento(conta):
    repo, uid, pedido, agora = conta
    creditar(repo, uid, 100, agora, 10)
    creditar(repo, uid, 40, agora, 100)
    debitar_uso_moedas(
        repo, usuario_id=uid, cobranca_id=uid, pedido_id=pedido, moedas=100, agora=agora + DIA
    )
    assert repo.saldo(uid, agora + 5 * DIA) == 40
    assert repo.saldo(uid, agora + 11 * DIA) == 40


def test_devolucoes_concorrentes_nao_passam_do_gasto(conta):
    repo, uid, pedido, agora = conta
    creditar(repo, uid, 60, agora, 10)
    creditar(repo, uid, 40, agora, 100)
    cobranca = f"cob-{uid}"
    debitar_uso_moedas(
        repo, usuario_id=uid, cobranca_id=cobranca, pedido_id=pedido, moedas=100, agora=agora + DIA
    )
    partes = [100, 300, 500, 700, 900, 1_000, 1_000, 200]
    barreira, erros = threading.Barrier(len(partes)), []

    def rodar(parte):
        barreira.wait()
        try:
            devolver_uso_moedas(
                repo,
                usuario_id=uid,
                cobranca_id=cobranca,
                pedido_id=pedido,
                moedas=100,
                agora=agora + 20 * DIA,
                devolvido_centavos=parte,
                base_centavos=1_000,
            )
        except Exception as erro:  # noqa: BLE001 - o teste confere abaixo
            erros.append(erro)

    fios = [threading.Thread(target=rodar, args=(p,)) for p in partes]
    [f.start() for f in fios]
    [f.join(30) for f in fios]

    assert erros == [] and not any(f.is_alive() for f in fios)
    estornos = [i for i in repo.lancamentos_da_carteira(uid) if i.tipo == "estorno"]
    assert sum(i.quantidade for i in estornos) == 100
    # o crédito de 10 dias venceu (vira 30 dias novos); o de 100 mantém a validade original
    por_prazo: dict[int, int] = {}
    for i in estornos:
        dias = round((i.expira_em - agora) / DIA)
        por_prazo[dias] = por_prazo.get(dias, 0) + i.quantidade
    assert por_prazo == {50: 60, 100: 40}
    assert repo.saldo(uid, agora + 49 * DIA) == 100
