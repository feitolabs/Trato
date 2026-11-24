"""B42: gatilho de indicação mais firme (contraparte, dinheiro pago, corrida) e reajuste/visitas."""

from __future__ import annotations

import threading
import time
from contextlib import nullcontext
from datetime import timedelta
from types import SimpleNamespace

import pytest
from conftest import AGORA, cab

from trato.agendador.executor import ExecutorContexto
from trato.api.auth import PapelUsuario
from trato.api.conta import DadosPessoais
from trato.api.indicacoes import ConfigIndicacao, acionar_gatilho
from trato.api.moedas import ConfigMoedas, MoedasEmMemoria
from trato.api.repositorios import Contrato
from trato.api.repositorios_app import PerfilDetalhe
from trato.pedidos.estados import Estado

H = timedelta(hours=1)
D = timedelta(days=1)
NOMES = (
    ("cli-1", "João Pedro Silva", PapelUsuario.CLIENTE),
    ("cli-2", "Maria Oliveira Lima", PapelUsuario.CLIENTE),
    ("pro-1", "Carlos Eduardo Souza", PapelUsuario.PROFISSIONAL),
    ("pro-2", "Ana Beatriz Costa", PapelUsuario.PROFISSIONAL),
)
TOKENS = {
    "cli-1": "t-cliente",
    "cli-2": "t-outro-cliente",
    "pro-1": "t-prof",
    "pro-2": "t-outro-prof",
}


@pytest.fixture
def b(amb):
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True))
    for uid, nome, papel in NOMES:
        amb.contexto.usuarios.adicionar(PerfilDetalhe(uid, nome, papel))
    return amb


def _codigo(amb, uid):
    return amb.cliente.get("/v1/indicacoes/meu-codigo", headers=cab(TOKENS[uid])).json()["codigo"]


def _aplicar(amb, uid, codigo):
    return amb.cliente.post(
        "/v1/indicacoes/aplicar", json={"codigo": codigo}, headers=cab(TOKENS[uid])
    )


