"""BE-CONFIG-PRAZOS: o prazo de resposta ao titular (14.9) e o da revisão de avaliação (12.7)
vêm do valor publicado; sem ele (ou fora da faixa), vale o padrão."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import pytest
from admin_ambiente import adm, cab  # noqa: F401
from test_avaliacoes_moderacao import semear_avaliacoes

from trato.api.rotas_avaliacoes_moderacao import _prazo_dias_uteis
from trato.api.rotas_lgpd_titular import _prazo_dias

LGPD = "lgpd_pedido_resposta_dias"
REVISAO = "avaliacao_revisao_resposta_dias_uteis"


@pytest.mark.parametrize("publicado,esperado", [(None, 15), (7, 7), (1, 1), (0, 15), (16, 15)])
def test_prazo_do_titular(adm, publicado, esperado):
    if publicado is not None:
        adm.contexto.config.parametros[LGPD] = publicado
    assert _prazo_dias(adm.contexto) == esperado


@pytest.mark.parametrize("publicado,esperado", [(None, 5), (2, 2), (0, 5), (31, 5)])
def test_prazo_da_revisao(adm, publicado, esperado):
    if publicado is not None:
        adm.contexto.config.parametros[REVISAO] = publicado
    assert _prazo_dias_uteis(adm.contexto) == esperado


def _dias_ate(item: dict) -> int:
    from datetime import datetime

    from trato.financeiro.periodo import BRASILIA

    inicio, fim = (
        datetime.fromisoformat(item[c]).astimezone(BRASILIA).date()
        for c in ("aberto_em" if "aberto_em" in item else "aberta_em", "responder_ate")
    )
    return (fim - inicio).days


def test_rotas_usam_o_valor_publicado(adm):
    def titular(tipo):
        r = adm.cliente.post(
            "/v1/me/lgpd/pedidos",
            json={"tipo": tipo, "descricao": "Quero os dados da minha conta."},
            headers=cab("t-cliente"),
        )
        assert r.status_code == 201, r.text
        return _dias_ate(r.json())

    assert titular("acesso") == 15
    adm.contexto.config.parametros[LGPD] = 4
    assert titular("correcao") == 4

    _, avaliacao = semear_avaliacoes(adm)
    adm.contexto.config.parametros[REVISAO] = 1
    r = adm.cliente.post(
        f"/v1/avaliacoes/{avaliacao}/revisoes",
        json={"justificativa": "O comentário contém ofensas pessoais previstas na 12.6."},
        headers=cab("t-prof"),
    )
    assert r.status_code == 201, r.text
    assert 1 <= _dias_ate(r.json()) <= 4  # um dia útil, com fim de semana no meio
