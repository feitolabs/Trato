# ruff: noqa: F811
"""Orçamento mensal de desconto de moedas: a empresa paga o desconto, então o backend segura o
total do mês e o que cada cliente pode usar. Esgotar não é erro: o desconto só não se aplica."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import date

from conftest import AGORA, CLIENTE
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.api.moedas import (
    ConfigMoedas,
    LancamentoMoeda,
    MoedasEmMemoria,
    calcular_uso_moedas,
    debitar_uso_moedas,
    devolver_uso_moedas,
    dia_ref,
    disponibilidade_desconto,
    mes_ref,
    volta_em,
)
from trato.pagamentos.provedor import TipoEvento

MES = date(2026, 10, 1)  # AGORA (29/10/2026 12:00 UTC) cai em outubro, no horário de Brasília
DIA = date(2026, 10, 29)


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


def _ligar(fluxo: Fluxo, saldo=5_000, **cfg) -> MoedasEmMemoria:
    fluxo.ctx.moedas = _repo(saldo, **cfg)
    return fluxo.ctx.moedas


def _cobrar(fluxo: Fluxo, pid, usar_moedas=True):
    return fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        {"meio": "pix", "usar_moedas": usar_moedas},
    )


def _pagar(fluxo: Fluxo, cobranca_id: str):
    fluxo.fake.marcar_paga(cobranca_id)
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca_id).status_code == 200


# --- regra pura -------------------------------------------------------------------------------


def test_mes_ref_e_o_primeiro_dia_no_horario_de_brasilia():
    assert mes_ref(AGORA) == MES
    # 01/11 02:00 UTC ainda é 31/10 23:00 em Brasília: continua outubro.
    assert mes_ref(AGORA.replace(month=11, day=1, hour=2)) == MES
    assert mes_ref(AGORA.replace(month=11, day=1, hour=3)) == date(2026, 11, 1)


def test_orcamento_esgotado_nao_e_erro_e_guarda_as_moedas():
    repo = _repo(orcamento_mensal_desconto_centavos=300)
    assert (
        repo.reservar_orcamento(MES, DIA, 300, 300, 1_000_000_000) == "ok"
    )  # o mês chegou ao fim do orçamento
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.desconto_centavos) == (0, 0)
    assert uso.disponivel is False and uso.motivo == "orcamento_esgotado"
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000  # moedas intactas


def test_teto_por_cliente_soma_uso_menos_estorno():
    repo = _repo(teto_desconto_cliente_mes_centavos=500)
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.disponivel) == (500, True)  # capado no teto do cliente, não no saldo
    kw = {"usuario_id": CLIENTE.id, "pedido_id": "p", "agora": AGORA}
    debitar_uso_moedas(repo, cobranca_id="c1", moedas=500, **kw)
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.disponivel, uso.motivo) == (0, False, "teto_cliente")
    devolver_uso_moedas(repo, cobranca_id="c1", moedas=500, **kw)  # estorno libera o teto de volta
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.disponivel) == (500, True)


def test_teto_de_um_cliente_nao_afeta_outro():
    repo = _repo(teto_desconto_cliente_mes_centavos=500)
    debitar_uso_moedas(
        repo, usuario_id=CLIENTE.id, cobranca_id="c1", pedido_id="p", moedas=500, agora=AGORA
    )
    outro = "outro-cliente"
    repo.lancar(LancamentoMoeda(outro, "bonus_avaliacao", 1_000, "bonus:o", AGORA))
    assert disponibilidade_desconto(repo, usuario_id=outro, agora=AGORA).disponivel is True


def test_mes_novo_reabre_orcamento_e_teto():
    repo = _repo(orcamento_mensal_desconto_centavos=500, teto_desconto_cliente_mes_centavos=500)
    repo.reservar_orcamento(MES, DIA, 500, 500, 1_000_000_000)
    debitar_uso_moedas(
        repo, usuario_id=CLIENTE.id, cobranca_id="c1", pedido_id="p", moedas=500, agora=AGORA
    )
    assert disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=AGORA).disponivel is False
    novembro = AGORA.replace(month=11, day=3)
    disp = disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=novembro)
    assert disp.disponivel is True and repo.orcamento_usado(date(2026, 11, 1)) == 0
    assert repo.orcamento_usado(MES) == 500  # o mês antigo não muda


def test_reserva_simultanea_nunca_estoura_o_orcamento():
    repo = _repo()
    resultados: list[bool] = []
    largada = threading.Barrier(40)

    def tentar():
        largada.wait()
        resultados.append(repo.reservar_orcamento(MES, DIA, 100, 1_000, 1_000_000_000) == "ok")

    fios = [threading.Thread(target=tentar) for _ in range(40)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()
    assert sum(resultados) == 10  # 10 x R$ 1,00 cabem em R$ 10,00; os outros 30 são recusados
    assert repo.orcamento_usado(MES) == 1_000


def test_devolver_reserva_nunca_fica_abaixo_de_zero():
    repo = _repo()
    repo.reservar_orcamento(MES, DIA, 200, 1_000, 1_000_000_000)
    assert repo.devolver_orcamento(MES, DIA, 500) == 0
    assert repo.orcamento_usado(MES) == 0


# --- fluxo HTTP (cobrança, webhook, estorno) --------------------------------------------------


def test_simulacao_mostra_disponibilidade_sem_reservar(fluxo: Fluxo):
    repo = _ligar(fluxo, orcamento_mensal_desconto_centavos=300)
    pid = fluxo.aceitar()
    previa = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?usar_moedas=true", "t-cliente"
    ).json()
    assert previa["desconto_disponivel"] is True and previa["desconto_indisponivel_motivo"] is None
    assert previa["moedas_usadas"] == 300  # capado no que sobra do orçamento
    assert repo.orcamento_usado(MES) == 0  # simulação não reserva nada

    repo.reservar_orcamento(MES, DIA, 300, 300, 1_000_000_000)
    previa = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?usar_moedas=true", "t-cliente"
    ).json()
    assert previa["desconto_disponivel"] is False
    assert previa["desconto_indisponivel_motivo"] == "orcamento_esgotado"
    assert previa["moedas_usadas"] == 0 and previa["total_a_pagar_centavos"] == 100_000
    sem = fluxo.chamar("GET", f"/v1/pedidos/{pid}/pagamento", "t-cliente").json()
    assert sem["desconto_disponivel"] is False  # o app sabe mesmo sem pedir as moedas


def test_me_moedas_devolve_disponibilidade(fluxo: Fluxo):
    repo = _ligar(fluxo, teto_desconto_cliente_mes_centavos=500)
    r = fluxo.chamar("GET", "/v1/me/moedas", "t-cliente").json()
    assert r["desconto_disponivel"] is True and r["desconto_indisponivel_motivo"] is None
    debitar_uso_moedas(
        repo, usuario_id=CLIENTE.id, cobranca_id="c1", pedido_id="p", moedas=500, agora=AGORA
    )
    r = fluxo.chamar("GET", "/v1/me/moedas", "t-cliente").json()
    assert r["desconto_disponivel"] is False and r["desconto_indisponivel_motivo"] == "teto_cliente"
    repo.salvar_config(replace(repo.config(), orcamento_mensal_desconto_centavos=0))
    r = fluxo.chamar("GET", "/v1/me/moedas", "t-cliente").json()
    assert r["desconto_indisponivel_motivo"] == "orcamento_esgotado"  # orçamento vale primeiro


def test_cobranca_reserva_o_desconto_no_orcamento(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    r = _cobrar(fluxo, pid)
    assert r.status_code == 201, r.text
    cob = r.json()
    assert cob["valor_centavos"] == 95_000 and cob["desconto_disponivel"] is True
    assert repo.orcamento_usado(MES) == 5_000  # reservado já na criação
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000  # moedas só saem na confirmação
    _pagar(fluxo, cob["cobranca_id"])
    assert repo.orcamento_usado(MES) == 5_000  # a reserva vira consumo: continua lá
    assert repo.saldo(CLIENTE.id, AGORA) == 0


def test_cobranca_com_orcamento_esgotado_sai_sem_desconto_e_sem_erro(fluxo: Fluxo):
    repo = _ligar(fluxo, orcamento_mensal_desconto_centavos=300)
    repo.reservar_orcamento(MES, DIA, 300, 300, 1_000_000_000)
    pid = fluxo.aceitar()
    r = _cobrar(fluxo, pid)
    assert r.status_code == 201, r.text
    cob = r.json()
    assert cob["valor_centavos"] == 100_000
    assert cob["desconto_disponivel"] is False
    assert cob["desconto_indisponivel_motivo"] == "orcamento_esgotado"
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000
    assert repo.orcamento_usado(MES) == 300  # nada foi reservado a mais


def test_corrida_na_reserva_cai_sem_desconto(fluxo: Fluxo):
    """Outro pagamento levou o orçamento entre a conta e a reserva: sai sem desconto."""
    repo = _ligar(fluxo)
    repo.reservar_desconto = lambda *a, **k: (
        "orcamento_esgotado"
    )  # a reserva atômica perdeu a corrida
    pid = fluxo.aceitar()
    r = _cobrar(fluxo, pid)
    assert r.status_code == 201, r.text
    cob = r.json()
    assert cob["valor_centavos"] == 100_000
    assert cob["desconto_disponivel"] is False
    assert cob["desconto_indisponivel_motivo"] == "orcamento_esgotado"


def test_cobranca_repetida_nao_reserva_duas_vezes(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    a = _cobrar(fluxo, pid).json()
    b = _cobrar(fluxo, pid).json()
    assert a["cobranca_id"] == b["cobranca_id"]
    assert repo.orcamento_usado(MES) == 5_000
    _pagar(fluxo, a["cobranca_id"])
    # Reentrega do webhook: nada muda no orçamento.
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, a["cobranca_id"]).status_code == 200
    assert repo.orcamento_usado(MES) == 5_000


def test_cobranca_que_falha_devolve_a_reserva_uma_vez(fluxo: Fluxo):
    repo = _ligar(fluxo)
    repo.reservar_orcamento(
        MES, DIA, 700, 1_000_000, 1_000_000_000
    )  # reserva de outro cliente: não pode ser tocada
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    assert repo.orcamento_usado(MES) == 5_700
    assert fluxo.webhook(TipoEvento.PAGAMENTO_FALHOU, cob["cobranca_id"]).status_code == 200
    assert repo.orcamento_usado(MES) == 700
    assert fluxo.webhook(TipoEvento.PAGAMENTO_FALHOU, cob["cobranca_id"]).status_code == 200
    assert repo.orcamento_usado(MES) == 700  # a segunda falha não devolve de novo


def test_cobranca_substituida_devolve_a_reserva_antiga(fluxo: Fluxo):
    """Trocar de moedas para sem moedas cancela a cobrança pendente e devolve a reserva dela."""
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    _cobrar(fluxo, pid, usar_moedas=True)
    assert repo.orcamento_usado(MES) == 5_000
    r = _cobrar(fluxo, pid, usar_moedas=False)
    assert r.status_code == 201 and r.json()["valor_centavos"] == 100_000
    assert repo.orcamento_usado(MES) == 0


def test_estorno_total_devolve_a_reserva_e_parcial_so_as_moedas_na_proporcao(fluxo: Fluxo):
    repo = _ligar(fluxo)
    repo.reservar_orcamento(MES, DIA, 700, 1_000_000, 1_000_000_000)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    _pagar(fluxo, cob["cobranca_id"])
    assert repo.orcamento_usado(MES) == 5_700

    paga = fluxo.servico.cobrancas.obter(cob["cobranca_id"])
    parcial = replace(paga, estornado_centavos=paga.valor_centavos - 1)
    fluxo.servico._devolver_moedas(fluxo.ctx, parcial)
    assert repo.orcamento_usado(MES) == 5_700  # parcial não devolve a reserva
    assert repo.saldo(CLIENTE.id, AGORA) == 4_999  # as moedas, na proporção (13.8)

    total = replace(paga, estornado_centavos=paga.valor_centavos)
    fluxo.servico._devolver_moedas(fluxo.ctx, total)
    assert repo.orcamento_usado(MES) == 700
    fluxo.servico._devolver_moedas(fluxo.ctx, total)  # idempotente
    assert repo.orcamento_usado(MES) == 700
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000


def test_pedido_cancelado_devolve_a_reserva_da_cobranca_pendente(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    _cobrar(fluxo, pid)
    assert repo.orcamento_usado(MES) == 5_000
    r = fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "desisti do serviço"})
    assert r.status_code == 200, r.text
    assert repo.orcamento_usado(MES) == 0


# --- teto diário ------------------------------------------------------------------------------


def test_dia_ref_e_a_data_em_brasilia():
    assert dia_ref(AGORA) == DIA
    # 30/10 02:00 UTC ainda é 29/10 23:00 em Brasília; às 03:00 UTC vira o dia 30.
    assert dia_ref(AGORA.replace(day=30, hour=2)) == DIA
    assert dia_ref(AGORA.replace(day=30, hour=3)) == date(2026, 10, 30)


def test_limite_diario_vale_antes_do_teto_do_cliente_e_volta_amanha():
    repo = _repo(orcamento_mensal_desconto_centavos=30_000, teto_diario_desconto_centavos=1_000)
    assert repo.reservar_orcamento(MES, DIA, 1_000, 30_000, 1_000) == "ok"  # o dia fechou
    disp = disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=AGORA)
    assert (disp.disponivel, disp.motivo) == (False, "limite_diario")
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.disponivel, uso.motivo) == (0, False, "limite_diario")
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000  # moedas guardadas
    amanha = AGORA.replace(day=30)  # mesmo mês, dia novo
    assert disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=amanha).disponivel is True
    assert repo.orcamento_usado(MES) == 1_000  # o mês continua contando o que já saiu


def test_orcamento_do_mes_ganha_do_dia_quando_os_dois_acabaram():
    repo = _repo(orcamento_mensal_desconto_centavos=1_000, teto_diario_desconto_centavos=1_000)
    repo.reservar_orcamento(MES, DIA, 1_000, 1_000, 1_000)
    disp = disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=AGORA)
    assert disp.motivo == "orcamento_esgotado"


def test_reserva_diz_o_motivo_e_nao_muda_nada_quando_nega():
    repo = _repo()
    assert repo.reservar_orcamento(MES, DIA, 900, 5_000, 1_000) == "ok"
    assert repo.reservar_orcamento(MES, DIA, 200, 5_000, 1_000) == "limite_diario"
    assert (repo.orcamento_usado(MES), repo.orcamento_usado_dia(DIA)) == (900, 900)
    outro_dia = date(2026, 10, 30)
    assert repo.reservar_orcamento(MES, outro_dia, 4_200, 5_000, 5_000) == "orcamento_esgotado"
    # Negar no mês não pode deixar o dia reservado.
    assert (repo.orcamento_usado(MES), repo.orcamento_usado_dia(outro_dia)) == (900, 0)


def test_reserva_simultanea_respeita_o_dia_e_o_mes_juntos():
    repo = _repo()
    resultados: list[str] = []
    largada = threading.Barrier(40)

    def tentar():
        largada.wait()
        resultados.append(repo.reservar_orcamento(MES, DIA, 100, 10_000, 1_500))

    fios = [threading.Thread(target=tentar) for _ in range(40)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()
    assert resultados.count("ok") == 15  # o teto do dia (R$ 15) manda
    assert repo.orcamento_usado_dia(DIA) == 1_500 and repo.orcamento_usado(MES) == 1_500


def test_devolucao_volta_mes_e_dia():
    repo = _repo()
    repo.reservar_orcamento(MES, DIA, 800, 10_000, 10_000)
    assert repo.devolver_orcamento(MES, DIA, 300) == 500
    assert (repo.orcamento_usado(MES), repo.orcamento_usado_dia(DIA)) == (500, 500)
    repo.devolver_orcamento(MES, DIA, 9_999)  # nunca abaixo de zero
    assert (repo.orcamento_usado(MES), repo.orcamento_usado_dia(DIA)) == (0, 0)


def test_estorno_total_devolve_mes_e_dia_da_cobranca(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    assert (repo.orcamento_usado(MES), repo.orcamento_usado_dia(DIA)) == (5_000, 5_000)
    _pagar(fluxo, cob["cobranca_id"])
    paga = fluxo.servico.cobrancas.obter(cob["cobranca_id"])
    # O estorno chega 2 dias depois: devolve no dia/mês em que a cobrança nasceu, não no de hoje.
    fluxo.amb.relogio.avancar(days=2)
    fluxo.servico._devolver_moedas(fluxo.ctx, replace(paga, estornado_centavos=paga.valor_centavos))
    assert (repo.orcamento_usado(MES), repo.orcamento_usado_dia(DIA)) == (0, 0)


def test_cobranca_no_limite_diario_sai_sem_desconto(fluxo: Fluxo):
    repo = _ligar(fluxo, teto_diario_desconto_centavos=1_000)
    repo.reservar_orcamento(MES, DIA, 1_000, 1_000_000, 1_000)
    pid = fluxo.aceitar()
    previa = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?usar_moedas=true", "t-cliente"
    ).json()
    assert previa["desconto_indisponivel_motivo"] == "limite_diario"
    cob = _cobrar(fluxo, pid).json()
    assert cob["valor_centavos"] == 100_000
    assert (cob["desconto_disponivel"], cob["desconto_indisponivel_motivo"]) == (
        False,
        "limite_diario",
    )
    assert repo.orcamento_usado_dia(DIA) == 1_000
    r = fluxo.chamar("GET", "/v1/me/moedas", "t-cliente").json()
    assert r["desconto_indisponivel_motivo"] == "limite_diario"


def test_orcamento_indisponivel_no_banco_nao_derruba_e_nao_da_desconto():
    """Migration ainda não aplicada (ou banco fora): sem desconto, sem erro."""

    class SemTabela(MoedasEmMemoria):
        def orcamento_usado(self, mes):
            raise RuntimeError("relation moedas_orcamento_mensal does not exist")

    repo = SemTabela(ConfigMoedas(ativo=True))
    disp = disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=AGORA)
    assert (disp.disponivel, disp.motivo) == (False, "orcamento_esgotado")


# --- quando volta e quanto seria o desconto ---------------------------------------------------


def test_volta_em_para_cada_motivo():
    repo = _repo()
    assert disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=AGORA).volta_em is None

    diario = _repo(teto_diario_desconto_centavos=100)
    diario.reservar_orcamento(MES, DIA, 100, 1_000_000, 100)
    d = disponibilidade_desconto(diario, usuario_id=CLIENTE.id, agora=AGORA)
    assert (d.motivo, d.volta_em) == ("limite_diario", date(2026, 10, 30))  # amanhã

    mensal = _repo(orcamento_mensal_desconto_centavos=100)
    mensal.reservar_orcamento(MES, DIA, 100, 100, 1_000_000)
    d = disponibilidade_desconto(mensal, usuario_id=CLIENTE.id, agora=AGORA)
    assert (d.motivo, d.volta_em) == ("orcamento_esgotado", date(2026, 11, 1))  # 1º do próximo mês

    teto = _repo(teto_desconto_cliente_mes_centavos=100)
    debitar_uso_moedas(
        teto, usuario_id=CLIENTE.id, cobranca_id="c1", pedido_id="p", moedas=100, agora=AGORA
    )
    d = disponibilidade_desconto(teto, usuario_id=CLIENTE.id, agora=AGORA)
    assert (d.motivo, d.volta_em) == ("teto_cliente", date(2026, 11, 1))


def test_volta_em_usa_a_data_de_brasilia_e_vira_o_ano():
    assert volta_em("limite_diario", AGORA.replace(day=30, hour=2)) == date(
        2026, 10, 30
    )  # ainda 29/10
    assert volta_em("limite_diario", AGORA.replace(day=30, hour=3)) == date(2026, 10, 31)
    assert volta_em("teto_cliente", AGORA.replace(month=12, day=15)) == date(2027, 1, 1)
    assert volta_em(None, AGORA) is None


def _possivel(repo, servico=100_000, **kw):
    return calcular_uso_moedas(
        repo, usuario_id=CLIENTE.id, servico_centavos=servico, agora=AGORA, **kw
    ).desconto_centavos


def test_possivel_respeita_o_saldo():
    assert _possivel(_repo(saldo=1_234)) == 1_234


def test_possivel_respeita_o_percentual_maximo_por_pedido():
    repo = _repo(saldo=50_000, max_desconto_percentual=20)
    assert _possivel(repo) == 20_000  # 20% de R$ 1.000,00
    assert _possivel(repo, servico=5_000) == 1_000


def test_possivel_respeita_o_teto_do_cliente_no_mes():
    repo = _repo(saldo=50_000, teto_desconto_cliente_mes_centavos=800)
    assert _possivel(repo) == 800
    debitar_uso_moedas(
        repo, usuario_id=CLIENTE.id, cobranca_id="c1", pedido_id="p", moedas=500, agora=AGORA
    )
    assert _possivel(repo) == 300  # sobrou R$ 3,00 do teto do cliente


def test_possivel_respeita_o_teto_diario():
    repo = _repo(saldo=50_000, teto_diario_desconto_centavos=1_000)
    assert _possivel(repo) == 1_000
    repo.reservar_orcamento(MES, DIA, 400, 1_000_000, 1_000)  # outro cliente já levou R$ 4,00 hoje
    assert _possivel(repo) == 600


def test_possivel_respeita_o_orcamento_do_mes():
    repo = _repo(saldo=50_000, orcamento_mensal_desconto_centavos=500)
    assert _possivel(repo) == 500
    repo.reservar_orcamento(MES, DIA, 100, 500, 1_000_000)
    assert _possivel(repo) == 400


def test_possivel_e_zero_quando_indisponivel_e_nunca_reserva():
    repo = _repo(saldo=50_000, orcamento_mensal_desconto_centavos=500)
    antes = (repo.orcamento_usado(MES), repo.orcamento_usado_dia(DIA))
    assert _possivel(repo) == 500  # só calcula
    assert (repo.orcamento_usado(MES), repo.orcamento_usado_dia(DIA)) == antes
    repo.reservar_orcamento(MES, DIA, 500, 500, 1_000_000)
    assert _possivel(repo) == 0


def test_simulacao_http_traz_possivel_e_volta_em(fluxo: Fluxo):
    repo = _ligar(fluxo, teto_diario_desconto_centavos=1_000)
    pid = fluxo.aceitar()
    # Interruptor desligado: o app já sabe quanto poderia abater, e nada é aplicado nem reservado.
    previa = fluxo.chamar("GET", f"/v1/pedidos/{pid}/pagamento", "t-cliente").json()
    assert previa["desconto_possivel_centavos"] == 1_000  # o teto do dia manda (saldo 5.000)
    assert previa["moedas_usadas"] == 0 and previa["total_a_pagar_centavos"] == 100_000
    assert previa["desconto_disponivel"] is True and previa["desconto_volta_em"] is None
    assert repo.orcamento_usado(MES) == 0
    ligada = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?usar_moedas=true", "t-cliente"
    ).json()
    assert ligada["desconto_possivel_centavos"] == ligada["moedas_desconto_centavos"] == 1_000

    repo.reservar_orcamento(MES, DIA, 1_000, 1_000_000, 1_000)
    previa = fluxo.chamar("GET", f"/v1/pedidos/{pid}/pagamento", "t-cliente").json()
    assert previa["desconto_possivel_centavos"] == 0
    assert previa["desconto_indisponivel_motivo"] == "limite_diario"
    assert previa["desconto_volta_em"] == "2026-10-30"
    me = fluxo.chamar("GET", "/v1/me/moedas", "t-cliente").json()
    assert me["desconto_volta_em"] == "2026-10-30"
    cob = _cobrar(fluxo, pid).json()
    assert cob["desconto_volta_em"] == "2026-10-30" and cob["desconto_possivel_centavos"] == 0
