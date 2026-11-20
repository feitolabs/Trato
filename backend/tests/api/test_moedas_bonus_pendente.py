"""Bônus de moedas pendente: a avaliação grava em `moedas_pendentes`; a rotina libera depois de
`dias_liberacao_bonus` (7) sem disputa, ou cancela com disputa perdida. Sem a tabela, volta ao
crédito imediato."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import date, timedelta
from types import SimpleNamespace

import pytest
from conftest import AGORA, cab

from trato.agendador.executor import ExecutorContexto
from trato.api.moedas import (
    ConfigMoedas,
    LancamentoMoeda,
    MoedasEmMemoria,
    MoedasPostgres,
    conceder_bonus_avaliacao,
    liberar_bonus_pendentes,
    resumo_pendentes,
)
from trato.disputas import Estado as EstadoDisputa
from trato.pedidos.estados import Estado
from trato.rotinas.regras import DecisaoBonus, decidir_liberacao_bonus

KW = {"cliente_id": "c", "valor_servico_centavos": 10_000, "agora": AGORA}


def _repo(**cfg) -> MoedasEmMemoria:
    return MoedasEmMemoria(ConfigMoedas(ativo=True, **cfg))


def _liberar(repo, quando, situacao="nenhuma"):
    return liberar_bonus_pendentes(repo, agora=quando, situacao_disputa=lambda _p: situacao)


# --- regra pura ---------------------------------------------------------------------------------


def test_regra_pura_do_bonus():
    ate = AGORA + timedelta(days=7)
    assert (
        decidir_liberacao_bonus(ate - timedelta(seconds=1), ate, "nenhuma") is DecisaoBonus.AGUARDAR
    )
    assert decidir_liberacao_bonus(ate, ate, "nenhuma") is DecisaoBonus.LIBERAR
    assert (
        decidir_liberacao_bonus(ate, ate, "aberta") is DecisaoBonus.AGUARDAR
    )  # sem decisão: espera
    assert decidir_liberacao_bonus(ate, ate, "perdida") is DecisaoBonus.CANCELAR
    # Disputa perdida antes do prazo também espera o prazo (a decisão só vale no vencimento).
    assert decidir_liberacao_bonus(AGORA, ate, "perdida") is DecisaoBonus.AGUARDAR


# --- avaliação -> pendente -> liberado -------------------------------------------------------------


def test_bonus_nasce_pendente_e_so_vira_saldo_apos_o_prazo():
    repo = _repo()
    assert conceder_bonus_avaliacao(repo, pedido_id="p", **KW) == 50
    assert repo.saldo("c", AGORA) == 0  # não entra direto no saldo
    assert resumo_pendentes(repo, "c") == (50, date(2026, 11, 5))

    assert _liberar(repo, AGORA + timedelta(days=6, hours=23)).liberados == 0
    assert repo.saldo("c", AGORA + timedelta(days=6, hours=23)) == 0

    depois = AGORA + timedelta(days=7)
    assert _liberar(repo, depois).liberados == 1
    assert repo.saldo("c", depois) == 50
    assert resumo_pendentes(repo, "c") == (0, None)
    lanc = repo.extrato("c")[0]
    assert (lanc.tipo, lanc.quantidade, lanc.chave_idempotencia) == (
        "bonus_avaliacao",
        50,
        "avaliacao:p",
    )  # a mesma chave de antes


def test_liberacao_e_idempotente():
    repo = _repo()
    conceder_bonus_avaliacao(repo, pedido_id="p", **KW)
    depois = AGORA + timedelta(days=8)
    assert _liberar(repo, depois).liberados == 1
    assert _liberar(repo, depois).liberados == 0  # rodar de novo não credita de novo
    assert repo.saldo("c", depois) == 50
    # Ciclo que caiu depois de lançar e antes de marcar: só falta marcar, saldo continua 50.
    repo2 = _repo()
    conceder_bonus_avaliacao(repo2, pedido_id="p", **KW)
    pend = repo2.pendentes_do_usuario("c")[0]
    repo2.lancar(LancamentoMoeda("c", "bonus_avaliacao", 50, pend.chave_idempotencia, depois))
    assert _liberar(repo2, depois).liberados == 1
    assert repo2.saldo("c", depois) == 50
    assert repo2.pendentes_do_usuario("c") == []


def test_avaliar_de_novo_nao_cria_outro_pendente():
    repo = _repo()
    assert conceder_bonus_avaliacao(repo, pedido_id="p", **KW) == 50
    assert conceder_bonus_avaliacao(repo, pedido_id="p", **KW) == 0
    _liberar(repo, AGORA + timedelta(days=7))
    assert conceder_bonus_avaliacao(repo, pedido_id="p", **KW) == 0  # nem depois de liberado
    assert repo.saldo("c", AGORA + timedelta(days=7)) == 50


def test_disputa_perdida_cancela_aberta_segura_e_ganha_libera():
    repo = _repo(max_bonus_por_profissional_mes=9)
    for pid in ("a", "b", "c"):
        conceder_bonus_avaliacao(repo, pedido_id=pid, profissional_id=f"prof-{pid}", **KW)
    quando = AGORA + timedelta(days=7)
    situacoes = {"a": "perdida", "b": "aberta", "c": "nenhuma"}
    r = liberar_bonus_pendentes(
        repo, agora=quando, situacao_disputa=lambda p: situacoes[p.pedido_id or ""]
    )
    assert (r.liberados, r.cancelados, r.aguardando) == (1, 1, 1)
    assert repo.saldo("c", quando) == 50  # só o "c"
    assert [p.pedido_id for p in repo.pendentes_do_usuario("c")] == ["b"]  # "b" segue esperando
    situacoes["b"] = "perdida"  # a disputa é decidida contra o cliente
    r = liberar_bonus_pendentes(
        repo, agora=quando, situacao_disputa=lambda p: situacoes[p.pedido_id or ""]
    )
    assert (r.liberados, r.cancelados) == (0, 1) and repo.saldo("c", quando) == 50
    assert repo.pendentes_do_usuario("c") == []


def test_pendente_conta_no_teto_mensal_e_no_limite_por_profissional():
    repo = _repo(bonus_avaliacao_moedas=50, teto_mensal_moedas=80, max_bonus_por_profissional_mes=1)
    assert conceder_bonus_avaliacao(repo, pedido_id="1", profissional_id="x", **KW) == 50
    assert (
        conceder_bonus_avaliacao(repo, pedido_id="2", profissional_id="x", **KW) == 0
    )  # mesmo par
    assert conceder_bonus_avaliacao(repo, pedido_id="3", profissional_id="y", **KW) == 30  # teto 80
    assert conceder_bonus_avaliacao(repo, pedido_id="4", profissional_id="z", **KW) == 0


def test_validade_conta_a_partir_da_liberacao():
    repo = _repo(validade_dias=10)
    conceder_bonus_avaliacao(repo, pedido_id="p", **KW)
    liberado = AGORA + timedelta(days=7)
    _liberar(repo, liberado)
    assert repo.saldo("c", liberado + timedelta(days=9)) == 50
    assert repo.saldo("c", liberado + timedelta(days=11)) == 0


# --- sem tabela: cai no comportamento antigo ----------------------------------------------------


class _SemTabelaPendentes(MoedasEmMemoria):
    def criar_pendente(self, pendente):
        raise RuntimeError('relation "public.moedas_pendentes" does not exist')

    def pendentes_do_usuario(self, usuario_id):
        raise RuntimeError('relation "public.moedas_pendentes" does not exist')


def test_sem_a_tabela_o_bonus_e_creditado_na_hora():
    repo = _SemTabelaPendentes(ConfigMoedas(ativo=True))
    assert conceder_bonus_avaliacao(repo, pedido_id="p", **KW) == 50
    assert repo.saldo("c", AGORA) == 50  # crédito imediato, como antes
    assert conceder_bonus_avaliacao(repo, pedido_id="p", **KW) == 0  # idempotente
    assert resumo_pendentes(repo, "c") == (0, None)  # e o resumo não quebra


def test_dias_zero_credita_na_hora():
    repo = _repo(dias_liberacao_bonus=0)
    assert conceder_bonus_avaliacao(repo, pedido_id="p", **KW) == 50
    assert repo.saldo("c", AGORA) == 50 and repo.pendentes_do_usuario("c") == []


class _Con:
    def __init__(self, com_colunas_novas: bool) -> None:
        self.novas = com_colunas_novas
        self._linha: dict | None = None

    def execute(self, sql, params=None):
        if "orcamento_mensal_desconto_centavos" in sql and not self.novas:
            raise RuntimeError('column "orcamento_mensal_desconto_centavos" does not exist')
        linha = {
            "ativo": True,
            "bonus_avaliacao_moedas": 50,
            "valor_moeda_centavos": 1,
            "teto_mensal_moedas": 500,
            "min_servico_centavos": 5000,
            "max_bonus_por_profissional_mes": 1,
            "max_desconto_percentual": 20,
            "validade_dias": None,
        }
        if "orcamento_mensal_desconto_centavos" in sql:
            linha |= {
                "orcamento_mensal_desconto_centavos": 45_000,
                "aviso_percentual": 70,
                "teto_desconto_cliente_mes_centavos": 800,
                "teto_diario_desconto_centavos": 1_500,
                "dias_liberacao_bonus": 3,
            }
        self._linha = linha
        return self

    def fetchone(self):
        return self._linha


class _Banco:
    def __init__(self, com_colunas_novas: bool) -> None:
        self._novas = com_colunas_novas

    @contextmanager
    def transacao(self):
        yield _Con(self._novas)


def test_config_do_postgres_cai_nos_padroes_sem_as_colunas_novas():
    cfg = MoedasPostgres(_Banco(False)).config()
    assert cfg.ativo is True
    assert (
        cfg.orcamento_mensal_desconto_centavos,
        cfg.aviso_percentual,
        cfg.teto_desconto_cliente_mes_centavos,
        cfg.teto_diario_desconto_centavos,
        cfg.dias_liberacao_bonus,
    ) == (30_000, 80, 500, 1_000, 7)


def test_config_do_postgres_le_as_colunas_novas():
    cfg = MoedasPostgres(_Banco(True)).config()
    assert (
        cfg.orcamento_mensal_desconto_centavos,
        cfg.aviso_percentual,
        cfg.teto_desconto_cliente_mes_centavos,
        cfg.teto_diario_desconto_centavos,
        cfg.dias_liberacao_bonus,
    ) == (45_000, 70, 800, 1_500, 3)


# --- HTTP + rotina do agendador -------------------------------------------------------------------


def _post(amb, url, token, corpo=None):
    return amb.cliente.post(url, json=corpo, headers=cab(token))


def test_avaliar_mostra_pendente_na_api_e_rotina_libera(amb):
    amb.contexto.moedas = _repo()
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    r = _post(amb, "/v1/pedidos/ped-1/avaliacao", "t-cliente", {"nota_geral": 5})
    assert r.status_code == 201 and r.json()["moedas_ganhas"] == 50
    m = amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).json()
    assert (m["saldo"], m["moedas_pendentes"], m["proxima_liberacao"]) == (0, 50, "2026-11-05")
    assert m["extrato"] == []

    # Rotina do agendador (disputa inexistente): depois de 7 dias vira saldo.
    amb.relogio.avancar(days=7)
    executor = ExecutorContexto(amb.contexto)
    amb.contexto.disputas = SimpleNamespace(obter=lambda _id: None)
    assert executor.liberar_bonus_moedas(amb.relogio.agora) == 1
    assert executor.liberar_bonus_moedas(amb.relogio.agora) == 0  # idempotente
    m = amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).json()
    assert (m["saldo"], m["moedas_pendentes"], m["proxima_liberacao"]) == (50, 0, None)
    assert m["extrato"][0]["tipo"] == "bonus_avaliacao"


@pytest.mark.parametrize(
    ("estado", "divisao", "liberado"),
    [
        (EstadoDisputa.ABERTA, None, 0),
        (EstadoDisputa.EM_ANALISE, None, 0),
        (EstadoDisputa.DECIDIDA, SimpleNamespace(para_cliente=0, retido=0), "cancelado"),
        (EstadoDisputa.DECIDIDA, SimpleNamespace(para_cliente=5_000, retido=0), 1),
    ],
)
def test_rotina_olha_a_disputa_do_pedido(amb, estado, divisao, liberado):
    amb.contexto.moedas = _repo()
    conceder_bonus_avaliacao(
        amb.contexto.moedas,
        cliente_id="c",
        pedido_id="ped-1",
        valor_servico_centavos=10_000,
        agora=AGORA,
    )
    disputa = SimpleNamespace(estado=estado, divisao=divisao)
    amb.contexto.disputas = SimpleNamespace(obter=lambda _id: disputa)
    quando = AGORA + timedelta(days=7)
    n = ExecutorContexto(amb.contexto).liberar_bonus_moedas(quando)
    saldo = amb.contexto.moedas.saldo("c", quando)
    if liberado == "cancelado":
        assert (n, saldo, amb.contexto.moedas.pendentes_do_usuario("c")) == (0, 0, [])
    else:
        assert (n, saldo) == (liberado, 50 * liberado)
