"""BE-VERSAO-CONTRATADA-236 no Postgres local: o aceite grava `regras_aplicadas`, a leitura do
contrato as traz e elas valem depois de a configuração piorar."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace

import pytest

from trato.api.admin.rotas_ausencias import _teto_retencao
from trato.api.desistencia import prazo
from trato.api.rotas_reagendamento import _antecedencia_horas

from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

PUBLICADOS = {
    "arrependimento_dias": 12,
    "ausencia_retencao_max_bps": 1500,
    "reagendamento_antecedencia_horas": 10,
}


@pytest.fixture
def publicados(pg, equipe):
    """Publica os parâmetros na versão vigente antes do aceite (só no banco descartável)."""
    from trato.persistencia.config import versao_vigente

    with pg.banco.transacao() as con:
        versao = versao_vigente(con)
    with pg.local.admin() as con:
        con.execute("set session_replication_role = replica")
        antes = con.execute(
            "select chave, valor from public.config_parametros where versao_id = %s "
            "and escopo_tipo = 'global' and chave = any(%s)",
            (versao, list(PUBLICADOS)),
        ).fetchall()
        assert not antes, antes
        for chave, valor in PUBLICADOS.items():
            con.execute(
                "insert into public.config_parametros (versao_id, escopo_tipo, chave, valor) "
                "values (%s, 'global', %s, %s)",
                (versao, chave, valor),
            )

    def retirar():
        with pg.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute(
                "delete from public.config_parametros where versao_id = %s and chave = any(%s)",
                (versao, list(PUBLICADOS)),
            )

    yield pg, retirar
    retirar()


def test_regras_do_aceite_sao_lidas_e_valem_depois_de_piorar(publicados, monkeypatch):
    c, retirar = publicados
    contexto = c.pagto[1]
    pid, _ = agendado(c)
    contrato = contexto.contratos.obter_do_pedido(pid)
    parametros = contrato.regras["parametros"]
    assert {k: parametros[k] for k in PUBLICADOS} == PUBLICADOS
    assert "adiantamento_bps" in contrato.regras
    # A configuração piora: sai o que estava publicado.
    retirar()
    original = contexto.config.carregar
    monkeypatch.setattr(
        contexto.config,
        "carregar",
        lambda: replace(original(), arrependimento_dias=7, ausencia_retencao_max_bps=3000),
    )
    pedido = contexto.pedidos.obter(pid)
    inicio, ate, _ = prazo(contexto, pedido)
    assert (ate.date() - inicio.astimezone(ate.tzinfo).date()).days == 12
    base, maximo = _teto_retencao(contexto, pedido)
    assert maximo == base * 1500 // 10_000
    assert _antecedencia_horas(contexto, pid) == 10
