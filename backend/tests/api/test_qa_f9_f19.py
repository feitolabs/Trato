# ruff: noqa
"""QA2: conferencia das entregas F9-F19/B6-B10 e idempotencia pela API HTTP (em memoria)."""

from __future__ import annotations

import hashlib
import hmac
import json
import threading
import zlib
from datetime import timedelta

import pytest
from conftest import AGORA, PROFISSIONAL, SEGREDO_WEBHOOK, cab

from trato.api.moedas import ConfigMoedas, MoedasEmMemoria
from trato.financeiro import extrato_profissional as ext
from trato.financeiro.ledger import CUSTODIA, Livro, registrar_cobranca, repartir_custodia
from trato.pedidos.estados import Estado as E


# ---------- PDF ----------
def _texto_do_pdf(b: bytes) -> str:
    """Junta o texto do PDF (descomprime streams se houver)."""
    saida = [b.decode("latin-1")]
    resto = b
    while b"stream" in resto:
        _, _, resto = resto.partition(b"stream")
        corpo, _, resto = resto.partition(b"endstream")
        corpo = corpo.lstrip(b"\r\n")
        try:
            saida.append(zlib.decompress(corpo).decode("latin-1"))
        except Exception:
            pass
    return "\n".join(saida)


def _extrato(taxa=0):
    livro = Livro()
    registrar_cobranca(livro, "ped-1", 100_000, "cob", AGORA)
    repartir_custodia(livro, "ped-1", PROFISSIONAL.id, taxa, "rep", AGORA)
    return ext.montar(livro.lancamentos, PROFISSIONAL.id, AGORA - timedelta(days=1), AGORA + timedelta(days=1))


def test_pdf_sem_taxa_e_sem_dados_do_cliente():
    e = _extrato(0)
    rot = {"ped-1": (7, "Pintar sala")}
    b = ext.pdf(e, "Maria Prof", rot, AGORA, documento="123.456.789-09", categorias={"ped-1": "Pintura"})
    t = _texto_do_pdf(b)
    assert b.startswith(b"%PDF")
    assert "Sem taxa" in t
    assert "Taxa do Trato" in t
    assert "123.456.789-09" in t  # CPF do proprio profissional
    for proibido in ("cli-1", "telefone", "Telefone", "Rua ", "Endere"):
        assert proibido not in t, proibido


def test_pdf_sem_documento_nao_inventa_cpf():
    t = _texto_do_pdf(ext.pdf(_extrato(0), "Maria Prof", {}, AGORA))
    assert "CPF" not in t


@pytest.mark.parametrize("doc,esperado", [("12345678909", "CPF 123.456.789-09"), ("1234567", None), ("", None), (None, None), ("12345678000199", "CNPJ 12.345.678/0001-99")])
def test_formatar_documento_estranho_nao_quebra(doc, esperado):
    assert ext.formatar_documento(doc) == esperado


# ---------- IDEMPOTENCIA PELA API ----------
def _assinar(corpo: bytes) -> str:
    t = int(AGORA.timestamp())
    v1 = hmac.new(SEGREDO_WEBHOOK.encode(), f"{t}.".encode() + corpo, hashlib.sha256).hexdigest()
    return f"t={t},v1={v1}"


def _evento(id_="evt_1", valor=100_000) -> bytes:
    obj = {"id": "pi_1", "amount": valor, "metadata": {"pedido_id": "ped-1"}}
    return json.dumps({"id": id_, "type": "payment_intent.succeeded", "data": {"object": obj}}).encode()


def _enviar(amb, corpo):
    return amb.cliente.post("/v1/webhooks/stripe", content=corpo, headers={"Stripe-Signature": _assinar(corpo)})


@pytest.mark.parametrize("vezes", [2, 5, 10])
def test_webhook_de_pagamento_repetido_lanca_uma_vez(amb, vezes):
    amb.semear_pedido(E.ORCAMENTO_ACEITO)
    corpo = _evento()
    codigos = [_enviar(amb, corpo).status_code for _ in range(vezes)]
    assert set(codigos) == {200}
    assert amb.contexto.ledger.saldo_da_conta(CUSTODIA, "ped-1") == 100_000


