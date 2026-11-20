# ruff: noqa
"""QA adversarial (em memoria, nunca contra producao). Tenta quebrar dinheiro, autorizacao e fluxo.

Testes marcados xfail(strict=True) com motivo 'bug conhecido: QA-xx' falham de proposito ate a
correcao; ao corrigir, o strict avisa para remover a marca.
"""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

import pytest
from conftest import AGORA, cab

from trato.financeiro.ledger import (
    ChaveReutilizada,
    EstornoInvalido,
    LancamentoInvalido,
    Livro,
    estornar,
    liberar,
    registrar_cobranca,
    repartir_custodia,
)
from trato.pedidos.estados import Estado as E
from trato.pedidos.estados import Janela

ROTAS_DO_PEDIDO = [
    "/v1/pedidos/ped-1",
    "/v1/pedidos/ped-1/eventos",
    "/v1/pedidos/ped-1/pagamento",
    "/v1/pedidos/ped-1/extrato",
    "/v1/pedidos/ped-1/saldo",
    "/v1/pedidos/ped-1/mensagens",
    "/v1/pedidos/ped-1/orcamentos",
    "/v1/pedidos/ped-1/dados",
    "/v1/pedidos/ped-1/interlocutor",
    "/v1/pedidos/ped-1/disputa",
    "/v1/pedidos/ped-1/exclusividade",
    "/v1/contratos/ped-1/garantia",
    "/v1/contratos/ped-1/pagamento",
    "/v1/contratos/ped-1/aditivos",
    "/v1/orcamentos/orc-1",
]


# ---------- AUTORIZACAO (IDOR) ----------
@pytest.mark.parametrize("url", ROTAS_DO_PEDIDO)
@pytest.mark.parametrize("token", ["t-outro-cliente", "t-outro-prof"])
def test_idor_terceiro_nao_le_o_pedido_dos_outros(amb, url, token):
    amb.semear_pedido(
        E.AGENDADO, janela=Janela(AGORA + timedelta(hours=1), AGORA + timedelta(hours=3))
    )
    r = amb.cliente.get(url, headers=cab(token))
    assert r.status_code == 404, f"{url} com {token}: {r.status_code} {r.text[:120]}"
    assert "cli-1" not in r.text and "pro-1" not in r.text


@pytest.mark.parametrize("url", ROTAS_DO_PEDIDO)
def test_sem_token_ou_token_invalido_nunca_le(amb, url):
    amb.semear_pedido(E.AGENDADO)
    assert amb.cliente.get(url).status_code == 401
    assert amb.cliente.get(url, headers=cab("t-expirado-ou-inventado")).status_code == 401


def test_cliente_nao_chama_rota_de_profissional_e_vice_versa(amb):
    amb.semear_pedido(E.AGENDADO)
    assert (
        amb.cliente.post(
            "/v1/profissional/pedidos/ped-1/a-caminho", headers=cab("t-cliente")
        ).status_code
        == 403
    )
    assert (
        amb.cliente.get("/v1/profissional/orcamentos", headers=cab("t-cliente")).status_code == 403
    )


# ---------- A CAMINHO ----------
@pytest.mark.parametrize("estado", [e for e in E if e is not E.AGENDADO])
def test_a_caminho_so_em_pedido_agendado(amb, estado):
    amb.semear_pedido(estado)
    r = amb.cliente.post("/v1/profissional/pedidos/ped-1/a-caminho", headers=cab("t-prof"))
    assert r.status_code == 409, f"{estado}: {r.status_code}"


@pytest.mark.parametrize("eta", [True, False, 0, -5, 5.5, "20", 10**12, None.__class__])
def test_a_caminho_eta_malformado_da_422(amb, eta):
    amb.semear_pedido(E.AGENDADO)
    corpo = {"eta_minutos": eta if eta is not None.__class__ else "x"}
    r = amb.cliente.post(
        "/v1/profissional/pedidos/ped-1/a-caminho", json=corpo, headers=cab("t-prof")
    )
    assert r.status_code == 422, f"{eta!r}: {r.status_code}"


def test_a_caminho_campo_extra_e_recusado(amb):
    amb.semear_pedido(E.AGENDADO)
    r = amb.cliente.post(
        "/v1/profissional/pedidos/ped-1/a-caminho",
        json={"eta_minutos": 10, "cliente_id": "x"},
        headers=cab("t-prof"),
    )
    assert r.status_code == 422


