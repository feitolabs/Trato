"""Etapa B, rodada 1: carteira do profissional separada da do cliente e bônus de 50 Tratinhos por
avaliar um cliente (pendente 7 dias, 1 por cliente para sempre, fail-closed sem as colunas novas)."""

from __future__ import annotations

import threading
from contextlib import contextmanager
from datetime import timedelta
from types import SimpleNamespace

import pytest
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab

from trato.agendador.executor import ExecutorContexto
from trato.api.moedas import (
    TIPO_BONUS_PROFISSIONAL,
    ConfigMoedas,
    DescontoMoedasIndisponivel,
    LancamentoMoeda,
    MoedasEmMemoria,
    MoedasPostgres,
    calcular_uso_moedas,
    conceder_bonus_profissional,
    liberar_bonus_pendentes,
    reservar_desconto,
    resumo_pendentes,
    saldo_profissional,
)
from trato.disputas import Estado as EstadoDisputa
from trato.pagamentos.modelos import EstadoCobranca
from trato.pedidos.estados import Estado

PROF, CLI = PROFISSIONAL.id, CLIENTE.id
CHAVE = f"avaliacao-prof:{PROF}:{CLI}"


def _repo(**cfg) -> MoedasEmMemoria:
    return MoedasEmMemoria(ConfigMoedas(ativo=True, **cfg))


def _dar(repo, pedido="p1", agora=AGORA):
    return conceder_bonus_profissional(
        repo, profissional_id=PROF, cliente_id=CLI, pedido_id=pedido, agora=agora
    )


def _liberar(repo, quando, situacao="nenhuma"):
    return liberar_bonus_pendentes(repo, agora=quando, situacao_disputa=lambda _p: situacao)


# --- 3) bônus: 1 por cliente, vitalício ------------------------------------------------------------------


def test_bonus_nasce_pendente_na_chave_do_par_e_nao_toca_o_orcamento():
    repo = _repo()
    assert _dar(repo) == 50
    assert repo.saldo(PROF, AGORA, "profissional") == 0  # ainda é pendente
    pend = repo.pendentes_do_usuario(PROF, TIPO_BONUS_PROFISSIONAL)
    assert [(p.chave_idempotencia, p.parceiro_id, p.tipo_lancamento) for p in pend] == [
        (CHAVE, CLI, TIPO_BONUS_PROFISSIONAL)
    ]
    assert pend[0].liberar_em == AGORA + timedelta(days=7)
    assert resumo_pendentes(repo, PROF, TIPO_BONUS_PROFISSIONAL) == (50, pend[0].liberar_em.date())
    assert repo.pendentes_do_usuario(PROF) == []  # não conta como bônus do cliente
    assert repo.orcamento_usado(AGORA.date().replace(day=1)) == 0
    assert repo.orcamento_usado_dia(AGORA.date()) == 0


def test_um_bonus_por_cliente_mesmo_em_dois_contratos():
    repo = _repo()
    assert _dar(repo, "p1") == 50
    assert _dar(repo, "p2") == 0  # outro contrato do MESMO cliente
    liberado = AGORA + timedelta(days=7)
    assert _liberar(repo, liberado).liberados == 1
    assert _dar(repo, "p3", agora=liberado) == 0  # nem depois de liberado
    assert repo.saldo(PROF, liberado, "profissional") == 50
    # Outro cliente é outro bônus.
    assert (
        conceder_bonus_profissional(
            repo, profissional_id=PROF, cliente_id="cli-9", pedido_id="p9", agora=AGORA
        )
        == 50
    )


def test_bonus_cancelado_por_disputa_nao_volta_a_ser_dado_para_o_mesmo_cliente():
    repo = _repo()
    _dar(repo, "p1")
    _liberar(repo, AGORA + timedelta(days=7), "perdida")
    assert _dar(repo, "p2", agora=AGORA + timedelta(days=8)) == 0  # a chave segue ocupada


