"""BE-INDISPONIBILIDADE-22.3-B: orçamento, disputa, avaliação, contestação de medida,
justificativa de ausência, reserva do Pix e visita recorrente. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import datetime, timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL
from test_ausencia_cliente import LONGE, justificar, registrado, remarcado_para_longe, ver
from test_cliente_bloqueado_pedido import bloquear
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401
from test_orcamento_vencido import aceitar, orcamento, vencido
from test_pessoa_diferente import estado

from trato.api import medidas
from trato.api.indisponibilidade import (
    corte_das_reservas,
    disputa_vigente,
    fim_do_congelamento,
)
from trato.api.recorrencias import ST_ATIVA, V_AGENDADA, V_EXPIRADA, Recorrencia, fechar_visitas
from trato.api.rotas_app import _limite_para_avaliar
from trato.api.validade import orcamento_vencido
from trato.disputas.indisponibilidade import estender, ultimo_inicio_vencido
from trato.pedidos.estados import Estado
from trato.persistencia.indisponibilidades import Janela

H = timedelta(hours=1)
D = timedelta(days=1)


def falha(contexto, inicio, fim=None, origem="app"):
    return contexto.indisponibilidades.criar(
        Janela(origem, inicio, "Falha geral registrada.", "eq-admin", fim_em=fim)
    )[0]


def test_falha_ativa_nao_deixa_vencer_e_a_encerrada_soma_o_tempo():
    ate = AGORA + 10 * H
    ativa = [(AGORA + 2 * H, None)]
    assert estender(ativa, AGORA, ate, AGORA + 20 * H) == AGORA + 28 * H
    parada = [(AGORA + 10 * H, None)]  # alcança exatamente o vencimento
    um_pouco_depois = AGORA + 11 * H + timedelta(microseconds=1)
    assert estender(parada, AGORA, ate, AGORA + 11 * H) == um_pouco_depois
    na_borda = estender([(AGORA + H, None)], AGORA, ate, AGORA + 100 * H)
    assert na_borda > AGORA + 100 * H
    assert estender([(AGORA + 30 * H, None)], AGORA, ate, AGORA + 5 * H) == ate


def test_inverso_para_a_reserva():
    agora = AGORA + 10 * H
    assert ultimo_inicio_vencido(agora, H, []) == agora - H
    meio = [(agora - 2 * H, agora - timedelta(minutes=30))]
    assert ultimo_inicio_vencido(agora, H, meio) == agora - timedelta(hours=2, minutes=30)
    assert ultimo_inicio_vencido(agora, H, [(agora - 3 * H, None)]) == agora - 4 * H


def test_orcamento_vale_pelo_tempo_prorrogado_no_aceite_e_no_detalhe(fluxo):
    pid, oid = orcamento(fluxo, fluxo.ctx.agora() + 2 * H)
    inicio = fluxo.ctx.agora()
    falha(fluxo.ctx, inicio + H, inicio + 4 * H, "pagamento")  # +3 h: vence em 5 h
    fluxo.amb.relogio.avancar(hours=4)
    assert not orcamento_vencido(fluxo.ctx, oid, fluxo.ctx.agora())
    r = fluxo.chamar("GET", f"/v1/orcamentos/{oid}", "t-cliente")
    assert r.status_code == 200, r.text
    assert datetime.fromisoformat(r.json()["validade_ate"]) == inicio + 5 * H
    assert aceitar(fluxo, pid, oid).status_code == 200
    assert fluxo.cobrar(pid)["status"] == "aguardando"  # a cobrança usa a mesma validade


def test_orcamento_vence_no_fim_prorrogado(fluxo):
    pid, oid = orcamento(fluxo, fluxo.ctx.agora() + 2 * H)
    inicio = fluxo.ctx.agora()
    falha(fluxo.ctx, inicio + H, inicio + 4 * H)
    fluxo.amb.relogio.avancar(hours=5)
    assert vencido(aceitar(fluxo, pid, oid))


def test_resposta_da_disputa_prorrogada_sem_gravar_o_prazo_novo(fluxo):
    pid = fluxo.ate_em_confirmacao()
    corpo = {"motivo": "mal_feito", "descricao": "A pintura ficou manchada."}
    assert fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa", "t-cliente", corpo).status_code < 300
    original = fluxo.ctx.disputas.obter(pid).prazos.resposta_ate
    aberta = fluxo.ctx.disputas.obter(pid).aberta_em
    falha(fluxo.ctx, aberta + H, aberta + 6 * H)
    vigente = disputa_vigente(fluxo.ctx, fluxo.ctx.disputas.obter(pid))
    assert vigente.prazos.resposta_ate == original + 5 * H
    fluxo.amb.relogio.agora = original + 2 * H  # fora do original, dentro do prorrogado
    visto = fluxo.chamar("GET", f"/v1/pedidos/{pid}/disputa", "t-cliente").json()
    assert datetime.fromisoformat(visto["resposta_ate"]) == original + 5 * H
    r = fluxo.chamar(
        "POST", f"/v1/pedidos/{pid}/disputa/resposta", "t-prof", {"mensagem": "Refaço a parede."}
    )
    assert r.status_code == 200, r.text
    assert fluxo.ctx.disputas.obter(pid).prazos.resposta_ate == original


def test_avaliacao_contestacao_e_congelamento(amb):
    pedido = amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - 3 * D)
    antes, _ = _limite_para_avaliar(amb.contexto, pedido)
    congela = fim_do_congelamento(amb.contexto, pedido.concluido_em)
    falha(amb.contexto, AGORA - 3 * D + H, AGORA - 3 * D + 11 * H)
    assert _limite_para_avaliar(amb.contexto, pedido)[0] == antes + 10 * H
    assert fim_do_congelamento(amb.contexto, pedido.concluido_em) == congela + 10 * H


def test_contestacao_de_medida_mostra_o_prazo_prorrogado(fluxo):
    medida = bloquear(fluxo)
    ate = medidas.contestavel_ate(fluxo.ctx, medida)
    falha(fluxo.ctx, medida.avisado_em + D, medida.avisado_em + 3 * D)
    assert medidas.saida(fluxo.ctx, medida).contestavel_ate == ate + 2 * D


def test_justificativa_da_ausencia_prorrogada(fluxo):
    pid, _ = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    ate = datetime.fromisoformat(ver(fluxo, pid).json()["justificativa_ate"])
    agora = fluxo.ctx.agora()
    falha(fluxo.ctx, agora + H, agora + 7 * H)
    fluxo.amb.relogio.agora = ate + H
    assert datetime.fromisoformat(ver(fluxo, pid).json()["justificativa_ate"]) == ate + 6 * H
    assert justificar(fluxo, pid).status_code == 200


def test_reserva_do_pix_devolve_o_tempo_da_falha(amb):
    agora = AGORA
    trinta = timedelta(minutes=30)
    assert corte_das_reservas(amb.contexto, trinta, agora) == agora
    falha(amb.contexto, agora - 2 * H, agora - H, "pagamento")
    # Falha antiga, fora da validade: nada muda para quem venceu agora.
    assert corte_das_reservas(amb.contexto, trinta, agora) == agora
    falha(amb.contexto, agora - timedelta(minutes=10))  # app, ativa
    corte = corte_das_reservas(amb.contexto, trinta, agora)
    assert corte == agora - timedelta(minutes=10)


def test_visita_recorrente_nao_expira_durante_a_falha(fluxo):
    agora = fluxo.ctx.agora()
    repo = fluxo.ctx.recorrencias
    serie = repo.criar(
        Recorrencia(
            id="rec-223",
            pedido_origem_id="ped-origem",
            cliente_id=CLIENTE.id,
            profissional_id=PROFISSIONAL.id,
            categoria_id="pintura",
            frequencia="semanal",
            valor_centavos=VALOR,
            status=ST_ATIVA,
            proposto_por=CLIENTE.id,
            criado_em=agora,
            proxima_visita_em=agora + 3 * D,
        )
    )
    pid = fluxo.chamar("POST", "/v1/pedidos", "t-cliente").json()["id"]
    visita = repo.reservar_visita(serie.id, serie.proxima_visita_em, agora)
    repo.vincular_pedido(visita.id, pid)
    limite = visita.data_prevista_em - timedelta(hours=repo.config().limite_confirmacao_horas)
    janela = falha(fluxo.ctx, agora + H)
    fechar_visitas(fluxo.ctx, limite + H)
    fluxo.amb.relogio.agora = limite + H
    assert fechar_visitas(fluxo.ctx, limite + H)[1] == 0
    assert repo.obter_visita(visita.id).status == V_AGENDADA
    fluxo.ctx.indisponibilidades.encerrar(janela.id, limite + H, "eq-admin")
    fim = limite + (limite + H - janela.inicio_em)
    assert fechar_visitas(fluxo.ctx, fim - H)[1] == 0
    fluxo.amb.relogio.agora = fim
    assert fechar_visitas(fluxo.ctx, fim)[1] == 1
    assert repo.obter_visita(visita.id).status == V_EXPIRADA
    assert estado(fluxo, pid) is Estado.ABERTO  # sem gancho de cancelamento neste teste