def test_a_caminho_pedido_inexistente_e_id_estranho(amb):
    for pid in ("nao-existe", "..%2F..%2Fetc", "' OR 1=1 --", "%F0%9F%92%A9", "a" * 3000):
        r = amb.cliente.post(f"/v1/profissional/pedidos/{pid}/a-caminho", headers=cab("t-prof"))
        assert r.status_code in (404, 405, 414), f"{pid[:20]}: {r.status_code}"


# ---------- DINHEIRO: LEDGER ----------
def _cobrar(livro, valor=10_000, chave="cob-1"):
    return registrar_cobranca(livro, "ped-1", valor, chave, AGORA)


@pytest.mark.parametrize(
    "valor", [0, -1, -10_000, 10.5, float("nan"), float("inf"), "100", None, True]
)
def test_ledger_recusa_valor_invalido(valor):
    with pytest.raises(LancamentoInvalido):
        _cobrar(Livro(), valor)


def test_ledger_data_sem_fuso_e_recusada():
    with pytest.raises(LancamentoInvalido):
        registrar_cobranca(Livro(), "ped-1", 100, "c", datetime(2026, 1, 1))


def test_ledger_mesma_chave_10x_grava_uma_vez():
    livro = Livro()
    for _ in range(10):
        _cobrar(livro)
    assert len(livro.lancamentos) == 1 and livro.total_creditos() == 10_000


def test_ledger_mesma_chave_valor_diferente_e_erro():
    livro = Livro()
    _cobrar(livro, 10_000)
    with pytest.raises(ChaveReutilizada):
        _cobrar(livro, 10_001)


def test_ledger_valor_enorme_nao_estoura_bigint():
    """Postgres bigint vai ate 9.22e18: o ledger recusa acima de 9e15 centavos (QA-02)."""
    with pytest.raises(LancamentoInvalido):
        _cobrar(Livro(), 10**30)
    with pytest.raises(LancamentoInvalido):
        _cobrar(Livro(), 9_000_000_000_000_001)
    assert _cobrar(Livro(), 9_000_000_000_000_000).valor == 9_000_000_000_000_000  # o teto vale


def test_ledger_repartir_mais_que_a_custodia_e_recusado():
    livro = Livro()
    _cobrar(livro, 10_000)
    with pytest.raises(LancamentoInvalido):
        repartir_custodia(livro, "ped-1", "pro-1", 10_001, "rep-1", AGORA)


def test_ledger_repartir_2x_mesma_chave_nao_duplica():
    livro = Livro()
    _cobrar(livro, 10_000)
    primeiro = repartir_custodia(livro, "ped-1", "pro-1", 1_000, "rep-1", AGORA)
    for _ in range(5):
        # A custódia já zerou: o reenvio devolve o resultado antigo (QA-03), sem duplicar.
        assert repartir_custodia(livro, "ped-1", "pro-1", 1_000, "rep-1", AGORA) == primeiro
    assert len(livro.lancamentos) == 1 + len(primeiro)
    assert livro.saldos_pedido("ped-1", "pro-1").taxa_trato == 1_000
    livro.verificar_partidas()


def test_ledger_repartir_mesma_chave_com_parametros_diferentes_continua_erro():
    livro = Livro()
    _cobrar(livro, 10_000)
    repartir_custodia(livro, "ped-1", "pro-1", 1_000, "rep-1", AGORA)
    with pytest.raises(ChaveReutilizada):
        repartir_custodia(livro, "ped-1", "pro-1", 2_000, "rep-1", AGORA)  # outra taxa
    with pytest.raises(ChaveReutilizada):
        repartir_custodia(livro, "ped-1", "pro-2", 1_000, "rep-1", AGORA)  # outro profissional
    assert len(livro.lancamentos) == 3


def test_ledger_liberar_repetido_com_a_mesma_chave_devolve_o_antigo():
    livro = Livro()
    _cobrar(livro, 10_000)
    repartir_custodia(livro, "ped-1", "pro-1", 1_000, "rep-1", AGORA)
    primeiro = liberar(livro, "ped-1", "pro-1", "lib-1", AGORA)
    assert liberar(livro, "ped-1", "pro-1", "lib-1", AGORA) == primeiro  # o saldo já zerou
    assert len(livro.lancamentos) == 4
    with pytest.raises(ChaveReutilizada):
        liberar(livro, "ped-1", "pro-2", "lib-1", AGORA)