def test_webhook_de_pagamento_duas_threads_simultaneas(amb):
    amb.semear_pedido(E.ORCAMENTO_ACEITO)
    corpo = _evento()
    res = []
    barreira = threading.Barrier(6)

    def tarefa():
        barreira.wait()
        res.append(_enviar(amb, corpo).status_code)

    ts = [threading.Thread(target=tarefa) for _ in range(6)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert all(c == 200 for c in res), res
    assert amb.contexto.ledger.saldo_da_conta(CUSTODIA, "ped-1") == 100_000


def test_webhook_valor_diferente_do_contrato_nao_credita_a_mais(amb):
    amb.semear_pedido(E.ORCAMENTO_ACEITO)
    _enviar(amb, _evento("evt_x", valor=999_999_999))
    assert amb.contexto.ledger.saldo_da_conta(CUSTODIA, "ped-1") <= 100_000


def test_webhook_sem_assinatura_ou_assinatura_errada_e_recusado(amb):
    amb.semear_pedido(E.ORCAMENTO_ACEITO)
    corpo = _evento()
    assert amb.cliente.post("/v1/webhooks/stripe", content=corpo).status_code in (400, 401, 403, 422)
    r = amb.cliente.post("/v1/webhooks/stripe", content=corpo, headers={"Stripe-Signature": "t=1,v1=00"})
    assert r.status_code in (400, 401, 403)
    assert amb.contexto.ledger.saldo_da_conta(CUSTODIA, "ped-1") == 0


def _ligar_moedas(amb):
    amb.contexto.moedas = MoedasEmMemoria(
        ConfigMoedas(ativo=True, dias_liberacao_bonus=0, bonus_avaliacao_moedas=50, valor_moeda_centavos=2)
    )


@pytest.mark.parametrize("vezes", [2, 10])
def test_avaliacao_repetida_nao_da_bonus_de_tratinhos_duplo(amb, vezes):
    _ligar_moedas(amb)
    amb.semear_pedido(E.CONCLUIDO, concluido_em=AGORA)
    cod = [amb.cliente.post("/v1/pedidos/ped-1/avaliacao", json={"nota_geral": 5}, headers=cab("t-cliente")).status_code for _ in range(vezes)]
    assert cod[0] == 201
    assert set(cod[1:]) <= {200, 201, 409}
    assert amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).json()["saldo"] == 50


def test_avaliacao_simultanea_nao_da_bonus_duplo(amb):
    _ligar_moedas(amb)
    amb.semear_pedido(E.CONCLUIDO, concluido_em=AGORA)
    b = threading.Barrier(6)

    def t():
        b.wait()
        amb.cliente.post("/v1/pedidos/ped-1/avaliacao", json={"nota_geral": 5}, headers=cab("t-cliente"))

    ts = [threading.Thread(target=t) for _ in range(6)]
    [x.start() for x in ts]
    [x.join() for x in ts]
    assert amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).json()["saldo"] == 50


@pytest.mark.parametrize("nota", [0, 6, -1, 5.5, "5", None, True])
def test_avaliacao_nota_invalida_da_422(amb, nota):
    amb.semear_pedido(E.CONCLUIDO, concluido_em=AGORA)
    r = amb.cliente.post("/v1/pedidos/ped-1/avaliacao", json={"nota_geral": nota}, headers=cab("t-cliente"))
    assert r.status_code == 422, f"{nota!r}: {r.status_code}"


def test_avaliar_pedido_nao_concluido_e_recusado(amb):
    amb.semear_pedido(E.AGENDADO)
    r = amb.cliente.post("/v1/pedidos/ped-1/avaliacao", json={"nota_geral": 5}, headers=cab("t-cliente"))
    assert r.status_code in (404, 409, 422)


def test_a_caminho_10x_so_avisa_uma_vez(amb):
    from trato.notificacoes import ligar_ao_contexto
    from trato.notificacoes.canais import Canais, CanalApp
    from trato.notificacoes.config import ConfigNotificacoes
    from trato.notificacoes.repositorio import RepositorioEmMemoria
    from trato.notificacoes.servico import ServicoNotificacoes
    from trato.pedidos.estados import Janela

    amb.semear_pedido(E.AGENDADO, janela=Janela(AGORA + timedelta(hours=1), AGORA + timedelta(hours=3)))
    n = ServicoNotificacoes(RepositorioEmMemoria(), Canais(CanalApp()), ConfigNotificacoes(_env_file=None), amb.relogio)
    ligar_ao_contexto(amb.cliente.app, amb.contexto, n)
    env = [amb.cliente.post("/v1/profissional/pedidos/ped-1/a-caminho", headers=cab("t-prof")).json()["enviado"] for _ in range(10)]
    assert env == [True] + [False] * 9
    assert len([x for x in n.repo.listar("cli-1", False, 50) if x.tipo == "agenda.a_caminho"]) == 1


def test_favorito_repetido_10x_e_remover_inexistente(amb):
    for _ in range(10):
        assert amb.cliente.put("/v1/me/favoritos/pro-1", headers=cab("t-cliente")).status_code in (200, 204, 404, 503)
    r = amb.cliente.delete("/v1/me/favoritos/nao-existe", headers=cab("t-cliente"))
    assert r.status_code in (200, 204, 404, 503)