def test_chamadas_simultaneas_em_dois_contratos_so_criam_um_bonus():
    repo = _repo()
    resultados: list[int] = []
    largada = threading.Barrier(20)

    def tentar(n):
        largada.wait()
        resultados.append(_dar(repo, f"p{n}"))

    fios = [threading.Thread(target=tentar, args=(n,)) for n in range(20)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()
    assert sorted(resultados) == [0] * 19 + [50]
    assert len(repo.pendentes_do_usuario(PROF, TIPO_BONUS_PROFISSIONAL)) == 1


def test_desligado_ou_sem_valor_nao_da_bonus():
    assert _dar(MoedasEmMemoria(ConfigMoedas(ativo=False))) == 0
    assert _dar(_repo(bonus_avaliacao_profissional_moedas=0)) == 0


class _SemColunasNovas(MoedasEmMemoria):
    def criar_pendente(self, pendente):
        raise RuntimeError('column "tipo_lancamento" of relation "moedas_pendentes" does not exist')


def test_sem_as_colunas_novas_nao_credita_nem_pendura_e_nao_levanta():
    repo = _SemColunasNovas(ConfigMoedas(ativo=True))
    assert _dar(repo) == 0  # fail-closed
    assert repo.saldo(PROF, AGORA, "profissional") == 0 and repo.extrato(PROF) == []


# --- 4) liberação -----------------------------------------------------------------------------------------


def test_liberacao_so_apos_7_dias_com_lancamento_na_carteira_do_profissional():
    repo = _repo(validade_dias=90)
    _dar(repo)
    assert _liberar(repo, AGORA + timedelta(days=6, hours=23)).liberados == 0
    assert saldo_profissional(repo, PROF, AGORA + timedelta(days=6, hours=23)) == 0
    quando = AGORA + timedelta(days=7)
    assert _liberar(repo, quando).liberados == 1
    assert saldo_profissional(repo, PROF, quando) == 50
    lanc = repo.extrato(PROF, carteira="profissional")[0]
    assert (lanc.tipo, lanc.carteira, lanc.quantidade, lanc.chave_idempotencia) == (
        TIPO_BONUS_PROFISSIONAL,
        "profissional",
        50,
        CHAVE,
    )
    assert lanc.parceiro_id == CLI and lanc.expira_em == quando + timedelta(days=90)
    assert saldo_profissional(repo, PROF, quando + timedelta(days=91)) == 0  # validade


def test_liberacao_e_idempotente():
    repo = _repo()
    _dar(repo)
    quando = AGORA + timedelta(days=8)
    assert _liberar(repo, quando).liberados == 1
    assert _liberar(repo, quando).liberados == 0
    assert saldo_profissional(repo, PROF, quando) == 50
    # Ciclo que caiu depois de lançar e antes de marcar: só falta marcar, sem creditar de novo.
    outro = _repo()
    _dar(outro)
    outro.lancar(
        LancamentoMoeda(PROF, TIPO_BONUS_PROFISSIONAL, 50, CHAVE, quando, carteira="profissional")
    )
    assert _liberar(outro, quando).liberados == 1
    assert saldo_profissional(outro, PROF, quando) == 50


def _executor(amb, disputa=None, pedido=None, cobrancas=()):
    amb.contexto.disputas = SimpleNamespace(obter=lambda _id: disputa)
    if pedido is not None:
        amb.contexto.pedidos = SimpleNamespace(obter=lambda _id: pedido)
    repo_cobrancas = SimpleNamespace(do_pedido=lambda _id: list(cobrancas))
    return ExecutorContexto(amb.contexto, None, repo_cobrancas)


@pytest.mark.parametrize(
    ("estado", "divisao", "saldo", "pendentes"),
    [
        (EstadoDisputa.ABERTA, None, 0, 1),  # disputa aberta segura
        (EstadoDisputa.EM_ANALISE, None, 0, 1),
        (
            EstadoDisputa.DECIDIDA,
            SimpleNamespace(para_profissional=0, para_cliente=9, retido=0),
            0,
            0,
        ),
        (
            EstadoDisputa.DECIDIDA,
            SimpleNamespace(para_profissional=4, para_cliente=5, retido=0),
            50,
            0,
        ),
        (
            EstadoDisputa.DECIDIDA,
            SimpleNamespace(para_profissional=9, para_cliente=0, retido=0),
            50,
            0,
        ),
    ],
)
def test_rotina_segura_cancela_ou_libera_conforme_a_disputa(amb, estado, divisao, saldo, pendentes):
    amb.contexto.moedas = _repo()
    _dar(amb.contexto.moedas, "ped-1")
    exe = _executor(amb, SimpleNamespace(estado=estado, divisao=divisao))
    quando = AGORA + timedelta(days=7)
    exe.liberar_bonus_moedas(quando)
    assert saldo_profissional(amb.contexto.moedas, PROF, quando) == saldo
    assert len(amb.contexto.moedas.pendentes_do_usuario(PROF, TIPO_BONUS_PROFISSIONAL)) == pendentes


def test_pedido_estornado_ou_cancelado_nao_libera(amb):
    amb.contexto.moedas = _repo()
    _dar(amb.contexto.moedas, "ped-1")
    quando = AGORA + timedelta(days=7)
    # Estorno total (cobrança devolvida por inteiro) dentro dos 7 dias.
    devolvida = SimpleNamespace(status=EstadoCobranca.DEVOLVIDA, contrato_encerrado=False)
    exe = _executor(amb, cobrancas=[devolvida])
    exe.liberar_bonus_moedas(quando)
    assert saldo_profissional(amb.contexto.moedas, PROF, quando) == 0
    assert amb.contexto.moedas.pendentes_do_usuario(PROF, TIPO_BONUS_PROFISSIONAL) == []

    # Pedido cancelado.
    amb.contexto.moedas = _repo()
    _dar(amb.contexto.moedas, "ped-2", agora=AGORA)
    cancelado = SimpleNamespace(estado=Estado.CANCELADO)
    _executor(amb, pedido=cancelado).liberar_bonus_moedas(quando)
    assert saldo_profissional(amb.contexto.moedas, PROF, quando) == 0


def test_o_bonus_do_cliente_continua_com_a_regra_antiga(amb):
    """Disputa perdida pelo cliente (nada para ele) cancela o bônus DELE; para o profissional não."""
    from trato.api.moedas import conceder_bonus_avaliacao

    amb.contexto.moedas = _repo(dias_liberacao_bonus=7)
    conceder_bonus_avaliacao(
        amb.contexto.moedas,
        cliente_id=CLI,
        pedido_id="ped-1",
        valor_servico_centavos=10_000,
        agora=AGORA,
    )
    disputa = SimpleNamespace(
        estado=EstadoDisputa.DECIDIDA,
        divisao=SimpleNamespace(para_profissional=9, para_cliente=0, retido=0),
    )
    quando = AGORA + timedelta(days=7)
    _executor(amb, disputa).liberar_bonus_moedas(quando)
    assert amb.contexto.moedas.saldo(CLI, quando) == 0
    assert amb.contexto.moedas.pendentes_do_usuario(CLI) == []


# --- 2) a moeda de profissional nunca vira desconto ---------------------------------------------------------


def _usuario_nos_dois_papeis(prof_moedas=500, cli_moedas=0) -> MoedasEmMemoria:
    repo = _repo(
        orcamento_mensal_desconto_centavos=1_000_000,
        teto_desconto_cliente_mes_centavos=1_000_000,
        teto_diario_desconto_centavos=1_000_000,
        dias_liberacao_bonus=0,
    )
    repo.lancar(
        LancamentoMoeda(
            CLI, TIPO_BONUS_PROFISSIONAL, prof_moedas, "p:1", AGORA, carteira="profissional"
        )
    )
    if cli_moedas:
        repo.lancar(LancamentoMoeda(CLI, "bonus_avaliacao", cli_moedas, "c:1", AGORA))
    return repo


def test_moeda_de_profissional_nao_entra_no_saldo_do_desconto_conta_dual():
    repo = _usuario_nos_dois_papeis(prof_moedas=500, cli_moedas=0)
    assert repo.saldo(CLI, AGORA) == 0 and saldo_profissional(repo, CLI, AGORA) == 500
    uso = calcular_uso_moedas(repo, usuario_id=CLI, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.desconto_centavos) == (0, 0)
    with pytest.raises(DescontoMoedasIndisponivel) as erro:
        reservar_desconto(repo, cobranca_id="cob-1", moedas=100, usuario_id=CLI, agora=AGORA)
    assert erro.value.motivo == "saldo_insuficiente"  # a reserva também só vê a carteira cliente
    assert repo.orcamento_usado(AGORA.date().replace(day=1)) == 0


def test_conta_dual_desconto_usa_so_a_carteira_do_cliente():
    repo = _usuario_nos_dois_papeis(prof_moedas=500, cli_moedas=120)
    uso = calcular_uso_moedas(repo, usuario_id=CLI, servico_centavos=100_000, agora=AGORA)
    assert uso.moedas == 120  # as 500 do profissional não somam
    assert reservar_desconto(repo, cobranca_id="cob-1", moedas=120, usuario_id=CLI, agora=AGORA)
    assert saldo_profissional(repo, CLI, AGORA) == 500  # intocada


# --- 5) API: /v1/me/moedas e avaliação ---------------------------------------------------------------------------


def _avaliar(amb, token, ped):
    return amb.cliente.post(
        f"/v1/pedidos/{ped}/avaliacao", json={"nota_geral": 5}, headers=cab(token)
    )


def test_profissional_avalia_cliente_ganha_pendente_e_ve_na_carteira_dele(amb):
    amb.contexto.moedas = _repo()
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    r = _avaliar(amb, "t-prof", "ped-1")
    assert r.status_code == 201 and r.json()["moedas_ganhas"] == 50
    m = amb.cliente.get("/v1/me/moedas", headers=cab("t-prof")).json()
    assert (m["saldo"], m["saldo_profissional"], m["moedas_pendentes_profissional"]) == (0, 0, 50)
    assert m["moedas_pendentes"] == 0 and m["extrato"] == []  # o bloco do cliente não mistura

    # Depois de 7 dias sem disputa, a rotina libera e o saldo aparece só na carteira dele.
    amb.relogio.avancar(days=7)
    _executor(amb).liberar_bonus_moedas(amb.relogio.agora)
    m = amb.cliente.get("/v1/me/moedas", headers=cab("t-prof")).json()
    assert (m["saldo"], m["saldo_profissional"], m["moedas_pendentes_profissional"]) == (0, 50, 0)
    assert m["extrato"] == []


def test_segundo_contrato_do_mesmo_cliente_devolve_moedas_ganhas_zero_e_grava_a_avaliacao(amb):
    amb.contexto.moedas = _repo()
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA, id="ped-2")
    assert _avaliar(amb, "t-prof", "ped-1").json()["moedas_ganhas"] == 50
    segundo = amb.cliente.post(
        "/v1/contratos/ped-2/avaliacao", json={"nota_geral": 4}, headers=cab("t-prof")
    )
    assert segundo.status_code == 201 and segundo.json()["moedas_ganhas"] == 0
    assert amb.contexto.avaliacoes.obter("ped-2", "profissional_para_cliente") is not None
    m = amb.cliente.get("/v1/me/moedas", headers=cab("t-prof")).json()
    assert m["moedas_pendentes_profissional"] == 50  # um só


