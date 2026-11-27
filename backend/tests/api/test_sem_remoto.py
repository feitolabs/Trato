"""BE-REMOTO (Termos 3.7): série de origem remota não gera nem retoma visita, as partes são
avisadas uma vez e o cadastro do profissional ignora `atende_remoto`."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace

import pytest
from conftest import AGORA, cab
from test_profissional_upload import e2  # noqa: F401
from test_recorrencias import URL, D, H, _acao, _ativa, _executor, _propor, _serie, rec  # noqa: F401

from trato.pedidos.estados import Estado


def tornar_remoto(amb, pid="ped-1") -> None:
    amb.contexto.pedidos.salvar(replace(amb.contexto.pedidos.obter(pid), remoto=True))


def avisos_de_serie(repo, quem) -> list:
    return [n for n in repo.listar(quem, False, 20) if "3.7" in n.corpo]


def test_proposta_de_origem_remota_e_recusada(rec):
    tornar_remoto(rec)
    r = _propor(rec)
    assert r.status_code == 422 and "3.7" in r.json()["detail"], r.text


def test_proposta_antiga_nao_e_aceita(rec):
    rid = _propor(rec).json()["id"]
    tornar_remoto(rec)
    r = _acao(rec, rid, "aceitar", "t-prof")
    assert r.status_code == 409 and "3.7" in r.json()["detail"], r.text
    assert _serie(rec, rid).status == "proposta"


def test_serie_remota_pausa_avisa_uma_vez_e_a_rotina_segue(rec):
    executor, avisos = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    tornar_remoto(rec)
    for passou in (0 * H, 1 * H, 8 * D):
        assert executor.gerar_visitas_recorrentes(AGORA + passou) == 0
    assert _serie(rec, rid).status == "pausada"
    assert rec.contexto.recorrencias.visitas(rid) == []
    for quem in ("cli-1", "pro-1"):
        assert len(avisos_de_serie(avisos, quem)) == 1, quem
    r = rec.cliente.post(f"{URL}/{rid}/retomar", headers=cab("t-cliente"))
    assert r.status_code == 409 and "3.7" in r.json()["detail"], r.text
    assert _serie(rec, rid).status == "pausada"


def test_serie_presencial_segue_gerando(rec):
    executor, _ = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    assert executor.gerar_visitas_recorrentes(AGORA) == 1
    (visita,) = rec.contexto.recorrencias.visitas(rid)
    pedido = rec.contexto.pedidos.obter(visita.pedido_id)
    assert pedido.estado is Estado.ABERTO and not pedido.remoto


def cadastro(**extra):
    return {
        "categorias": ["cat-pintura"],
        "regioes": [{"cidade_id": "cid-bh"}],
        **extra,
    }


@pytest.mark.parametrize(
    "extra", [{"atende_remoto": True}, {"atende_presencial": False, "atende_remoto": True}]
)
def test_cadastro_e_edicao_ignoram_atende_remoto(e2, extra):
    r = e2.post("/v1/profissional/cadastro", "t-cliente", cadastro(**extra))
    assert r.status_code == 201, r.text
    assert (r.json()["atende_presencial"], r.json()["atende_remoto"]) == (True, False)
    r = e2.amb.cliente.patch("/v1/profissional/perfil", json=extra, headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    assert (r.json()["atende_presencial"], r.json()["atende_remoto"]) == (True, False)


def test_quem_ja_atendia_remoto_continua_e_pode_desligar(e2):
    assert e2.post("/v1/profissional/cadastro", "t-cliente", cadastro()).status_code == 201
    repo = e2.modulo.repo
    (usuario,) = [e2.amb.cliente.get("/v1/profissional/perfil", headers=cab("t-cliente")).json()]
    perfil = repo.obter(usuario["usuario_id"])
    repo.salvar(replace(perfil, atende_remoto=True))

    def editar(corpo):
        r = e2.amb.cliente.patch("/v1/profissional/perfil", json=corpo, headers=cab("t-cliente"))
        assert r.status_code == 200, r.text
        return r.json()["atende_remoto"]

    assert editar({"bio": "Pintor."}) is True
    assert editar({"atende_remoto": True}) is True
    assert editar({"atende_remoto": False}) is False
    assert editar({"atende_remoto": True}) is False
