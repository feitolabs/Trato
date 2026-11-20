# ruff: noqa: F811
"""Reserva de desconto POR COBRANÇA (`moedas_reservas`): orçamento do mês e do dia, teto do cliente
e saldo reservados juntos; devolução pelo valor gravado, uma vez só; expiração no agendador."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import timedelta

from conftest import AGORA, CLIENTE
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.agendador.executor import ExecutorContexto
from trato.api.moedas import (
    ConfigMoedas,
    DescontoMoedasIndisponivel,
    LancamentoMoeda,
    MoedasEmMemoria,
    calcular_uso_moedas,
    chave_reserva,
    devolver_reserva_desconto,
    dia_ref,
    disponibilidade_desconto,
    expirar_reservas_moedas,
    mes_ref,
    reservar_desconto,
)
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.provedor import TipoEvento

MES = mes_ref(AGORA)
DIA = dia_ref(AGORA)


def _repo(saldo=5_000, **cfg) -> MoedasEmMemoria:
    cfg = {
        "orcamento_mensal_desconto_centavos": 1_000_000,
        "teto_desconto_cliente_mes_centavos": 1_000_000,
        "teto_diario_desconto_centavos": 1_000_000,
        "dias_liberacao_bonus": 0,
        "valor_moeda_centavos": 1,
        **cfg,
    }
    repo = MoedasEmMemoria(ConfigMoedas(ativo=True, **cfg))
    if saldo:
        repo.lancar(LancamentoMoeda(CLIENTE.id, "bonus_avaliacao", saldo, "bonus:t", AGORA))
    return repo


def _reservar(repo, cobranca, moedas, usuario=CLIENTE.id, agora=AGORA):
    try:
        reservar_desconto(
            repo, cobranca_id=cobranca, moedas=moedas, usuario_id=usuario, agora=agora
        )
    except DescontoMoedasIndisponivel as erro:
        return erro.motivo
    return "ok"


def _ligar(fluxo: Fluxo, saldo=5_000, **cfg) -> MoedasEmMemoria:
    fluxo.ctx.moedas = _repo(saldo, **cfg)
    return fluxo.ctx.moedas


def _cobrar(fluxo: Fluxo, pid):
    return fluxo.chamar(
        "POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix", "usar_moedas": True}
    )


def _pagar(fluxo: Fluxo, cobranca_id: str):
    fluxo.fake.marcar_paga(cobranca_id)
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca_id).status_code == 200


# --- A1: reserva atômica de saldo, teto e limite de reservas ----------------------------------------


def test_duas_cobrancas_pendentes_com_o_mesmo_saldo_so_uma_reserva_ok():
    repo = _repo(saldo=5_000)
    assert _reservar(repo, "cob-a", 5_000) == "ok"
    assert _reservar(repo, "cob-b", 5_000) == "saldo_insuficiente"
    assert repo.orcamento_usado(MES) == 5_000  # a negada não deixou nada reservado
    assert _reservar(repo, "cob-a", 5_000) == "ok"  # repetir a mesma cobrança: ja_reservada = ok
    assert repo.orcamento_usado(MES) == 5_000


def test_reserva_simultanea_do_mesmo_saldo_nunca_passa_de_uma():
    repo = _repo(saldo=5_000, max_reservas_abertas=50)
    resultados: list[str] = []
    largada = threading.Barrier(20)

    def tentar(n):
        largada.wait()
        resultados.append(_reservar(repo, f"cob-{n}", 5_000))

    fios = [threading.Thread(target=tentar, args=(n,)) for n in range(20)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()
    assert resultados.count("ok") == 1 and set(resultados) <= {"ok", "saldo_insuficiente"}
    assert repo.orcamento_usado(MES) == 5_000


def test_teto_do_cliente_com_dois_pedidos_simultaneos():
    repo = _repo(saldo=10_000, teto_desconto_cliente_mes_centavos=800)
    resultados: list[str] = []
    largada = threading.Barrier(2)

    def tentar(n):
        largada.wait()
        resultados.append(_reservar(repo, f"cob-{n}", 500))

    fios = [threading.Thread(target=tentar, args=(n,)) for n in (1, 2)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()
    assert sorted(resultados) == ["ok", "teto_cliente"]  # 2 x R$ 5,00 não cabem em R$ 8,00
    assert repo.orcamento_usado(MES) == 500


def test_limite_de_reservas_abertas():
    repo = _repo(saldo=10_000, max_reservas_abertas=2)
    assert [_reservar(repo, f"c{n}", 100) for n in (1, 2, 3)] == ["ok", "ok", "reservas_abertas"]
    disp = disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=AGORA)
    assert (disp.disponivel, disp.motivo, disp.volta_em) == (False, "reservas_abertas", None)
    # Confirmar o pagamento de uma libera a vaga (deixa de ser "aberta").
    assert repo.confirmar_reserva(chave_reserva("c1")) is True
    assert _reservar(repo, "c3", 100) == "ok"


def test_simulacao_ve_o_saldo_preso_em_outra_cobranca():
    repo = _repo(saldo=5_000)
    assert _reservar(repo, "cob-a", 5_000) == "ok"
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.disponivel, uso.motivo) == (0, False, "saldo_insuficiente")
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000  # o saldo em si só sai no pagamento
    # A mesma cobrança (do mesmo pedido) é ignorada pela simulação.
    uso = calcular_uso_moedas(
        repo,
        usuario_id=CLIENTE.id,
        servico_centavos=100_000,
        agora=AGORA,
        ignorar={chave_reserva("cob-a")},
    )
    assert (uso.moedas, uso.disponivel) == (5_000, True)


def test_reserva_falha_no_armazenamento_nao_da_desconto_nem_erro():
    class SemTabela(MoedasEmMemoria):
        def reservar_desconto(self, *a, **k):
            raise RuntimeError("function public.moedas_reservar_desconto does not exist")

    repo = SemTabela(ConfigMoedas(ativo=True))
    assert _reservar(repo, "cob-a", 100) == "orcamento_esgotado"  # fail-closed: nada reservado
    assert repo.orcamento_usado(MES) == 0


def test_fluxo_http_sem_a_tabela_sai_sem_desconto(fluxo: Fluxo):
    repo = _ligar(fluxo)

    def quebrar(*a, **k):
        raise RuntimeError("sem tabela")

    repo.reservar_desconto = quebrar
    pid = fluxo.aceitar()
    r = _cobrar(fluxo, pid)
    assert r.status_code == 201, r.text
    cob = r.json()
    assert cob["valor_centavos"] == 100_000 and cob["desconto_disponivel"] is False
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000  # nada creditado, nada gasto


# --- A3/A4: devolução pelo valor gravado, uma vez só --------------------------------------------------


def test_devolver_reserva_e_idempotente_e_usa_o_valor_gravado():
    repo = _repo(valor_moeda_centavos=1)
    assert _reservar(repo, "cob-a", 1_000) == "ok"
    repo.salvar_config(replace(repo.config(), valor_moeda_centavos=3))  # a moeda mudou de valor
    assert devolver_reserva_desconto(repo, cobranca_id="cob-a") == 1_000  # o gravado, não 3.000
    assert devolver_reserva_desconto(repo, cobranca_id="cob-a") == 0  # segunda vez: nada
    assert devolver_reserva_desconto(repo, cobranca_id="nunca-existiu") == 0
    assert repo.orcamento_usado(MES) == 0


def test_mudar_valor_da_moeda_com_cobranca_pendente_devolve_o_valor_gravado(fluxo: Fluxo):
    repo = _ligar(fluxo)
    repo.reservar_orcamento(MES, DIA, 700, 1_000_000, 1_000_000)  # uso de outros clientes
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    assert repo.orcamento_usado(MES) == 5_700
    repo.salvar_config(replace(repo.config(), valor_moeda_centavos=4))
    assert fluxo.webhook(TipoEvento.PAGAMENTO_FALHOU, cob["cobranca_id"]).status_code == 200
    assert repo.orcamento_usado(MES) == 700  # voltou 5.000 (o gravado), não 20.000


def test_estorno_total_duplicado_devolve_uma_vez_so(fluxo: Fluxo):
    repo = _ligar(fluxo)
    repo.reservar_orcamento(MES, DIA, 700, 1_000_000, 1_000_000)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    _pagar(fluxo, cob["cobranca_id"])
    assert repo.orcamento_usado(MES) == 5_700
    paga = fluxo.servico.cobrancas.obter(cob["cobranca_id"])
    total = replace(paga, estornado_centavos=paga.valor_centavos)
    fluxo.servico._devolver_moedas(fluxo.ctx, total)
    fluxo.servico._devolver_moedas(fluxo.ctx, total)  # webhook de estorno reentregue
    assert repo.orcamento_usado(MES) == 700
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000


def test_pagamento_confirma_a_reserva_e_ela_sai_da_lista_de_abertas(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    assert len(repo.reservas_abertas_do_usuario(CLIENTE.id)) == 1
    _pagar(fluxo, cob["cobranca_id"])
    assert repo.reservas_abertas_do_usuario(CLIENTE.id) == []
    assert repo.saldo(CLIENTE.id, AGORA) == 0
    # Falha tardia depois de paga não devolve nada.
    fluxo.webhook(TipoEvento.PAGAMENTO_FALHOU, cob["cobranca_id"])
    assert repo.orcamento_usado(MES) == 5_000


# --- A2: expiração -------------------------------------------------------------------------------------


def test_expiracao_devolve_a_reserva_e_cancela_a_cobranca(fluxo: Fluxo):
    repo = _ligar(fluxo, reserva_minutos=30)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    rotina = ExecutorContexto(fluxo.ctx, None, fluxo.servico.cobrancas)

    fluxo.amb.relogio.avancar(minutes=31)  # dentro da margem de 2 min
    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 0  # ainda vale
    assert repo.orcamento_usado(MES) == 5_000

    fluxo.amb.relogio.avancar(minutes=4)  # 33 min: passou de 30 + 2 de margem
    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 1
    assert fluxo.servico.cobrancas.obter(cob["cobranca_id"]).status is EstadoCobranca.CANCELADA
    assert repo.orcamento_usado(MES) == 0
    assert repo.reservas_abertas_do_usuario(CLIENTE.id) == []
    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 0  # idempotente
    # O saldo livre voltou: dá para pedir o desconto de novo.
    nova = _cobrar(fluxo, pid)
    assert nova.status_code == 201 and nova.json()["valor_centavos"] == 95_000


def test_expiracao_nao_mexe_em_reserva_ja_paga(fluxo: Fluxo):
    repo = _ligar(fluxo, reserva_minutos=30)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    _pagar(fluxo, cob["cobranca_id"])
    fluxo.amb.relogio.avancar(hours=2)
    rotina = ExecutorContexto(fluxo.ctx, None, fluxo.servico.cobrancas)
    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 0
    assert repo.orcamento_usado(MES) == 5_000
    assert fluxo.servico.cobrancas.obter(cob["cobranca_id"]).status is EstadoCobranca.PAGA


def test_expiracao_sem_a_tabela_nao_quebra_o_ciclo():
    class SemTabela(MoedasEmMemoria):
        def expirar_reservas(self, agora):
            raise RuntimeError('relation "public.moedas_reservas" does not exist')

    assert expirar_reservas_moedas(SemTabela(), object(), AGORA + timedelta(days=1)) == 0
