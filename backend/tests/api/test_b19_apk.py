"""B19 (bugs do APK 0.1.31): G-1 garantia, IDEM-1 duplo toque, PIX-1 e TRAT-1."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.api.moedas import ConfigMoedas, MoedasEmMemoria, conceder_bonus_avaliacao
from trato.pagamentos.provedor import ErroProvedor
from trato.pedidos.estados import Estado

MSG_PIX = "Não foi possível gerar o Pix agora. Tente de novo ou pague com cartão."
MSG_CARTAO = "Não foi possível processar o pagamento agora. Tente de novo."


def _acao(amb, quem, acao, pedido="ped-1"):
    return amb.cliente.post(f"/v1/pedidos/{pedido}/acoes/{acao}", json=None, headers=cab(quem))


# --- G-1: garantia com os dias prometidos no contrato ----------------------------------------


def test_g1_garantia_usa_os_dias_do_contrato_em_categoria_sem_mapa(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    contrato = amb.contexto.contratos.obter_do_pedido("ped-1")
    amb.contexto.contratos.salvar(replace(contrato, categoria_id="sem-mapa", garantia_dias=90))

    assert _acao(amb, "t-cliente", "confirmar_conclusao").status_code == 200

    assert amb.contexto.garantias.obter_garantia("ped-1").dias == 90


def test_g1_sem_dias_no_contrato_cai_no_padrao(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)

    assert _acao(amb, "t-cliente", "confirmar_conclusao").status_code == 200

    assert amb.contexto.garantias.obter_garantia("ped-1").dias == 30


# --- IDEM-1: duplo toque devolve o mesmo sucesso ---------------------------------------------


def test_idem1_confirmar_conclusao_duas_vezes_devolve_o_mesmo_200(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)

    a = _acao(amb, "t-cliente", "confirmar_conclusao")
    b = _acao(amb, "t-cliente", "confirmar_conclusao")

    assert a.status_code == 200 and b.status_code == 200
    assert b.json() == a.json() and b.json()["estado"] == "concluido"
    eventos = amb.cliente.get("/v1/pedidos/ped-1/eventos", headers=cab("t-cliente")).json()
    assert [e["acao"] for e in eventos].count("confirmar_conclusao") == 1


def test_idem1_confirmar_conclusao_em_8_threads_so_um_registro_e_todos_200(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    codigos, barreira = [], threading.Barrier(8)

    def f():
        barreira.wait()
        codigos.append(_acao(amb, "t-cliente", "confirmar_conclusao").status_code)

    fios = [threading.Thread(target=f) for _ in range(8)]
    [t.start() for t in fios]
    [t.join() for t in fios]

    assert codigos == [200] * 8, codigos
    eventos = amb.cliente.get("/v1/pedidos/ped-1/eventos", headers=cab("t-cliente")).json()
    assert [e["acao"] for e in eventos].count("confirmar_conclusao") == 1


def _avaliar(amb, quem):
    return amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao", json={"nota_geral": 5}, headers=cab(quem)
    )


def test_idem1_avaliar_duas_vezes_cliente_e_profissional_mesmo_sucesso_um_registro(amb):
    amb.contexto.moedas = MoedasEmMemoria(
        ConfigMoedas(ativo=True, bonus_avaliacao_moedas=50, dias_liberacao_bonus=3)
    )
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)

    for quem in ("t-cliente", "t-prof"):
        a, b = _avaliar(amb, quem), _avaliar(amb, quem)
        assert a.status_code == 201, a.text
        assert b.status_code == 200, b.text
        assert b.json() == a.json(), quem
    assert len(amb.contexto.avaliacoes._itens) == 2  # um registro por lado
    pend = amb.contexto.moedas.pendentes_do_usuario(CLIENTE.id)
    assert sum(p.quantidade for p in pend) == 50  # um só bônus


# --- PIX-1: erro do provedor vira 502 claro --------------------------------------------------


def _quebrar_provedor(fake):
    def recusa(**_kw):
        raise ErroProvedor("Stripe recusou (400): The PaymentMethod provided (pix) is not allowed")

    fake.criar_cobranca = recusa


def test_pix1_pix_recusado_pelo_provedor_da_502_com_mensagem_clara(fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    _quebrar_provedor(fluxo.fake)

    r = fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix"})

    assert r.status_code == 502, r.text
    assert r.json()["detail"] == MSG_PIX
    assert "Stripe" not in r.text  # a mensagem do parceiro fica no log, não na tela


def test_pix1_cartao_recusado_pelo_provedor_da_502_com_mensagem_de_cartao(fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    _quebrar_provedor(fluxo.fake)

    r = fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "cartao"})

    assert r.status_code == 502, r.text
    assert r.json()["detail"] == MSG_CARTAO


# --- TRAT-1: bonus_disponivel sem creditar ---------------------------------------------------


def _dados(amb):
    return amb.cliente.get("/v1/pedidos/ped-1/avaliacao", headers=cab("t-cliente"))


def test_trat1_bonus_disponivel_verdadeiro_e_nao_credita(amb):
    amb.contexto.moedas = MoedasEmMemoria(
        ConfigMoedas(ativo=True, bonus_avaliacao_moedas=50, dias_liberacao_bonus=0)
    )
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)

    r = _dados(amb)

    assert r.status_code == 200, r.text
    assert r.json() == {
        "pedido_id": "ped-1",
        "ja_avaliou": False,
        "bonus_disponivel": True,
        "bonus_moedas": 50,
    }
    assert amb.contexto.moedas.saldo(CLIENTE.id, AGORA) == 0  # só leu


def test_trat1_bonus_indisponivel_quando_o_limite_do_profissional_no_mes_ja_foi_usado(amb):
    amb.contexto.moedas = MoedasEmMemoria(
        ConfigMoedas(
            ativo=True,
            bonus_avaliacao_moedas=50,
            dias_liberacao_bonus=0,
            max_bonus_por_profissional_mes=1,
        )
    )
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    # outro pedido do mesmo par no mesmo mês já rendeu o bônus
    ganhou = conceder_bonus_avaliacao(
        amb.contexto.moedas,
        cliente_id=CLIENTE.id,
        pedido_id="ped-antigo",
        agora=amb.contexto.agora() - timedelta(minutes=1),
        profissional_id=PROFISSIONAL.id,
        valor_servico_centavos=100_000,
    )
    assert ganhou == 50

    r = _dados(amb)

    assert r.status_code == 200, r.text
    assert r.json()["bonus_disponivel"] is False and r.json()["bonus_moedas"] == 0