def test_avaliacao_sem_as_colunas_novas_segue_sem_erro_e_sem_credito(amb):
    amb.contexto.moedas = _SemColunasNovas(ConfigMoedas(ativo=True))
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    r = _avaliar(amb, "t-prof", "ped-1")
    assert r.status_code == 201 and r.json()["moedas_ganhas"] == 0
    assert amb.contexto.avaliacoes.obter("ped-1", "profissional_para_cliente") is not None


def test_so_pedido_concluido_da_bonus_ao_profissional(amb):
    amb.contexto.moedas = _repo()
    amb.semear_pedido(Estado.EM_ANDAMENTO)
    assert _avaliar(amb, "t-prof", "ped-1").status_code == 409
    assert amb.contexto.moedas.pendentes_do_usuario(PROF, TIPO_BONUS_PROFISSIONAL) == []


def test_cliente_avaliando_continua_recebendo_na_carteira_cliente(amb):
    amb.contexto.moedas = _repo(dias_liberacao_bonus=0)
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    assert _avaliar(amb, "t-cliente", "ped-1").json()["moedas_ganhas"] == 50
    m = amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).json()
    assert (m["saldo"], m["saldo_profissional"]) == (50, 0)


# --- fallback do Postgres sem as colunas novas (banco falso) --------------------------------------------------------


