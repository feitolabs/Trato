"""TERMOS-BE-126 no Postgres local: triggers de `avaliacao_ocultacoes` e `avaliacao_revisoes`
(migration 20261125225600), recálculo da nota pública, idempotência e regra 20.5."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from trato.api.repositorios_app import Avaliacao
from trato.persistencia.avaliacoes_moderacao import ModeracaoAvaliacoesPostgres
from trato.persistencia.dinheiro import AvaliacoesPostgres

from .test_ausencia_reembolso_postgres import pago_e_agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401

pytestmark = pytest.mark.integracao


def _sem_avaliacoes_anteriores(c, profissional: str) -> None:
    """O banco é dividido entre os módulos e este teste confere a média EXATA do profissional:
    tira do caminho as avaliações que outros testes deixaram para ele (só no banco local)."""
    alvo = "select id from public.avaliacoes where avaliado_id = %s"
    with c.local.admin() as con, con.transaction():
        con.execute("set local session_replication_role = replica")
        for tabela in ("avaliacao_revisoes", "avaliacao_ocultacoes"):
            con.execute(
                f"delete from public.{tabela} where avaliacao_id in ({alvo})",  # noqa: S608
                (profissional,),
            )
        con.execute("delete from public.avaliacoes where avaliado_id = %s", (profissional,))
        con.execute("select public.recalcular_perfil_profissional(%s)", (profissional,))


@pytest.fixture
def profissional_sem_avaliacoes(equipe):  # noqa: F811
    """Limpa antes (o que outros deixaram) e depois (o que este teste cria), nas duas ordens."""
    c = equipe
    _sem_avaliacoes_anteriores(c, c.ids["profissional"])
    yield
    _sem_avaliacoes_anteriores(c, c.ids["profissional"])


def _criar_avaliacao_no_banco(c, nota: int, comentario: str) -> str:
    pid, _, _ = pago_e_agendado(c)
    avs = AvaliacoesPostgres(c.banco)
    avs.salvar(
        Avaliacao(
            pedido_id=pid,
            direcao="cliente_para_profissional",
            avaliador_id=c.ids["cliente"],
            avaliado_id=c.ids["profissional"],
            nota_geral=nota,
            nota_decimal=float(nota),
            comentario=comentario,
            etiquetas=(),
            criada_em=datetime.now(UTC),
        )
    )
    av = avs.obter(pid, "cliente_para_profissional")
    assert av is not None and av.id
    return av.id


def test_ocultar_reverter_e_revisao_no_postgres_real(
    equipe,  # noqa: F811
    migrations_novas,  # noqa: F811
    profissional_sem_avaliacoes,  # noqa: F811
):
    _ = migrations_novas
    c = equipe
    mod = ModeracaoAvaliacoesPostgres(c.banco)
    avs = AvaliacoesPostgres(c.banco)
    assert mod.disponivel()

    av_id = _criar_avaliacao_no_banco(c, 1, "Ofensa pessoal grave.")
    assert avs.media_recebida(c.ids["profissional"]) == 1.0
    assert len(avs.recebidas(c.ids["profissional"])) == 1

    agora = datetime.now(UTC)
    mediador_id = c.ids["med_a"]
    lider_id = c.ids["adm_a"]

    # Profissional (avaliado) abre pedido de revisão -> protocolo REV-... e idempotência
    rev1, nova1, cod1 = mod.abrir_revisao(
        avaliacao_id=av_id,
        tipo="revisao",
        ocultacao_id=None,
        solicitante_id=c.ids["profissional"],
        justificativa="Comentário ofensivo conforme cláusula 12.6.",
        anexos=(),
        canal="app",
        agora=agora,
        responder_ate=agora + timedelta(days=5),
    )
    assert nova1 and cod1 == "ok" and rev1 is not None and rev1.protocolo.startswith("REV-")

    rev2, nova2, cod2 = mod.abrir_revisao(
        avaliacao_id=av_id,
        tipo="revisao",
        ocultacao_id=None,
        solicitante_id=c.ids["profissional"],
        justificativa="Tentativa duplicada.",
        anexos=(),
        canal="app",
        agora=agora,
        responder_ate=agora + timedelta(days=5),
    )
    assert not nova2 and cod2 == "ja_aberta" and rev2 is not None and rev2.id == rev1.id

    # Analista coloca em_analise e decide aceitando + oculta avaliação
    rev_ana, cod_ana = mod.iniciar_analise(rev1.id, mediador_id)
    assert cod_ana == "ok" and rev_ana is not None and rev_ana.status == "em_analise"

    rev_dec, cod_dec = mod.decidir_revisao(
        rev1.id, "aceita", mediador_id, "Ofensa confirmada na revisão.", agora
    )
    assert cod_dec == "ok" and rev_dec is not None and rev_dec.status == "aceita"

    ocu, cod_ocu = mod.ocultar(
        av_id, "ofensa_ou_ilegal", "Ofensa confirmada na revisão.", mediador_id, agora
    )
    assert cod_ocu == "ok" and ocu is not None and ocu.status_anterior == "publicada"

    # Trigger do banco mudou avaliacoes.status para 'descartada' e excluiu da nota pública
    assert avs.media_recebida(c.ids["profissional"]) is None
    assert avs.recebidas(c.ids["profissional"]) == []
    assert linhas(c, "select status from public.avaliacoes where id = %s", (av_id,)) == [
        ("descartada",)
    ]

    # Reverter ocultação por outro analista restaura status 'publicada' e a nota
    rev_ocu, cod_rev = mod.reverter_ocultacao(av_id, lider_id, agora + timedelta(seconds=1))
    assert cod_rev == "ok" and rev_ocu is not None and rev_ocu.revertida_por == lider_id
    assert avs.media_recebida(c.ids["profissional"]) == 1.0
    assert len(avs.recebidas(c.ids["profissional"])) == 1
