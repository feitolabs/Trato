"""Indique e Ganhe Tratinhos: código, aplicar, gatilho no 1º serviço, liberação e limites."""

from __future__ import annotations

from dataclasses import replace
from datetime import timedelta
from types import SimpleNamespace

import pytest
from conftest import AGORA, cab

from trato.agendador.executor import ExecutorContexto
from trato.api.auth import PapelUsuario
from trato.api.indicacoes import ConfigIndicacao, acionar_gatilho
from trato.api.moedas import ConfigMoedas, MoedasEmMemoria
from trato.api.repositorios import Contrato
from trato.api.repositorios_app import PerfilDetalhe
from trato.disputas import Estado as EstadoDisputa
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado

D = timedelta(days=1)
NOMES = {
    "cli-1": ("João Pedro Silva", PapelUsuario.CLIENTE),
    "cli-2": ("Maria Oliveira Lima", PapelUsuario.CLIENTE),
    "pro-1": ("Carlos Eduardo Souza", PapelUsuario.PROFISSIONAL),
    "pro-2": ("Ana Beatriz Costa", PapelUsuario.PROFISSIONAL),
}
TOKENS = {
    "cli-1": "t-cliente",
    "cli-2": "t-outro-cliente",
    "pro-1": "t-prof",
    "pro-2": "t-outro-prof",
}


@pytest.fixture
def ind(amb):
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True))
    for uid, (nome, papel) in NOMES.items():
        amb.contexto.usuarios.adicionar(PerfilDetalhe(uid, nome, papel))
    return amb


def _codigo(amb, uid):
    r = amb.cliente.get("/v1/indicacoes/meu-codigo", headers=cab(TOKENS[uid]))
    assert r.status_code == 200, r.text
    return r.json()["codigo"]


def _aplicar(amb, uid, codigo):
    return amb.cliente.post(
        "/v1/indicacoes/aplicar", json={"codigo": codigo}, headers=cab(TOKENS[uid])
    )