class _Con:
    def __init__(self, faltam: tuple[str, ...]) -> None:
        self.faltam = faltam
        self.sqls: list[str] = []
        self._linha: dict | None = {}

    def execute(self, sql, params=None):
        self.sqls.append(sql)
        for coluna in self.faltam:
            if coluna in sql:
                raise RuntimeError(f'column "{coluna}" does not exist')
        if "select 1" in sql:  # `existe`: nenhuma linha
            self._linha = None
            return self
        completa = {
            "total": 7,
            "ativo": True,
            "bonus_avaliacao_moedas": 50,
            "valor_moeda_centavos": 1,
            "teto_mensal_moedas": 500,
            "min_servico_centavos": 5000,
            "max_bonus_por_profissional_mes": 1,
            "max_desconto_percentual": 20,
            "validade_dias": None,
            "orcamento_mensal_desconto_centavos": 45_000,
            "aviso_percentual": 70,
            "teto_desconto_cliente_mes_centavos": 800,
            "teto_diario_desconto_centavos": 1_500,
            "dias_liberacao_bonus": 3,
            "max_reservas_abertas": 4,
            "reserva_minutos": 20,
            "bonus_avaliacao_profissional_moedas": 70,
            "exclusividade_custo_moedas": 110,
            "exclusividade_duracao_horas": 24,
            "exclusividade_max_simultaneas": 2,
            "exclusividade_prazo_resposta_horas": 5,
            "exclusividade_bloqueio_recusa_dias": 10,
        }
        pedidas = sql.split("select", 1)[-1].split(" from ", 1)[0]
        nomes = [c.strip().split(" as ")[-1] for c in pedidas.split(",")]
        # Só devolve as colunas pedidas (como o banco): `total` se for soma, senão as listadas.
        self._linha = {n: completa[n] for n in nomes if n in completa} or completa
        return self

    def fetchone(self):
        return self._linha

    def fetchall(self):
        if self.sqls[-1].startswith("select tipo, quantidade, chave_idempotencia, expira_em"):
            return [  # o saldo sai dos lançamentos: um crédito de 7 sem prazo
                {
                    "tipo": "ajuste",
                    "quantidade": 7,
                    "chave_idempotencia": "k",
                    "expira_em": None,
                    "criada_em": AGORA,
                }
            ]
        return []