def _concluir(amb, contrato=100_000, pago=100_000):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.contexto.contratos.salvar(Contrato("ped-1", "orc-1", "pro-1", contrato, "pintura"))
    amb.semear_dinheiro(pago, taxa=pago // 10)
    r = amb.cliente.post("/v1/pedidos/ped-1/acoes/confirmar_conclusao", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text


def _indicacao(amb, uid="cli-1"):
    return amb.contexto.indicacoes.do_indicado(uid)


def _dados(amb, uid, email=None, telefone=None):
    amb.contexto.conta._dados[uid] = DadosPessoais("Nome", email, None, telefone, None)


# --- 1. contraparte do pedido gatilho -----------------------------------------------------------


def test_servico_com_o_proprio_indicador_nao_conta(b):
    assert _aplicar(b, "cli-1", _codigo(b, "pro-1")).status_code == 201  # pro-1 indica cli-1
    _concluir(b)  # e o profissional do pedido é o próprio pro-1
    i = _indicacao(b)
    assert i.status == "bloqueado_fraude" and i.motivo_bloqueio == "contraparte_e_o_indicador"
    assert (i.bonus_indicador_tratinhos, i.bonus_indicado_tratinhos) == (0, 0)
    assert i.pedido_gatilho_id is None
    executor = ExecutorContexto(b.contexto)
    assert executor.liberar_indicacoes(AGORA + 8 * D) == 0
    assert b.contexto.moedas.saldo("cli-1", AGORA + 8 * D) == 0


def test_cliente_que_contrata_o_proprio_indicador_profissional_tambem_nao_conta(b):
    # pro-1 (profissional do pedido) foi indicado por cli-2?  Não pode (cliente não indica
    # profissional); o caso espelhado é pro-1 indicado por pro-2 e o pedido ser com pro-2 como cliente.
    assert _aplicar(b, "pro-1", _codigo(b, "pro-2")).status_code == 201
    b.semear_pedido(Estado.EM_CONFIRMACAO, cliente_id="pro-2")
    b.semear_dinheiro(100_000, taxa=10_000)
    pedido = b.contexto.pedidos.obter("ped-1")
    assert acionar_gatilho(b.contexto, pedido, AGORA) == []
    assert _indicacao(b, "pro-1").motivo_bloqueio == "contraparte_e_o_indicador"


@pytest.mark.parametrize(
    ("indicador", "contraparte", "motivo"),
    [
        (("a.b+x@gmail.com", None), ("ab@GMAIL.com", None), "contraparte_mesmo_email"),
        ((None, "+55 (11) 91234-5678"), (None, "11 91234-5678"), "contraparte_mesmo_telefone"),
    ],
)
def test_contraparte_com_mesmo_contato_do_indicador_bloqueia(b, indicador, contraparte, motivo):
    _dados(b, "pro-2", *indicador)  # indicador
    _dados(b, "pro-1", *contraparte)  # profissional do pedido, outra conta da mesma pessoa
    assert _aplicar(b, "cli-1", _codigo(b, "pro-2")).status_code == 201
    _concluir(b)
    assert _indicacao(b).status == "bloqueado_fraude"
    assert _indicacao(b).motivo_bloqueio == motivo


def test_bloqueio_da_contraparte_pode_ser_desligado_pela_config(b):
    b.contexto.indicacoes.salvar_config(ConfigIndicacao(bloquear_contraparte_indicador=False))
    assert _aplicar(b, "cli-1", _codigo(b, "pro-1")).status_code == 201
    _concluir(b)
    assert _indicacao(b).status == "aguardando_liberacao"


# --- 2. dinheiro pago de fato -----------------------------------------------------------------


def test_gatilho_exige_o_minimo_pago_em_dinheiro_e_nao_o_valor_do_contrato(b):
    assert _aplicar(b, "cli-1", _codigo(b, "pro-2")).status_code == 201
    _concluir(b, contrato=100_000, pago=5_999)  # contrato alto, pagou pouco
    assert _indicacao(b).status == "cadastrado"


def test_pagou_o_minimo_com_contrato_menor_arma(b):
    assert _aplicar(b, "cli-1", _codigo(b, "pro-2")).status_code == 201
    _concluir(b, contrato=5_000, pago=6_000)
    assert _indicacao(b).status == "aguardando_liberacao"


# --- 5. corrida no limite mensal --------------------------------------------------------------


@pytest.mark.parametrize(("com_trava", "esperado"), [(True, [0, 300]), (False, [300, 300])])
def test_dois_gatilhos_ao_mesmo_tempo_nao_passam_do_limite_mensal(
    b, monkeypatch, com_trava, esperado
):
    repo = b.contexto.indicacoes
    for n in range(2):  # limite do cliente é 3: já há 2 recompensadas neste mês
        antiga = repo.criar(
            "cli-2", f"antigo-{n}", f"ANTIGO{n:03d}", "cliente_cliente", 300, 300, AGORA
        )
        assert repo.armar(antiga.id, f"ped-a{n}", 300, AGORA + 7 * D)
    for n in range(2):
        repo.criar("cli-2", f"novo-{n}", f"NOVO{n:04d}", "cliente_cliente", 300, 300, AGORA)
    b.contexto.ledger.saldos_pedido = lambda *_a, **_k: SimpleNamespace(cliente_pagou=10_000)
    original = repo.recompensadas_no_mes

    def lenta(*args, **kwargs):  # abre a janela da corrida: conta, dorme, só depois arma
        valor = original(*args, **kwargs)
        time.sleep(0.15)
        return valor

    monkeypatch.setattr(repo, "recompensadas_no_mes", lenta)
    if not com_trava:  # prova de que o teste enxerga a corrida: sem a trava os dois levam 300
        monkeypatch.setattr(repo, "trava_do_indicador", lambda _id: nullcontext())
    resultados = []

    def gatilho(n):
        pedido = SimpleNamespace(id=f"ped-n{n}", cliente_id=f"novo-{n}", profissional_id="pro-9")
        resultados.extend(acionar_gatilho(b.contexto, pedido, AGORA))

    fios = [threading.Thread(target=gatilho, args=(n,)) for n in range(2)]
    for fio in fios:
        fio.start()
    for fio in fios:
        fio.join(10)
    assert len(resultados) == 2  # as duas indicações armam...
    # ...e com a trava só uma leva a recompensa; sem ela, as duas passam do limite
    assert sorted(r.bonus_indicador_tratinhos for r in resultados) == esperado


# --- 3. reajuste ---------------------------------------------------------------------------------


@pytest.fixture
def serie(b):
    b.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    r = b.cliente.post(
        "/v1/recorrencias",
        json={
            "pedido_origem_id": "ped-1",
            "frequencia": "semanal",
            "proxima_visita_em": (AGORA + 30 * H).isoformat(),
        },
        headers=cab("t-cliente"),
    )
    rid = r.json()["id"]
    assert (
        b.cliente.post(f"/v1/recorrencias/{rid}/aceitar", headers=cab("t-prof")).status_code == 200
    )
    return b, rid


def _reaj(amb, rid, caminho, quem, valor=None):
    corpo = None if valor is None else {"valor_centavos": valor}
    return amb.cliente.post(f"/v1/recorrencias/{rid}/{caminho}", json=corpo, headers=cab(quem))


def test_aceite_do_reajuste_exige_o_valor_que_o_cliente_viu(serie):
    amb, rid = serie
    assert _reaj(amb, rid, "reajuste", "t-prof", 120_000).status_code == 200
    sem_corpo = _reaj(amb, rid, "reajuste/aceitar", "t-cliente")
    assert sem_corpo.status_code == 422
    errado = _reaj(amb, rid, "reajuste/aceitar", "t-cliente", 110_000)
    assert errado.status_code == 409
    assert errado.json()["detail"] == "O valor do reajuste mudou. Confira o novo valor."
    assert amb.contexto.recorrencias.obter(rid).valor_centavos == 100_000  # nada mudou
    ok = _reaj(amb, rid, "reajuste/aceitar", "t-cliente", 120_000)
    assert ok.status_code == 200 and ok.json()["valor_centavos"] == 120_000
    de_novo = _reaj(amb, rid, "reajuste/aceitar", "t-cliente", 120_000)
    assert de_novo.status_code == 409
    assert de_novo.json()["detail"] == "Não há reajuste esperando resposta."


def test_nova_proposta_com_outra_pendente_da_409(serie):
    amb, rid = serie
    assert _reaj(amb, rid, "reajuste", "t-prof", 120_000).status_code == 200
    segunda = _reaj(amb, rid, "reajuste", "t-prof", 130_000)
    assert segunda.status_code == 409 and "esperando resposta" in segunda.json()["detail"]
    assert amb.contexto.recorrencias.obter(rid).valor_proposto_centavos == 120_000  # a 1ª vale
    assert _reaj(amb, rid, "reajuste/recusar", "t-cliente").status_code == 200
    assert _reaj(amb, rid, "reajuste", "t-prof", 130_000).status_code == 200  # liberou


# --- 4. partes inativas não geram visita ----------------------------------------------------------


@pytest.mark.parametrize(
    "mudanca",
    [
        ("pro-1", PapelUsuario.PROFISSIONAL, "bloqueado"),  # profissional inativo
        ("pro-1", PapelUsuario.CLIENTE, "ativo"),  # sem perfil de profissional aprovado
        ("cli-1", PapelUsuario.CLIENTE, "restrito"),  # cliente inativo
    ],
)
def test_parte_inativa_pausa_a_serie_e_nao_gera_visita(serie, mudanca):
    amb, rid = serie
    uid, papel, status = mudanca
    amb.contexto.usuarios.adicionar(PerfilDetalhe(uid, "Nome Teste", papel, status))
    assert ExecutorContexto(amb.contexto).gerar_visitas_recorrentes(AGORA) == 0
    assert amb.contexto.recorrencias.obter(rid).status == "pausada"
    assert amb.contexto.recorrencias.visitas(rid) == []


def test_partes_ativas_seguem_gerando(serie):
    amb, rid = serie
    assert ExecutorContexto(amb.contexto).gerar_visitas_recorrentes(AGORA) == 1
    assert amb.contexto.recorrencias.obter(rid).status == "ativa"
