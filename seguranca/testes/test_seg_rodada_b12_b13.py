"""Seguranca: lacunas apontadas na revisao dos commits B12/B13 (so o que o QA nao cobre).

SEG-1 (M1): limite_por_usuario estourando no webhook com desconto ja dado.
SEG-2: tetos da nota de material no backend (app limita 9.999 un. e R$ 1.000.000,00).
SEG-3: repeticao da cobranca (timeout no app) com 'usar_moedas' diferente.
SEG-4: duplo envio da nota de material (mesmo corpo, 2 threads).
"""

from __future__ import annotations

import sys
import threading
from pathlib import Path

import pytest

import importlib.util

_API = Path(__file__).resolve().parents[2] / "backend" / "tests" / "api"
for _p in (str(_API), str(_API.parent)):
    if _p not in sys.path:
        sys.path.insert(0, _p)
# 'conftest' ja aponta para backend/tests/conftest.py; carrega o do tests/api sob o mesmo nome.
_spec = importlib.util.spec_from_file_location("conftest", _API / "conftest.py")
_mod = importlib.util.module_from_spec(_spec)
sys.modules["conftest"] = _mod
_spec.loader.exec_module(_mod)
amb, cab = _mod.amb, _mod.cab
from test_fluxo_pagamento_e2e import fluxo  # noqa: E402,F401

from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Estado


def _cupom_unico():
    return {
        "codigo": "UNICO1", "tipo": "valor_fixo", "valor": 2000, "ativo": True,
        "limite_usos": 10, "limite_por_usuario": 1, "usos_atuais": 0,
    }  # fmt: skip


def _cenario_seg1(fluxo):
    """Corrida na CRIACAO: duas cobrancas com o mesmo cupom (limite 1/usuario) antes de pagar."""
    cupom = _cupom_unico()
    fluxo.ctx.extras["cupons"] = {"UNICO1": cupom}
    p1, p2 = fluxo.aceitar(), fluxo.aceitar()
    corpo = {"meio": "pix", "parcelas": 1, "cupom": "UNICO1"}
    r1 = fluxo.chamar("POST", f"/v1/contratos/{p1}/cobranca", "t-cliente", corpo)
    r2 = fluxo.chamar("POST", f"/v1/contratos/{p2}/cobranca", "t-cliente", corpo)
    assert r1.status_code == 201, r1.text
    # Documenta o comportamento: ambos passam na criacao (uso so conta no webhook).
    assert r2.status_code == 201, r2.text
    for r in (r1, r2):
        fluxo.fake.marcar_paga(r.json()["cobranca_id"])
        assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, r.json()["cobranca_id"]).status_code == 200
    # Com o limite 1/usuario, so UM pagamento pode levar desconto.
    assert cupom["usos_atuais"] == 1
    valores = sorted(r.json()["valor_centavos"] for r in (r1, r2))
    assert valores[0] != valores[1], f"os 2 pedidos levaram o desconto (cupom 1/usuario usado 2x): {valores}"


def test_seg1_limite_por_usuario_nao_pode_ser_furado_por_pedidos_simultaneos(fluxo):  # noqa: F811
    _cenario_seg1(fluxo)


def _contrato_em_andamento(amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO)


def _nota(qtd, unit):
    return {
        "foto_storage_path": "pedidos/ped-1/nota.jpg",
        "itens": [{"descricao": "Fio", "quantidade": qtd, "valor_unitario_centavos": unit}],
    }


def _enviar_nota(amb, corpo):
    return amb.cliente.post("/v1/contratos/ped-1/notas-material", headers=cab("t-prof"), json=corpo)


def test_seg2_nota_normal_e_aceita(amb):
    _contrato_em_andamento(amb)
    r = _enviar_nota(amb, _nota("2", 1500))
    assert r.status_code == 201, r.text
    assert r.json()["total_centavos"] == 3000


def test_seg2_nota_acima_de_1_milhao_deveria_dar_422(amb):
    _contrato_em_andamento(amb)
    r = _enviar_nota(amb, _nota("1", 100_000_001))  # R$ 1.000.000,01
    assert r.status_code == 422, (r.status_code, r.text[:120])


def test_seg2_quantidade_acima_de_9999_deveria_dar_422(amb):
    _contrato_em_andamento(amb)
    r = _enviar_nota(amb, _nota("10000", 1))
    assert r.status_code == 422, (r.status_code, r.text[:120])


def test_seg2_quantidade_negativa_zero_e_total_gigante_sao_barrados(amb):
    _contrato_em_andamento(amb)
    for qtd, unit in (("0", 100), ("-1", 100), ("99999999.99", 10**10)):
        r = _enviar_nota(amb, _nota(qtd, unit))
        assert r.status_code == 422, (qtd, unit, r.status_code, r.text[:100])
    assert amb.contexto.notas_material.do_pedido("ped-1") == [] or not list(
        amb.contexto.notas_material.do_pedido("ped-1")
    )


def test_seg2_cliente_e_outro_profissional_nao_enviam_nota(amb):
    _contrato_em_andamento(amb)
    for tok in ("t-cliente", "t-outro-prof", "t-outro-cliente"):
        r = amb.cliente.post(
            "/v1/contratos/ped-1/notas-material", headers=cab(tok), json=_nota("1", 100)
        )
        assert r.status_code in (403, 404), (tok, r.status_code)


def test_seg3_repetir_cobranca_com_moedas_diferentes_nao_gera_segunda_cobranca(fluxo):  # noqa: F811
    """O app usa 'cobranca-<pedido>-<meio>[-moedas]' como chave; o servidor NAO le o header, mas
    `servico.cobrar` devolve a cobranca pendente. Confere: sem 2a cobranca (sem cobrar 2x)."""
    p = fluxo.aceitar()
    r1 = fluxo.chamar("POST", f"/v1/contratos/{p}/cobranca", "t-cliente", {"meio": "pix"})
    assert r1.status_code == 201, r1.text
    r2 = fluxo.chamar(
        "POST", f"/v1/contratos/{p}/cobranca", "t-cliente", {"meio": "pix", "usar_moedas": True}
    )
    assert r2.status_code == 201, r2.text
    assert r2.json()["cobranca_id"] == r1.json()["cobranca_id"]  # sem cobranca em dobro
    # BAIXA: a pendente volta como esta; 'usar_moedas' pedido depois e ignorado (sem prejuizo).
    assert r2.json()["valor_centavos"] == r1.json()["valor_centavos"]


def test_seg4_duplo_envio_da_nota_cria_no_maximo_uma(amb):
    _contrato_em_andamento(amb)
    res, barreira = [], threading.Barrier(6)

    def f():
        barreira.wait()
        res.append(_enviar_nota(amb, _nota("1", 1000)).status_code)

    ts = [threading.Thread(target=f) for _ in range(6)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    notas = list(amb.contexto.notas_material.do_pedido("ped-1"))
    assert all(c in (201, 409) for c in res), res
    assert len(notas) <= 1, f"{len(notas)} notas iguais gravadas por duplo envio: {res}"