class _Banco:
    def __init__(self, *faltam: str) -> None:
        self.con = _Con(faltam)

    @contextmanager
    def transacao(self):
        yield self.con


def test_config_le_as_6_colunas_novas():
    cfg = MoedasPostgres(_Banco()).config()
    assert (
        cfg.bonus_avaliacao_profissional_moedas,
        cfg.exclusividade_custo_moedas,
        cfg.exclusividade_duracao_horas,
        cfg.exclusividade_max_simultaneas,
        cfg.exclusividade_prazo_resposta_horas,
        cfg.exclusividade_bloqueio_recusa_dias,
    ) == (70, 110, 24, 2, 5, 10)


def test_config_sem_as_6_colunas_cai_nos_padroes_e_mantem_o_resto():
    cfg = MoedasPostgres(_Banco("exclusividade_custo_moedas")).config()
    assert (
        cfg.bonus_avaliacao_profissional_moedas,
        cfg.exclusividade_custo_moedas,
        cfg.exclusividade_duracao_horas,
        cfg.exclusividade_max_simultaneas,
        cfg.exclusividade_prazo_resposta_horas,
        cfg.exclusividade_bloqueio_recusa_dias,
    ) == (50, 100, 48, 3, 6, 30)
    # O que já existia de migrations anteriores segue valendo.
    assert (cfg.max_reservas_abertas, cfg.orcamento_mensal_desconto_centavos) == (4, 45_000)


def test_saldo_e_extrato_sem_a_coluna_carteira_tudo_e_do_cliente():
    banco = _Banco("carteira")
    repo = MoedasPostgres(banco)
    uid = "00000000-0000-0000-0000-000000000001"
    assert repo.saldo(uid, AGORA) == 7  # legado: soma tudo
    assert repo.saldo(uid, AGORA, "profissional") == 0
    assert repo.extrato(uid) == [] and repo.extrato(uid, carteira="profissional") == []


def test_pendentes_sem_a_coluna_tipo_lancamento_e_criar_do_profissional_falha_fechado():
    banco = _Banco("tipo_lancamento")
    repo = MoedasPostgres(banco)
    uid = "00000000-0000-0000-0000-000000000001"
    assert repo.pendentes_do_usuario(uid) == []  # legado: lê sem filtrar por tipo
    assert repo.pendentes_do_usuario(uid, TIPO_BONUS_PROFISSIONAL) == []
    assert repo.pendentes_vencidos(AGORA) == []
    banco.con.sqls.clear()
    assert (
        conceder_bonus_profissional(
            repo,
            profissional_id=uid,
            cliente_id="00000000-0000-0000-0000-000000000002",
            pedido_id="00000000-0000-0000-0000-000000000003",
            agora=AGORA,
        )
        == 0
    )  # o insert do profissional exige a coluna: nada creditado, sem exceção
    assert any("tipo_lancamento" in s and "insert" in s for s in banco.con.sqls)


def test_lancar_do_cliente_nao_depende_da_coluna_carteira():
    banco = _Banco("carteira")
    banco.con.execute = lambda sql, params=None: (
        (_ for _ in ()).throw(RuntimeError('column "carteira" does not exist'))
        if "carteira" in sql
        else SimpleNamespace(fetchone=lambda: {"id": 1})
    )
    repo = MoedasPostgres(banco)
    uid = "00000000-0000-0000-0000-000000000001"
    assert repo.lancar(LancamentoMoeda(uid, "bonus_avaliacao", 5, "k1", AGORA)) is True
    with pytest.raises(RuntimeError):  # o do profissional precisa da coluna
        repo.lancar(
            LancamentoMoeda(uid, TIPO_BONUS_PROFISSIONAL, 5, "k2", AGORA, carteira="profissional")
        )
