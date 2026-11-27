"""TERMOS-ET5: exclusividade paga pelo cliente (13.6, 13.8, I.4). Memória, com a mesma semântica
das funções SQL."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import timedelta

import pytest
from conftest import AGORA, CLIENTE, OUTRO_PROFISSIONAL, PROFISSIONAL, cab
from test_exclusividade import _orcar, _pedido
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401 - fixtures
from test_termos_m2_dinheiro import agendador

from trato.api.moedas import ConfigMoedas, LancamentoMoeda, MoedasEmMemoria, ReservaMoeda
from trato.pedidos.estados import Estado

PRO, OUTRO = PROFISSIONAL.id, OUTRO_PROFISSIONAL.id
URL = "/v1/pedidos/ped-1/exclusividade-cliente"


def ligar(amb, *creditos):
    """`creditos`: (moedas, dias até vencer). Padrão: 300 por 90 dias."""
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True))
    for n, (valor, dias) in enumerate(creditos or ((300, 90),)):
        amb.contexto.moedas.lancar(
            LancamentoMoeda(
                CLIENTE.id,
                "bonus_avaliacao",
                valor,
                f"c{n}",
                AGORA,
                expira_em=AGORA + timedelta(days=dias),
            )
        )


def pedir(amb, chave="chave-0001", quem="t-cliente", **escolha):
    corpo = {"chave_idempotencia": chave} | (escolha or {"profissional_id": PRO})
    return amb.cliente.post(URL, json=corpo, headers=cab(quem))


def ver(amb):
    return amb.cliente.get(URL, headers=cab("t-cliente")).json()


def saldo(amb):
    return amb.contexto.exclusividades.saldo_livre(CLIENTE.id, amb.relogio.agora)


def estado(amb):
    return amb.contexto.pedidos.obter("ped-1").estado


def desistir(amb, eid, quem="t-prof"):
    return amb.cliente.post(f"/v1/profissional/exclusividades/{eid}/desistir", headers=cab(quem))


def falha(amb, eid, quem="t-mediador", motivo="O aplicativo ficou fora do ar."):
    url = f"/v1/admin/exclusividades/{eid}/falha-trato"
    return amb.cliente.post(url, json={"motivo": motivo}, headers=cab(quem))


def test_pede_debita_reserva_e_esconde_dos_outros(amb):
    ligar(amb)
    _pedido(amb)
    r = pedir(amb)
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "ativa" and r.json()["moedas"] == 100
    assert r.json()["expira_em"].startswith("2026-10-31T12:00:00")
    assert saldo(amb) == 200 and estado(amb) is Estado.RESERVADO
    assert pedir(amb).status_code == 200 and saldo(amb) == 200
    assert pedir(amb, "chave-0002").json()["codigo"] == "pedido_indisponivel"
    assert _orcar(amb, "t-outro-prof").status_code in (404, 409)
    assert amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-outro-prof")).status_code == 404
    assert _orcar(amb).status_code == 201
    dados = ver(amb)
    assert dados["disponivel"] and dados["saldo_livre"] == 200
    assert dados["custo_moedas"] == 100 and dados["duracao_horas"] == 48
    assert [c["moedas"] for c in dados["creditos"]] == [200]


def test_por_orcamento_e_orcamento_de_outro_pedido(amb):
    ligar(amb)
    _pedido(amb)
    assert _orcar(amb).status_code == 201
    orcamento = next(
        o for o in amb.contexto.orcamentos.do_pedido("ped-1") if o.profissional_id == PRO
    )
    assert pedir(amb, orcamento_id="nao-existe").json()["codigo"] == "orcamento_invalido"
    r = pedir(amb, orcamento_id=orcamento.id)
    assert r.status_code == 201 and r.json()["profissional_id"] == PRO


@pytest.mark.parametrize(
    "preparo,codigo",
    [
        ("pouco", "saldo_insuficiente"),
        ("vencido", "saldo_insuficiente"),
        ("preso", "saldo_insuficiente"),
        ("cliente_medida", "conta_com_restricao"),
        ("pro_medida", "profissional_indisponivel"),
        ("pro_inexistente", "profissional_indisponivel"),
    ],
)
def test_recusas_nao_cobram(amb, preparo, codigo):
    ligar(amb, (99, 90)) if preparo == "pouco" else ligar(amb, (300, 1))
    _pedido(amb)
    escolha = {"profissional_id": PRO}
    if preparo == "vencido":
        amb.relogio.avancar(days=2)
    if preparo == "preso":
        amb.contexto.moedas._reservas["cob-x"] = ReservaMoeda(
            "cob-x", CLIENTE.id, AGORA.date(), AGORA.date(), 250, 250,
            expira_em=AGORA + timedelta(days=1),
        )  # fmt: skip
    if preparo == "cliente_medida":
        amb.contexto.medidas.impedidas.add(CLIENTE.id)
    if preparo == "pro_medida":
        amb.contexto.medidas.impedidas.add(PRO)
    if preparo == "pro_inexistente":
        escolha = {"profissional_id": CLIENTE.id}
    antes = saldo(amb)
    r = pedir(amb, **escolha)
    assert r.json()["codigo"] == codigo, r.text
    assert saldo(amb) == antes and estado(amb) is Estado.ABERTO


def test_so_o_cliente_do_pedido(amb):
    ligar(amb)
    _pedido(amb)
    assert pedir(amb, quem="t-outro-cliente").status_code == 404
    assert pedir(amb, quem="t-prof").status_code == 404


def test_oito_pedidos_juntos_cobram_uma_vez(amb):
    ligar(amb, (100, 90))
    _pedido(amb)
    codigos = []
    threads = [
        threading.Thread(target=lambda n=n: codigos.append(pedir(amb, f"chave-{n:04}").status_code))
        for n in range(8)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(codigos).count(201) == 1 and saldo(amb) == 0


@pytest.mark.parametrize("quando,validade", [(1, "original"), (40, "nova")])
def test_desistencia_devolve_com_a_validade(amb, quando, validade):
    ligar(amb, (60, 30), (240, 90))
    _pedido(amb)
    eid = pedir(amb).json()["id"]  # gasta 60 (30 dias) + 40 (90 dias)
    if validade == "nova":  # o prazo de 48 h é esticado para o crédito antigo vencer antes
        item = amb.contexto.exclusividades.obter(eid)
        amb.contexto.exclusividades._mudar(item, expira_em=AGORA + timedelta(days=100))
    amb.relogio.avancar(days=quando)
    r = desistir(amb, eid)
    assert r.status_code == 200, r.text
    assert r.json() == {"resultado": "ok", "moedas_devolvidas": 100}
    assert desistir(amb, eid).json()["resultado"] == "ja_devolvida"
    assert saldo(amb) == 300 and estado(amb) is Estado.ABERTO
    estornos = sorted(
        (i.quantidade, i.expira_em)
        for i in amb.contexto.moedas.lancamentos_da_carteira(CLIENTE.id)
        if i.tipo == "exclusividade_estorno"
    )
    sessenta = (
        AGORA + timedelta(days=30)
        if validade == "original"
        else amb.relogio.agora + timedelta(days=30)
    )
    assert estornos == [(40, AGORA + timedelta(days=90)), (60, sessenta)]


def test_so_o_profissional_escolhido_desiste(amb):
    ligar(amb)
    _pedido(amb)
    eid = pedir(amb).json()["id"]
    assert desistir(amb, eid, "t-outro-prof").status_code == 404
    amb.relogio.avancar(hours=48)
    assert desistir(amb, eid).json()["codigo"] == "prazo_vencido"
    assert saldo(amb) == 200 and estado(amb) is Estado.ABERTO


@pytest.mark.parametrize("quem", ["t-financeiro", "t-cliente", "t-prof"])
def test_falha_do_trato_exige_permissao(amb, quem):
    ligar(amb)
    _pedido(amb)
    eid = pedir(amb).json()["id"]
    assert falha(amb, eid, quem).status_code == 403
    assert saldo(amb) == 200


def test_falha_do_trato_devolve_mesmo_depois_do_prazo(amb):
    ligar(amb)
    _pedido(amb)
    eid = pedir(amb).json()["id"]
    assert falha(amb, eid, motivo="curto").status_code == 422
    amb.relogio.avancar(hours=50)
    amb.contexto.exclusividades.expirar_cliente(amb.relogio.agora)
    for _ in range(2):
        r = falha(amb, eid)
        assert r.status_code == 200, r.text
    assert saldo(amb) == 300


# --- contratação, cancelamento e prazo -----------------------------------------------------------


def _com_pedido_pago(f: Fluxo, escolhido=PRO):
    ligar(f.amb)
    pid = f.chamar("POST", "/v1/pedidos", "t-cliente").json()["id"]
    f.ctx.exclusividades.vincular(f.ctx)
    item = f.ctx.exclusividades.solicitar_cliente(
        CLIENTE.id, pid, escolhido, None, "chave-fluxo", AGORA, False, lambda _: True
    )
    return pid, item.exclusividade_id


@pytest.mark.parametrize("escolhido,status", [(PRO, "concluida"), (OUTRO, "cancelada")])
def test_so_o_pagamento_confirmado_encerra_sem_devolver(fluxo, escolhido, status):  # noqa: F811
    from trato.api.repositorios import Orcamento

    pid, eid = _com_pedido_pago(fluxo, escolhido)
    fluxo.ctx.orcamentos.adicionar(Orcamento("orc-e2e", pid, PRO, 100_000, "pintura"))
    r = fluxo.acao(pid, "aceitar_orcamento", "t-cliente", {"orcamento_id": "orc-e2e"})
    assert r.status_code == 200, r.text
    assert fluxo.ctx.exclusividades.obter(eid).status == "ativa"  # aceitar não é contratar
    fluxo.pagar(pid)
    assert fluxo.ctx.exclusividades.obter(eid).status == status
    assert saldo(fluxo.amb) == 200


def test_cancelar_o_pedido_encerra_sem_devolver(fluxo):  # noqa: F811
    pid, eid = _com_pedido_pago(fluxo)
    r = fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"})
    assert r.status_code == 200, r.text
    assert fluxo.ctx.exclusividades.obter(eid).status == "cancelada"
    assert saldo(fluxo.amb) == 200


def test_prazo_expira_reabre_e_a_validade_do_pedido_conta_da_reabertura(fluxo):  # noqa: F811
    pid, eid = _com_pedido_pago(fluxo)
    prazo = fluxo.ctx.config.carregar().prazos_pedido.receber_orcamentos
    rotina = agendador(fluxo)
    fluxo.amb.relogio.agora = AGORA + timedelta(hours=48)
    assert rotina._executor.expirar_exclusividades(fluxo.amb.relogio.agora) == 1
    assert rotina._executor.expirar_exclusividades(fluxo.amb.relogio.agora) == 0
    assert fluxo.ctx.exclusividades.obter(eid).status == "expirada_sem_contratacao"
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.ABERTO and saldo(fluxo.amb) == 200
    fluxo.amb.relogio.agora = AGORA + prazo + timedelta(hours=1)  # venceria contando da abertura
    rotina.rodar_uma_vez()
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.ABERTO
    fluxo.amb.relogio.agora = AGORA + timedelta(hours=48) + prazo + timedelta(minutes=1)
    rotina.rodar_uma_vez()
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CANCELADO


def test_a_forma_paga_pelo_profissional_nao_e_mais_oferecida(amb):
    ligar(amb)
    _pedido(amb)
    r = amb.cliente.post(
        "/v1/profissional/exclusividades",
        json={"pedido_id": "ped-1", "chave_idempotencia": "k1"},
        headers=cab("t-prof"),
    )
    assert r.status_code == 409 and r.json()["codigo"] == "exclusividade_descontinuada"
    config = amb.contexto.config
    config._config = replace(config.carregar(), exclusividade_profissional_ofertada=True)
    assert config.carregar().exclusividade_profissional_ofertada