def test_ledger_estorno_duplo_com_chaves_diferentes_e_recusado():
    livro = Livro()
    orig = _cobrar(livro, 10_000)
    estornar(livro, orig.id, "est-1", AGORA)
    with pytest.raises(EstornoInvalido):
        estornar(livro, orig.id, "est-2", AGORA)
    assert livro.saldos_pedido("ped-1").cliente_pagou == 0


def test_ledger_estorno_mesma_chave_e_idempotente():
    livro = Livro()
    orig = _cobrar(livro, 10_000)
    for _ in range(5):
        estornar(livro, orig.id, "est-1", AGORA)
    assert len(livro.lancamentos) == 2


def test_ledger_nao_estorna_estorno_nem_inexistente():
    livro = Livro()
    orig = _cobrar(livro, 10_000)
    est = estornar(livro, orig.id, "est-1", AGORA)
    with pytest.raises(EstornoInvalido):
        estornar(livro, est.id, "est-2", AGORA)
    with pytest.raises(EstornoInvalido):
        estornar(livro, "id-inventado", "est-3", AGORA)


def test_ledger_lancamento_e_imutavel():
    livro = Livro()
    item = _cobrar(livro, 10_000)
    with pytest.raises(Exception):
        item.valor = 1  # type: ignore[misc]
    assert isinstance(livro.lancamentos, tuple)


def test_ledger_corrida_mesma_chave_em_duas_threads():
    resultados = []
    for _ in range(300):
        livro = Livro()
        barreira = threading.Barrier(8)

        def tarefa():
            barreira.wait()
            try:
                registrar_cobranca(livro, "ped-1", 10_000, "cob-1", AGORA)
            except Exception:  # noqa: BLE001
                pass

        ts = [threading.Thread(target=tarefa) for _ in range(8)]
        [t.start() for t in ts]
        [t.join() for t in ts]
        resultados.append(len(livro.lancamentos))
    assert set(resultados) == {1}, f"lancamentos por rodada: {sorted(set(resultados))}"


# ---------- DATAS / FUSO ----------
def test_a_caminho_mostra_hora_de_brasilia_na_virada_do_dia(amb):
    """23:30 em Brasilia (02:30 UTC do dia seguinte) nao pode virar '02:30'."""
    from trato.notificacoes import ligar_ao_contexto
    from trato.notificacoes.canais import Canais, CanalApp
    from trato.notificacoes.config import ConfigNotificacoes
    from trato.notificacoes.repositorio import RepositorioEmMemoria
    from trato.notificacoes.servico import ServicoNotificacoes

    amb.relogio.agora = datetime(2027, 1, 1, 2, 30, tzinfo=UTC)  # 31/12 23:30 BRT
    amb.semear_pedido(
        E.AGENDADO,
        janela=Janela(
            amb.relogio.agora + timedelta(hours=1), amb.relogio.agora + timedelta(hours=3)
        ),
    )
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(), Canais(CanalApp()), ConfigNotificacoes(_env_file=None), amb.relogio
    )
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    r = amb.cliente.post(
        "/v1/profissional/pedidos/ped-1/a-caminho", json={"eta_minutos": 20}, headers=cab("t-prof")
    )
    assert r.status_code == 200
    [n] = notif.repo.listar("cli-1", False, 10)
    assert "23:30" in n.corpo, n.corpo


def test_upload_tamanho_tem_limite_por_tipo_da_config_e_1gb_e_recusado():
    """O esquema aceita até 10**9, mas o limite por categoria da config corta antes (422)."""
    from trato.seguranca.config import ConfigSeguranca
    from trato.seguranca.upload import ErroUpload, validar_metadados

    config = ConfigSeguranca()
    assert config.uploads  # foto, portfolio, documento, anexo_pedido
    for categoria, regra in config.uploads.items():
        tipo = regra.tipos[0]
        nome = "a.jpg" if tipo == "image/jpeg" else "a.png" if tipo == "image/png" else "a.webp"
        if not tipo.startswith("image/"):
            continue
        validar_metadados(config, categoria, tipo, regra.tamanho_max_bytes, nome)  # no limite: ok
        for acima in (regra.tamanho_max_bytes + 1, 10**9):
            with pytest.raises(ErroUpload, match="grande demais"):
                validar_metadados(config, categoria, tipo, acima, nome)
