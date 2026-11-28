"""BE-LOTE-A no Postgres LOCAL descartável: SQL novo (aviso ao autor, carteiras vencendo e data
do selo). Nunca toca no Supabase."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta

import pytest

from trato.persistencia.avaliacoes_moderacao import ModeracaoAvaliacoesPostgres
from trato.persistencia.usuarios import UsuariosPostgres

from .test_avaliacoes_moderacao_postgres import _criar_avaliacao_no_banco
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401
from .test_tratinhos_validade_postgres import conta, creditar  # noqa: F401 - fixture

pytestmark = pytest.mark.integracao


def test_aviso_ao_autor_grava_uma_vez_mesmo_em_paralelo(equipe, migrations_novas):  # noqa: F811
    c = equipe
    mod = ModeracaoAvaliacoesPostgres(c.banco)
    av = _criar_avaliacao_no_banco(c, 1, "Texto com dado pessoal.")
    agora = datetime.now(UTC)
    ocu, cod = mod.ocultar(av, "dados_pessoais", "Expõe telefone.", c.ids["med_a"], agora)
    assert cod == "ok"
    with ThreadPoolExecutor(max_workers=3) as pool:
        datas = {
            x.autor_avisado_em
            for x in pool.map(
                lambda s: mod.marcar_autor_avisado(ocu.id, agora + timedelta(seconds=s)), range(3)
            )
        }
    assert len(datas) == 1 and None not in datas


def test_carteiras_vencendo_respeita_a_janela(conta):  # noqa: F811
    repo, uid, _, agora = conta
    creditar(repo, uid, 10, agora, 5)
    assert (uid, "cliente") in repo.carteiras_vencendo(agora, agora + timedelta(days=7))
    assert (uid, "cliente") not in repo.carteiras_vencendo(agora, agora + timedelta(days=4))


def test_data_do_selo_vem_da_ultima_aprovacao(pg):  # noqa: F811
    uid = pg.ids["profissional"]
    repo = UsuariosPostgres(pg.banco)
    esperado = linhas(
        pg,
        "select max(decidida_em) from public.verificacoes "
        "where profissional_id = %s and status = 'aprovada'",
        (uid,),
    )[0][0]
    assert repo.selos_conferidos_em([uid]).get(uid) == esperado
    assert repo.selos_conferidos_em([]) == {}
