"""TERMOS-M2: conclusão por prazo move o dinheiro (5.8), aditivo pago depois do cancelamento,
reembolso integral com o parcelado (7.7), reenvio seguro de estornos (6.10) e contestação
perdida (6.11). Memória e provedor falso."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import timedelta

import pytest
from conftest import AGORA, PROFISSIONAL
from test_ausencia_profissional_reembolso import (
    ADITIVO,
    aditivo_aprovado,
    estornos_no_provedor,
    pedido_pago_e_agendado,
    vencer_a_tolerancia,
)
from test_fluxo_pagamento_e2e import VALOR, Fluxo, fluxo  # noqa: F401 - `fluxo` é fixture

from trato.agendador import Agendador
from trato.agendador.executor import ExecutorContexto, FonteContexto, ids_ativos_memoria
from trato.agendador.registro import RegistroEmMemoria
from trato.agendador.trava import TravaEmMemoria
from trato.financeiro.ledger import (
    CUSTODIA,
    TAXA_TRATO,
    Livro,
    TipoLancamento,
    a_liberar,
    liberar,
    reembolso_total_com_custo,
    registrar_cobranca,
    repartir_custodia,
    separar_custo_parcelamento,
)
from trato.pagamentos.modelos import ConfigPagamento, EstadoCobranca
from trato.pagamentos.parcelamento import ConfigParcelamento
from trato.pagamentos.provedor import ErroProvedor, TipoEvento
from trato.pedidos.estados import Acao, Estado
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

MINUTOS_2 = timedelta(minutes=2)


def agendador(f: Fluxo) -> Agendador:
    executor = ExecutorContexto(
        f.ctx, cobrancas=f.servico.cobrancas, provedor=f.fake, pagamento=f.servico
    )
    trava = type("TravaLivre", (TravaEmMemoria,), {"_ocupadas": set()})()
    return Agendador(
        FonteContexto(f.ctx, ids_ativos_memoria(f.ctx)),
        executor,
        RegistroEmMemoria(),
        trava,
        f.amb.relogio,
        rotina_estornos=executor.reenviar_estornos,
    )


def por_prazo(pid: str) -> AcaoRotina:
    return AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"prazo:{pid}", acao=Acao.CONCLUIR_POR_PRAZO
    )


def custodia(f: Fluxo, pid: str) -> int:
    return f.ctx.ledger.saldo_da_conta(CUSTODIA, pid)


def revisoes(f: Fluxo) -> list[str]:
    return [m for e, m in f.ctx.eventos_webhook.em_revisao() if e.evento_id.startswith("trato-")]


# --- 1) 5.8: conclusão por prazo ----------------------------------------------------------------


def test_conclusao_por_prazo_move_o_dinheiro_como_a_confirmacao(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.amb.relogio.avancar(days=8)
    for _ in range(2):
        assert agendador(fluxo).rodar_uma_vez().falhas == 0
    ExecutorContexto(fluxo.ctx).executar(por_prazo(pid), fluxo.amb.relogio.agora)

    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CONCLUIDO
    assert custodia(fluxo, pid) == 0
    assert fluxo.ctx.ledger.saldo_da_conta(a_liberar(PROFISSIONAL.id), pid) == VALOR
    repasse = fluxo.repasse(pid)  # um só
    assert repasse.gatilho == "prazo" and repasse.valor_liquido_centavos == VALOR
    assert fluxo.saldo(pid)["liberado_centavos"] == 0  # a liberação não é desta tarefa
    assert not [n for n, _ in fluxo.fake.chamadas if n.startswith("transfer")]


def test_duas_maquinas_concluindo_juntas_geram_um_repasse(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.amb.relogio.avancar(days=8)
    barreira = threading.Barrier(2)

    def maquina() -> None:
        executor = ExecutorContexto(fluxo.ctx)
        barreira.wait()
        try:
            executor.executar(por_prazo(pid), fluxo.amb.relogio.agora)
        except Exception as erro:  # noqa: BLE001 - perder a corrida é conflito de estado
            assert type(erro).__name__ == "ConflitoDeEstado"

    fios = [threading.Thread(target=maquina) for _ in range(2)]
    [f.start() for f in fios]
    [f.join(20) for f in fios]
    assert len(list(fluxo.ctx.repasses.do_pedido(pid))) == 1
    assert fluxo.tipos(pid).count(TipoLancamento.RETENCAO) == 1


def test_com_relato_aberto_nada_conclui(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    r = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/disputa",
        "t-cliente",
        {"motivo": "mal_feito", "descricao": "Ficou torto"},
    )
    assert r.status_code in (200, 201), r.text
    disputa = fluxo.ctx.disputas.obter(pid)
    fluxo.amb.relogio.avancar(days=30)
    agendador(fluxo).rodar_uma_vez()
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.EM_DISPUTA
    # mesmo que o pedido volte a "em confirmação" com o relato ainda aberto
    pedido = fluxo.ctx.pedidos.obter(pid)
    fluxo.ctx.pedidos.salvar(replace(pedido, estado=Estado.EM_CONFIRMACAO))
    assert fluxo.ctx.disputas.obter(pid) == disputa
    ExecutorContexto(fluxo.ctx).executar(por_prazo(pid), fluxo.amb.relogio.agora)
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.EM_CONFIRMACAO
    assert custodia(fluxo, pid) == VALOR


def test_check_out_sem_codigo_nao_conclui_por_prazo(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    pedido = fluxo.ctx.pedidos.obter(pid)
    fluxo.ctx.pedidos.salvar(replace(pedido, check_out_sem_codigo=True))
    fluxo.amb.relogio.avancar(days=30)
    agendador(fluxo).rodar_uma_vez()
    ExecutorContexto(fluxo.ctx).executar(por_prazo(pid), fluxo.amb.relogio.agora)
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.EM_CONFIRMACAO
    assert custodia(fluxo, pid) == VALOR


# --- 2) aditivo pago depois do cancelamento ------------------------------------------------------


@pytest.mark.parametrize("fim", ["ausencia", "cancelamento"])
def test_aditivo_pago_depois_volta_inteiro_e_nao_fica_em_custodia(fluxo: Fluxo, fim):  # noqa: F811
    pid, _ = pedido_pago_e_agendado(fluxo)
    extra = aditivo_aprovado(fluxo, pid, pago=False)
    if fim == "ausencia":
        vencer_a_tolerancia(fluxo)
        agendador(fluxo).rodar_uma_vez()
    else:
        assert fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"}).status_code == 200
    assert ("cancelar_cobranca", extra.id) in fluxo.fake.chamadas

    fluxo.fake.marcar_paga(extra.id)  # o provedor aceitou mesmo assim
    for evento in ("ev-1", "ev-1", "ev-2"):
        r = fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, extra.id, evento_id=evento)
        assert r.status_code == 200, r.text

    assert custodia(fluxo, pid) == 0
    assert fluxo.servico.cobrancas.obter(extra.id).status is EstadoCobranca.DEVOLVIDA
    (estorno,) = fluxo.fake.estornos_da_cobranca(extra.id)
    assert estorno.valor_centavos == ADITIVO and estorno.chave == f"orfao/{extra.id}"


def test_falha_ao_cancelar_no_provedor_nao_impede_o_cancelamento(fluxo, monkeypatch):  # noqa: F811
    pid, _ = pedido_pago_e_agendado(fluxo)
    extra = aditivo_aprovado(fluxo, pid, pago=False)

    def quebra(_):
        raise ErroProvedor("fora do ar")

    monkeypatch.setattr(fluxo.fake, "cancelar_cobranca", quebra)
    assert fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"}).status_code == 200
    assert fluxo.servico.cobrancas.obter(extra.id).status is EstadoCobranca.CANCELADA


# --- 3) 7.7: o parcelado volta quando a falta é do profissional ----------------------------------

CUSTO = 5_000


def parcelado(f: Fluxo) -> tuple[str, str]:
    f.servico.config = lambda: ConfigPagamento(
        alcada_disputa_centavos=10**9, parcelamento=ConfigParcelamento({3: 500})
    )
    pid = f.aceitar()
    r = f.chamar(
        "POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", {"meio": "cartao", "parcelas": 3}
    )
    assert r.status_code == 201, r.text
    cob = r.json()
    assert cob["valor_centavos"] > VALOR
    f.fake.marcar_paga(cob["id"])
    assert f.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob["id"]).status_code == 200
    f.agendar(pid)
    return pid, cob["id"]


@pytest.mark.parametrize("quem", ["ausencia", "cancela_profissional"])
def test_falta_ou_cancelamento_do_profissional_devolve_tambem_o_parcelado(fluxo, quem):  # noqa: F811
    pid, cobranca = parcelado(fluxo)
    cobrado = fluxo.servico.cobrancas.obter(cobranca).valor_centavos
    if quem == "ausencia":
        vencer_a_tolerancia(fluxo)
        agendador(fluxo).rodar_uma_vez()
    else:
        r = fluxo.acao(pid, "cancelar", "t-prof", {"motivo": "Não vou conseguir"})
        assert r.status_code == 200, r.text
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert ordem.valor_centavos == cobrado and ordem.estado == "enviada"
    assert custodia(fluxo, pid) == 0 and fluxo.ctx.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0
    assert fluxo.saldo(pid)["cliente_pagou_centavos"] == 0
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_cancelamento_pelo_cliente_antes_do_check_in_devolve_o_parcelado(fluxo):  # noqa: F811
    pid, cobranca = parcelado(fluxo)
    cobrado = fluxo.servico.cobrancas.obter(cobranca).valor_centavos
    for _ in range(2):  # repetir o toque não gera outro estorno
        fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"})
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert ordem.valor_centavos == cobrado and total_estornado(fluxo, cobranca) == cobrado
    assert custodia(fluxo, pid) == 0 and fluxo.ctx.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0
    assert fluxo.saldo(pid)["cliente_pagou_centavos"] == 0


def test_contestacao_aberta_nao_segura_o_estorno(fluxo: Fluxo):  # noqa: F811
    pid, cob = pedido_pago_e_agendado(fluxo)
    r = fluxo.webhook(
        TipoEvento.CONTESTACAO, cob["id"], valor_centavos=VALOR, status_contestacao="needs_response"
    )
    assert r.status_code == 200, r.text
    assert fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"}).status_code == 200
    assert total_estornado(fluxo, cob["id"]) == VALOR


# --- Etapa 2b: reembolso total por disputa devolve o valor pago (6.10) ---------------------------


def disputa_do_parcelado(f: Fluxo) -> tuple[str, str, int]:
    pid, cobranca = parcelado(f)
    f.iniciar(pid)
    f.encerrar_execucao(pid)
    corpo = {"motivo": "mal_feito", "descricao": "Ficou torto"}
    assert f.chamar("POST", f"/v1/pedidos/{pid}/disputa", "t-cliente", corpo).status_code == 201
    assert f.chamar("POST", f"/v1/pedidos/{pid}/disputa/resposta", "t-prof").status_code == 200
    return pid, cobranca, f.servico.cobrancas.obter(cobranca).valor_centavos


def decidir(f: Fluxo, pid: str, **corpo):
    corpo.setdefault("justificativa", "Conferido nas fotos.")
    return f.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-mediador", corpo)


def test_reembolso_total_por_disputa_devolve_tambem_o_parcelado(fluxo: Fluxo):  # noqa: F811
    pid, cobranca, cobrado = disputa_do_parcelado(fluxo)
    assert decidir(fluxo, pid, resultado="reembolso_total").status_code == 200
    assert decidir(fluxo, pid, resultado="reembolso_total").status_code != 200
    assert total_estornado(fluxo, cobranca) == cobrado
    assert sum(o.valor_centavos for o in fluxo.servico.ordens.do_pedido(pid)) == cobrado
    assert custodia(fluxo, pid) == 0 and fluxo.ctx.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0
    assert fluxo.saldo(pid)["cliente_pagou_centavos"] == 0
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_reembolso_parcial_por_disputa_nao_muda(fluxo: Fluxo):  # noqa: F811
    pid, cobranca, cobrado = disputa_do_parcelado(fluxo)
    r = decidir(fluxo, pid, resultado="reembolso_parcial", percentual_cliente_bps=2_500)
    assert r.status_code == 200, r.text
    assert total_estornado(fluxo, cobranca) == VALOR // 4
    assert fluxo.ctx.ledger.saldo_da_conta(TAXA_TRATO, pid) == cobrado - VALOR


def test_reembolso_total_com_custo_so_quando_ha_custo_e_nada_foi_liberado():
    livro = Livro()
    agora = AGORA
    registrar_cobranca(livro, "p", 1_050, "c", agora)
    assert reembolso_total_com_custo(livro.lancamentos, "p", "pro") is None  # sem parcelamento
    separar_custo_parcelamento(livro, "p", 50, "c", agora)
    assert reembolso_total_com_custo(livro.lancamentos, "p", "pro") == 1_050
    repartir_custodia(livro, "p", "pro", 0, "r", agora)
    assert reembolso_total_com_custo(livro.lancamentos, "p", "pro") == 1_050  # ainda a liberar
    liberar(livro, "p", "pro", "l", agora)
    assert reembolso_total_com_custo(livro.lancamentos, "p", "pro") is None


# --- 4) 6.10: reenvio seguro ---------------------------------------------------------------------


def ordem_pendente(f: Fluxo, monkeypatch, *, chegou: bool) -> tuple[str, str]:
    """Cancela com o provedor falhando. `chegou`: ele executou, mas a resposta se perdeu."""
    pid, cob = pedido_pago_e_agendado(f)
    original = f.fake.estornar

    def falha(*args):
        if chegou:
            original(*args)
        raise ErroProvedor("sem resposta")

    with monkeypatch.context() as m:
        m.setattr(f.fake, "estornar", falha)
        assert f.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"}).status_code == 200
    assert len(f.servico.ordens.pendentes(pid)) == 1
    return pid, cob["id"]


def total_estornado(f: Fluxo, cobranca: str) -> int:
    return sum(e.valor_centavos for e in f.fake.estornos_da_cobranca(cobranca))


def test_o_ciclo_reenvia_depois_da_idade_minima_uma_vez(fluxo, monkeypatch):  # noqa: F811
    pid, cob = ordem_pendente(fluxo, monkeypatch, chegou=False)
    assert agendador(fluxo).rodar_uma_vez().estornos_confirmados == 0  # nova demais
    fluxo.amb.relogio.agora += MINUTOS_2
    assert agendador(fluxo).rodar_uma_vez().estornos_confirmados == 1
    assert agendador(fluxo).rodar_uma_vez().estornos_confirmados == 0
    assert total_estornado(fluxo, cob) == VALOR
    assert fluxo.servico.ordens.pendentes(pid) == [] or not fluxo.servico.ordens.pendentes(pid)


@pytest.mark.parametrize("chave_venceu", [False, True])
def test_resposta_perdida_nao_vira_segundo_estorno(fluxo, monkeypatch, chave_venceu):  # noqa: F811
    pid, cob = ordem_pendente(fluxo, monkeypatch, chegou=True)
    if chave_venceu:
        fluxo.fake.esquecer_chaves()
    chamadas = len(estornos_no_provedor(fluxo))
    assert fluxo.servico.reenviar_estornos(pid) == 1
    assert len(estornos_no_provedor(fluxo)) == chamadas  # achou na consulta: não reenviou
    assert total_estornado(fluxo, cob) == VALOR
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert ordem.estado == "enviada" and ordem.provedor_estorno_id


def test_estorno_por_fora_deixa_a_ordem_em_revisao_uma_vez(fluxo, monkeypatch):  # noqa: F811
    pid, cob = ordem_pendente(fluxo, monkeypatch, chegou=False)
    fluxo.fake.estornar_por_fora(cob, 1_000)
    chamadas = len(estornos_no_provedor(fluxo))
    for _ in range(3):
        assert fluxo.servico.reenviar_estornos(pid) == 0
    assert len(estornos_no_provedor(fluxo)) == chamadas
    assert total_estornado(fluxo, cob) == 1_000
    assert len(revisoes(fluxo)) == 1 and "por fora" in revisoes(fluxo)[0]


def test_estorno_falho_no_provedor_vai_para_revisao(fluxo, monkeypatch):  # noqa: F811
    pid, cob = ordem_pendente(fluxo, monkeypatch, chegou=True)
    chave, feito = next(iter(fluxo.fake._estornos.items()))
    fluxo.fake._estornos[chave] = replace(feito, falhou=True)
    assert fluxo.servico.reenviar_estornos(pid) == 0
    assert len(revisoes(fluxo)) == 1


def test_sem_conseguir_consultar_nada_e_reenviado(fluxo, monkeypatch):  # noqa: F811
    pid, cob = ordem_pendente(fluxo, monkeypatch, chegou=False)

    def quebra(_):
        raise ErroProvedor("fora do ar")

    monkeypatch.setattr(fluxo.fake, "estornos_da_cobranca", quebra)
    chamadas = len(estornos_no_provedor(fluxo))
    assert fluxo.servico.reenviar_estornos(pid) == 0
    assert len(estornos_no_provedor(fluxo)) == chamadas and revisoes(fluxo) == []


def test_dois_reenvios_ao_mesmo_tempo_estornam_uma_vez(fluxo, monkeypatch):  # noqa: F811
    pid, cob = ordem_pendente(fluxo, monkeypatch, chegou=False)
    barreira = threading.Barrier(4)

    def rodar() -> None:
        barreira.wait()
        fluxo.servico.reenviar_estornos(pid)

    fios = [threading.Thread(target=rodar) for _ in range(4)]
    [f.start() for f in fios]
    [f.join(20) for f in fios]
    assert total_estornado(fluxo, cob) == VALOR


# --- 5) 6.11: contestação perdida ----------------------------------------------------------------


def perder_contestacao(f: Fluxo, cobranca: str, valor: int) -> None:
    r = f.webhook(
        TipoEvento.CONTESTACAO,
        cobranca,
        valor_centavos=valor,
        status_contestacao="lost",
        evento_id=f"ev-contest-{valor}",
    )
    assert r.status_code == 200, r.text


@pytest.mark.parametrize("perdido", [30_000, VALOR])
def test_cancelar_depois_da_contestacao_devolve_so_o_que_falta(fluxo: Fluxo, perdido):  # noqa: F811
    pid, cob = pedido_pago_e_agendado(fluxo)
    perder_contestacao(fluxo, cob["id"], perdido)
    assert fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"}).status_code == 200
    pedidas = sum(o.valor_centavos for o in fluxo.servico.ordens.do_pedido(pid))
    assert pedidas == VALOR - perdido and total_estornado(fluxo, cob["id"]) == VALOR - perdido
    assert custodia(fluxo, pid) == 0


def test_ordem_anterior_a_contestacao_perdida_nao_e_enviada(fluxo, monkeypatch):  # noqa: F811
    pid, cob = ordem_pendente(fluxo, monkeypatch, chegou=False)
    perder_contestacao(fluxo, cob, VALOR)
    chamadas = len(estornos_no_provedor(fluxo))
    assert fluxo.servico.reenviar_estornos(pid) == 0
    assert len(estornos_no_provedor(fluxo)) == chamadas and total_estornado(fluxo, cob) == 0
    assert any("contesta" in m for m in revisoes(fluxo))


@pytest.mark.parametrize("quem", ["t-cliente", "t-prof"])
def test_parcelado_com_contestacao_maior_que_o_servico_ainda_cancela(fluxo, quem):  # noqa: F811
    pid, cobranca = parcelado(fluxo)
    cobrado = fluxo.servico.cobrancas.obter(cobranca).valor_centavos
    perder_contestacao(fluxo, cobranca, cobrado - 1_000)
    r = fluxo.acao(pid, "cancelar", quem, {"motivo": "Não vai dar"})
    assert r.status_code == 200, r.text
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CANCELADO
    pedidas = sum(o.valor_centavos for o in fluxo.servico.ordens.do_pedido(pid))
    assert total_estornado(fluxo, cobranca) == pedidas <= 1_000


def test_parcelado_com_contestacao_parcial_devolve_o_resto_ao_ser_o_profissional(fluxo):  # noqa: F811
    pid, cobranca = parcelado(fluxo)
    cobrado = fluxo.servico.cobrancas.obter(cobranca).valor_centavos
    perder_contestacao(fluxo, cobranca, 30_000)
    r = fluxo.acao(pid, "cancelar", "t-prof", {"motivo": "Não vai dar"})
    assert r.status_code == 200, r.text
    assert total_estornado(fluxo, cobranca) == cobrado - 30_000
    assert custodia(fluxo, pid) == 0 and fluxo.ctx.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0
