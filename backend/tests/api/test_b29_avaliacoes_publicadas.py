"""B29: só avaliação publicada aparece no perfil e conta em `etiquetas_top`."""

from __future__ import annotations

from dataclasses import replace
from datetime import timedelta

from conftest import AGORA
from test_profissional_upload import _aprovar, e2  # noqa: F401

from trato.api.repositorios_app import Avaliacao


def _av(i, etiquetas, status="publicada"):
    return Avaliacao(
        f"ped-{i}", "cliente_para_profissional", f"cli-{i}", "pro-1", 5, None,
        tuple(etiquetas), AGORA + timedelta(days=i), status=status,
    )  # fmt: skip


def test_descartada_e_em_revisao_nao_aparecem_nem_contam(e2):  # noqa: F811
    _aprovar(e2)
    av = e2.amb.contexto.avaliacoes
    av.salvar(_av(1, ["Pontual"]))
    av.salvar(_av(2, ["Pontual", "Limpo"], status="descartada"))
    av.salvar(_av(3, ["Pontual", "Limpo"], status="em_revisao"))

    corpo = e2.get("/v1/profissionais/pro-1", "t-cliente").json()
    assert len(corpo["avaliacoes"]) == 1
    assert corpo["etiquetas_top"] == [{"etiqueta": "Pontual", "total": 1}]


def test_em_revisao_volta_a_contar_quando_publicada(e2):  # noqa: F811
    _aprovar(e2)
    av = e2.amb.contexto.avaliacoes
    av.salvar(_av(1, ["Limpo"], status="em_revisao"))
    assert e2.get("/v1/profissionais/pro-1", "t-cliente").json()["etiquetas_top"] == []
    av.salvar(replace(av.obter("ped-1", "cliente_para_profissional"), status="publicada"))
    corpo = e2.get("/v1/profissionais/pro-1", "t-cliente").json()
    assert corpo["etiquetas_top"] == [{"etiqueta": "Limpo", "total": 1}]
    assert len(corpo["avaliacoes"]) == 1


def test_recebidas_da_memoria_filtra_por_status(e2):  # noqa: F811
    av = e2.amb.contexto.avaliacoes
    av.salvar(_av(1, [], status="descartada"))
    av.salvar(_av(2, []))
    assert [a.pedido_id for a in av.recebidas("pro-1")] == ["ped-2"]