def _concluir(amb, valor=100_000):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.contexto.contratos.salvar(Contrato("ped-1", "orc-1", "pro-1", valor, "pintura"))
    amb.semear_dinheiro(valor, taxa=valor // 10)
    r = amb.cliente.post("/v1/pedidos/ped-1/acoes/confirmar_conclusao", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text


def _executor(amb):
    repo = RepositorioEmMemoria()
    notif = ServicoNotificacoes(repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True))
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    return ExecutorContexto(amb.contexto, notif), repo


def _do_indicado(amb, uid):
    return amb.contexto.indicacoes.do_indicado(uid)


# --- código pessoal ------------------------------------------------------------------------


def test_codigo_unico_estavel_e_sem_ambiguos(ind):
    codigos = {uid: _codigo(ind, uid) for uid in NOMES}
    assert len(set(codigos.values())) == 4
    for codigo in codigos.values():
        assert 6 <= len(codigo) <= 10 and codigo == codigo.upper() and codigo.isalnum()
        assert not set(codigo) & set("01OIL")
    assert _codigo(ind, "cli-1") == codigos["cli-1"]  # estável


def test_meu_codigo_exige_login_e_bloqueia_equipe(ind):
    assert ind.cliente.get("/v1/indicacoes/meu-codigo").status_code == 401
    assert ind.cliente.get("/v1/indicacoes/meu-codigo", headers=cab("t-equipe")).status_code == 403


def test_meu_codigo_lista_so_nome_curto_e_resumo(ind):
    assert _aplicar(ind, "cli-1", _codigo(ind, "cli-2")).status_code == 201
    r = ind.cliente.get("/v1/indicacoes/meu-codigo", headers=cab("t-outro-cliente")).json()
    assert r["resumo"] == {
        "cadastradas": 1,
        "aguardando_liberacao": 0,
        "liberadas": 0,
        "limite_mensal": 3,
        "limite_mensal_restante": 3,
        "validade_dias": 90,  # validade dos Tratinhos (Termos 13.3)
    }
    (item,) = r["indicacoes"]
    assert item["indicado_nome"] == "João S."
    assert (item["status"], item["tipo"]) == ("cadastrado", "cliente_cliente")
    assert item["bonus_indicador_tratinhos"] == 300
    texto = str(r)
    assert "Pedro" not in texto and "Silva" not in texto and "@" not in texto


# --- aplicar código -----------------------------------------------------------------------


def test_cliente_indica_cliente_300_300_e_normaliza_o_codigo(ind):
    codigo = _codigo(ind, "cli-2")
    r = _aplicar(ind, "cli-1", f"  {codigo.lower()} ")
    assert r.status_code == 201, r.text
    assert r.json()["tipo"] == "cliente_cliente" and r.json()["bonus_indicado_tratinhos"] == 300
    salvo = _do_indicado(ind, "cli-1")
    assert (salvo.bonus_indicador_tratinhos, salvo.bonus_indicado_tratinhos) == (300, 300)
    assert salvo.codigo_usado == codigo and salvo.status == "cadastrado"


def test_uso_unico_a_segunda_tentativa_da_409(ind):
    primeiro = _codigo(ind, "cli-2")
    assert _aplicar(ind, "cli-1", primeiro).status_code == 201
    outra = _aplicar(ind, "cli-1", _codigo(ind, "pro-1"))
    assert outra.status_code == 409
    assert outra.json()["detail"] == "Você já utilizou um código de indicação."


def test_auto_indicacao_da_422_e_codigo_inexistente_404(ind):
    r = _aplicar(ind, "cli-1", _codigo(ind, "cli-1"))
    assert r.status_code == 422
    assert r.json()["detail"] == "Você não pode usar o próprio código de indicação."
    nao = _aplicar(ind, "cli-1", "ZZZZZZZZ")
    assert nao.status_code == 404
    assert nao.json()["detail"] == "Código de indicação não encontrado."
    assert _aplicar(ind, "cli-1", "!!").status_code == 404


def test_profissional_indica_cliente_150_300_e_profissional_indica_profissional_150_100(ind):
    assert _aplicar(ind, "cli-1", _codigo(ind, "pro-1")).status_code == 201
    pc = _do_indicado(ind, "cli-1")
    assert (pc.tipo, pc.bonus_indicador_tratinhos, pc.bonus_indicado_tratinhos) == (
        "profissional_cliente",
        150,
        300,
    )
    assert _aplicar(ind, "pro-2", _codigo(ind, "pro-1")).status_code == 201
    pp = _do_indicado(ind, "pro-2")
    assert (pp.tipo, pp.bonus_indicador_tratinhos, pp.bonus_indicado_tratinhos) == (
        "profissional_profissional",
        150,
        100,
    )


def test_cliente_nao_indica_profissional(ind):
    r = _aplicar(ind, "pro-1", _codigo(ind, "cli-2"))
    assert r.status_code == 422
    assert r.json()["detail"] == (
        "A indicação de novos profissionais está disponível apenas por códigos de profissionais."
    )
    assert _do_indicado(ind, "pro-1") is None


def test_bloqueia_depois_do_primeiro_pedido(ind):
    codigo = _codigo(ind, "cli-2")
    ind.semear_pedido(Estado.ABERTO)
    assert _aplicar(ind, "cli-1", codigo).status_code == 409
    assert _do_indicado(ind, "cli-1") is None


def test_profissional_que_ja_concluiu_servico_nao_usa_codigo(ind):
    codigo = _codigo(ind, "pro-2")
    ind.semear_pedido(Estado.CONCLUIDO)
    assert _aplicar(ind, "pro-1", codigo).status_code == 409


def test_indicacao_cruzada_da_409(ind):
    assert _aplicar(ind, "cli-1", _codigo(ind, "cli-2")).status_code == 201
    assert _aplicar(ind, "cli-2", _codigo(ind, "cli-1")).status_code == 409


def test_conferir_codigo_nao_vaza_dados_privados(ind):
    codigo = _codigo(ind, "pro-1")
    r = ind.cliente.get(f"/v1/indicacoes/codigo/{codigo.lower()}")
    assert r.status_code == 200, r.text
    assert r.json() == {
        "valido": True,
        "indicador_nome_curto": "Carlos S.",
        "indicador_papel": "profissional",
        "profissional_id": "pro-1",
    }
    cliente = ind.cliente.get(f"/v1/indicacoes/codigo/{_codigo(ind, 'cli-2')}").json()
    assert cliente["indicador_papel"] == "cliente" and cliente["profissional_id"] is None
    assert ind.cliente.get("/v1/indicacoes/codigo/NAOEXISTE").status_code == 404


# --- gatilho e liberação ------------------------------------------------------------------


def test_gatilho_so_vale_a_partir_de_r60_pagos(ind):
    assert _aplicar(ind, "cli-1", _codigo(ind, "cli-2")).status_code == 201
    _concluir(ind, valor=5_999)
    assert _do_indicado(ind, "cli-1").status == "cadastrado"


def test_gatilho_move_para_aguardando_com_pedido_e_prazo_de_7_dias(ind):
    assert _aplicar(ind, "cli-1", _codigo(ind, "cli-2")).status_code == 201
    _concluir(ind, valor=6_000)
    i = _do_indicado(ind, "cli-1")
    assert i.status == "aguardando_liberacao" and i.pedido_gatilho_id == "ped-1"
    assert i.liberacao_prevista_em == ind.contexto.agora() + 7 * D
    # concluir outro pedido não arma de novo (só o 1º serviço conta)
    assert acionar_gatilho(ind.contexto, ind.contexto.pedidos.obter("ped-1"), AGORA) == []


def test_liberacao_credita_os_dois_lados_uma_vez_e_avisa(ind):
    executor, avisos = _executor(ind)
    assert _aplicar(ind, "cli-1", _codigo(ind, "cli-2")).status_code == 201
    _concluir(ind)
    assert executor.liberar_indicacoes(AGORA + 6 * D) == 0  # ainda não venceu
    assert executor.liberar_indicacoes(AGORA + 8 * D) == 1
    assert executor.liberar_indicacoes(AGORA + 9 * D) == 0  # idempotente
    moedas = ind.contexto.moedas
    assert moedas.saldo("cli-2", AGORA + 9 * D) == 300  # indicador
    assert moedas.saldo("cli-1", AGORA + 9 * D) == 300  # indicado
    assert _do_indicado(ind, "cli-1").status == "liberado"
    tipos = {n.tipo for uid in ("cli-1", "cli-2") for n in avisos.listar(uid, False, 10)}
    assert tipos == {"indicacao.liberada"}
    assert all(len(avisos.listar(uid, False, 10)) == 1 for uid in ("cli-1", "cli-2"))
    # validade de 90 dias
    lancamento = moedas.extrato("cli-1")[0]
    assert lancamento.tipo == "bonus_indicacao"
    assert lancamento.expira_em == AGORA + 8 * D + timedelta(days=90)


def test_profissional_indicando_profissional_vai_para_a_carteira_do_profissional(ind):
    executor, _ = _executor(ind)
    assert _aplicar(ind, "pro-1", _codigo(ind, "pro-2")).status_code == 201
    _concluir(ind)  # o indicado (pro-1) é o profissional do pedido
    assert _do_indicado(ind, "pro-1").status == "aguardando_liberacao"
    assert executor.liberar_indicacoes(AGORA + 8 * D) == 1
    moedas = ind.contexto.moedas
    assert moedas.saldo("pro-2", AGORA + 8 * D, "profissional") == 150
    assert moedas.saldo("pro-1", AGORA + 8 * D, "profissional") == 100
    assert moedas.saldo("pro-1", AGORA + 8 * D, "cliente") == 0  # nunca vira desconto


def test_profissional_indica_cliente_cai_na_carteira_certa_de_cada_um(ind):
    executor, _ = _executor(ind)
    # O indicador (pro-2) não é o profissional do pedido (pro-1): o serviço vale.
    assert _aplicar(ind, "cli-1", _codigo(ind, "pro-2")).status_code == 201
    _concluir(ind)
    assert executor.liberar_indicacoes(AGORA + 8 * D) == 1
    moedas = ind.contexto.moedas
    assert moedas.saldo("pro-2", AGORA + 8 * D, "profissional") == 150
    assert moedas.saldo("cli-1", AGORA + 8 * D, "cliente") == 300


@pytest.mark.parametrize("situacao", ["cancelado", "disputa_aberta", "disputa_procedente"])
def test_cancela_sem_creditar_se_o_pedido_gatilho_deu_problema(ind, situacao):
    executor, _ = _executor(ind)
    assert _aplicar(ind, "cli-1", _codigo(ind, "cli-2")).status_code == 201
    _concluir(ind)
    if situacao == "cancelado":
        pedido = ind.contexto.pedidos.obter("ped-1")
        ind.contexto.pedidos.salvar(replace(pedido, estado=Estado.CANCELADO))
    elif situacao == "disputa_aberta":
        ind.contexto.disputas.obter = lambda pid: SimpleNamespace(estado="em_analise", divisao=None)
    else:
        ind.contexto.disputas.obter = lambda pid: SimpleNamespace(
            estado=EstadoDisputa.DECIDIDA, divisao=SimpleNamespace(para_cliente=5_000)
        )
    assert executor.liberar_indicacoes(AGORA + 8 * D) == 0
    i = _do_indicado(ind, "cli-1")
    assert i.status == "cancelado" and i.motivo_bloqueio.startswith("pedido_gatilho:")
    assert ind.contexto.moedas.saldo("cli-1", AGORA + 8 * D) == 0
    assert ind.contexto.moedas.saldo("cli-2", AGORA + 8 * D) == 0


@pytest.mark.parametrize(
    ("indicador", "tipo", "limite", "bonus"),
    [("cli-2", "cliente_cliente", 3, 300), ("pro-2", "profissional_cliente", 5, 150)],
)
def test_limite_mensal_zera_o_bonus_do_indicador_mas_nao_o_do_indicado(
    ind, indicador, tipo, limite, bonus
):
    repo = ind.contexto.indicacoes
    codigo = _codigo(ind, indicador)

    def encher(quantas):
        for n in range(quantas):
            feita = repo.criar(indicador, f"amigo-{n}", f"AMIGO{n:03d}", tipo, bonus, 300, AGORA)
            assert repo.armar(feita.id, f"ped-x{n}", bonus, AGORA + 7 * D)

    # Um a menos que o limite: ainda recompensa.
    encher(limite - 1)
    assert _aplicar(ind, "cli-1", codigo).status_code == 201
    _concluir(ind)
    assert _do_indicado(ind, "cli-1").bonus_indicador_tratinhos == bonus


@pytest.mark.parametrize(
    ("indicador", "tipo", "limite", "bonus"),
    [("cli-2", "cliente_cliente", 3, 300), ("pro-2", "profissional_cliente", 5, 150)],
)
def test_no_limite_o_indicador_fica_com_zero_e_o_indicado_recebe(
    ind, indicador, tipo, limite, bonus
):
    repo = ind.contexto.indicacoes
    codigo = _codigo(ind, indicador)
    for n in range(limite):
        feita = repo.criar(indicador, f"amigo-{n}", f"AMIGO{n:03d}", tipo, bonus, 300, AGORA)
        assert repo.armar(feita.id, f"ped-x{n}", bonus, AGORA + 7 * D)
    assert _aplicar(ind, "cli-1", codigo).status_code == 201
    _concluir(ind)
    i = _do_indicado(ind, "cli-1")
    assert i.status == "aguardando_liberacao"
    assert (i.bonus_indicador_tratinhos, i.bonus_indicado_tratinhos) == (0, 300)
    executor, _ = _executor(ind)
    assert executor.liberar_indicacoes(AGORA + 8 * D) == limite + 1
    carteira = "profissional" if indicador.startswith("pro") else "cliente"
    moedas = ind.contexto.moedas
    assert _do_indicado(ind, "cli-1").status == "liberado"
    assert moedas.saldo("cli-1", AGORA + 8 * D) == 300  # o indicado recebe
    # o indicador só recebeu as `limite` indicações anteriores; a que passou do limite deu 0
    assert moedas.saldo(indicador, AGORA + 8 * D, carteira) == bonus * limite
    resumo = ind.cliente.get("/v1/indicacoes/meu-codigo", headers=cab(TOKENS[indicador])).json()
    assert resumo["resumo"]["limite_mensal_restante"] == 0


def test_config_pode_mudar_os_valores_sem_mexer_nas_regras(ind):
    ind.contexto.indicacoes.salvar_config(ConfigIndicacao(bonus_cliente_cliente=(500, 400)))
    assert _aplicar(ind, "cli-1", _codigo(ind, "cli-2")).status_code == 201
    i = _do_indicado(ind, "cli-1")
    assert (i.bonus_indicador_tratinhos, i.bonus_indicado_tratinhos) == (500, 400)
