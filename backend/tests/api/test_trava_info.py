"""BE-TRAVA-INFO: o painel sabe quem tem trava por fraude em vigor e o prazo máximo. Só
leitura. Memória."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

from admin_ambiente import adm  # noqa: F401 - fixture
from conftest import cab

from trato.api.admin.papeis import MATRIZ, PapelEquipe, Permissao
from trato.api.medidas import aplicar
from trato.persistencia.medidas import Medida

BASE = "/v1/admin"


def travar(amb, usuario_id, fraude=True, dias=5) -> None:
    agora = amb.contexto.agora()
    aplicar(
        amb.contexto,
        Medida(
            usuario_id=usuario_id,
            tipo="trava_saque",
            motivo=f"Apuração {fraude} {dias}.",
            clausulas=("20.6",),
            inicio_em=agora,
            fim_em=agora + timedelta(days=dias),
            efeito="Segue a cláusula 20.6.",
            como_contestar="Pelo atendimento.",
            aplicada_por="eq-seguranca",
            motivo_fraude=fraude,
            limite_retencao_centavos=100 if fraude else None,
        ),
    )


def test_busca_e_detalhe_marcam_so_a_trava_por_fraude_vigente(adm):
    def marcas(quem="t-seguranca"):
        r = adm.cliente.get(f"{BASE}/usuarios", headers=cab(quem))
        assert r.status_code == 200, r.text
        return {u["id"]: u["trava_fraude_vigente"] for u in r.json()["itens"]}

    ids = list(marcas())
    assert ids and set(marcas().values()) == {False}
    alvo = ids[0]
    travar(adm, alvo, fraude=False)
    assert marcas()[alvo] is False
    travar(adm, alvo)
    assert marcas() == {i: i == alvo for i in ids}
    r = adm.cliente.get(f"{BASE}/usuarios/{alvo}", headers=cab("t-seguranca"))
    assert r.json()["trava_fraude_vigente"] is True, r.text
    adm.relogio.avancar(days=5)
    assert marcas()[alvo] is False


def test_quem_nao_reativa_nem_ve_risco_recebe_nulo(adm):
    veem = {Permissao.USUARIOS_STATUS, Permissao.MEDIDAS_APLICAR, Permissao.RISCO_VER}
    sem = [
        p for p in PapelEquipe if Permissao.USUARIOS_BUSCAR in MATRIZ[p] and not veem & MATRIZ[p]
    ]
    for papel in sem:
        r = adm.cliente.get(f"{BASE}/usuarios", headers=cab(f"t-{papel.value}"))
        if r.status_code == 200:
            assert {u["trava_fraude_vigente"] for u in r.json()["itens"]} <= {None}, papel


def test_prazo_maximo_para_o_painel(adm):
    r = adm.cliente.get(f"{BASE}/medidas/trava-fraude", headers=cab("t-seguranca"))
    assert r.status_code == 200 and r.json() == {"prazo_maximo_dias": 30}, r.text
