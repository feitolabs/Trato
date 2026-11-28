"""Serviço recorrente: propor, aceitar, pausar, retomar, cancelar, pular, reajustar e gerar visitas."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from conftest import AGORA, cab

from trato.agendador.executor import ExecutorContexto
from trato.api.auth import PapelUsuario
from trato.api.recorrencias import somar_frequencia
from trato.api.repositorios_app import PerfilDetalhe
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado

URL = "/v1/recorrencias"
H = timedelta(hours=1)
D = timedelta(days=1)


@pytest.fixture
def rec(amb):
    for uid, nome, papel in (
        ("cli-1", "João Pedro Silva", PapelUsuario.CLIENTE),
        ("pro-1", "Carlos Eduardo Souza", PapelUsuario.PROFISSIONAL),
    ):
        amb.contexto.usuarios.adicionar(PerfilDetalhe(uid, nome, papel))
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    return amb


def _propor(amb, quem="t-cliente", freq="semanal", em=7 * D, **extra):
    corpo = {
        "pedido_origem_id": "ped-1",
        "frequencia": freq,
        "proxima_visita_em": (AGORA + em).isoformat(),
        **extra,
    }
    return amb.cliente.post(URL, json=corpo, headers=cab(quem))


def _ativa(amb, em=7 * D, freq="semanal") -> str:
    rid = _propor(amb, em=em, freq=freq).json()["id"]
    r = amb.cliente.post(f"{URL}/{rid}/aceitar", headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    return rid


def _acao(amb, rid, caminho, quem="t-cliente", **kw):
    return amb.cliente.post(f"{URL}/{rid}/{caminho}", headers=cab(quem), **kw)


def _executor(amb):
    repo = RepositorioEmMemoria()
    notif = ServicoNotificacoes(repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True))
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    return ExecutorContexto(amb.contexto, notif), repo


def _serie(amb, rid):
    return amb.contexto.recorrencias.obter(rid)


# --- propor e aceitar ---------------------------------------------------------------------


def test_cliente_propoe_e_profissional_ve_so_o_nome_curto(rec):
    r = _propor(rec)
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["status"] == "proposta" and corpo["valor_centavos"] == 100_000
    assert corpo["meu_papel"] == "cliente" and corpo["proposto_por_mim"] is True
    assert corpo["outra_parte_nome"] == "Carlos S."
    do_prof = rec.cliente.get(URL, headers=cab("t-prof")).json()
    assert [(i["meu_papel"], i["proposto_por_mim"], i["outra_parte_nome"]) for i in do_prof] == [
        ("profissional", False, "João S.")
    ]
    texto = str(do_prof) + str(corpo)
    assert "Pedro" not in texto and "Eduardo" not in texto and "@" not in texto


def test_profissional_pode_propor_com_outro_valor(rec):
    r = _propor(rec, quem="t-prof", freq="mensal", valor_centavos=120_000)
    assert r.status_code == 201 and r.json()["valor_centavos"] == 120_000
    assert r.json()["frequencia"] == "mensal"


def test_so_a_outra_parte_aceita_e_so_uma_vez(rec):
    rid = _propor(rec).json()["id"]
    proprio = _acao(rec, rid, "aceitar", "t-cliente")
    assert proprio.status_code == 403
    assert proprio.json()["detail"] == "Apenas a outra parte pode aceitar o serviço recorrente."
    ok = _acao(rec, rid, "aceitar", "t-prof")
    assert ok.status_code == 200 and ok.json()["status"] == "ativa"
    de_novo = _acao(rec, rid, "aceitar", "t-prof")
    assert de_novo.status_code == 409
    assert de_novo.json()["detail"] == "Este serviço recorrente já foi respondido."


def test_recusar_cancela_a_proposta_e_libera_nova_proposta(rec):
    rid = _propor(rec).json()["id"]
    assert _acao(rec, rid, "recusar", "t-cliente").status_code == 403  # quem propôs cancela
    assert _acao(rec, rid, "recusar", "t-prof").json()["status"] == "cancelada"
    assert _propor(rec, quem="t-prof").status_code == 201


def test_regras_de_entrada(rec):
    assert _propor(rec).status_code == 201
    dup = _propor(rec, quem="t-prof")
    assert dup.status_code == 409
    assert dup.json()["detail"] == "Já existe um serviço recorrente para este pedido."


def test_so_pedido_concluido_e_so_as_partes(rec):
    pedido = rec.contexto.pedidos.obter("ped-1")
    from dataclasses import replace

    rec.contexto.pedidos.salvar(replace(pedido, estado=Estado.EM_ANDAMENTO))
    r = _propor(rec)
    assert r.status_code == 409
    assert "depois que o serviço for concluído" in r.json()["detail"]
    rec.contexto.pedidos.salvar(replace(pedido, estado=Estado.CONCLUIDO))
    assert _propor(rec, quem="t-outro-cliente").status_code == 404
    assert _propor(rec, quem="t-outro-prof").status_code == 404
    assert rec.cliente.post(URL, json={}).status_code == 401
    assert _propor(rec, quem="t-equipe").status_code == 403


@pytest.mark.parametrize(
    "extra",
    [{"freq": "diaria"}, {"em": -D}, {"valor_centavos": 0}, {"valor_centavos": 50_000_001}],
)
def test_validacao_da_proposta(rec, extra):
    assert _propor(rec, **extra).status_code == 422


def test_terceiro_nao_ve_nem_mexe(rec):
    rid = _ativa(rec)
    for quem in ("t-outro-cliente", "t-outro-prof"):
        assert rec.cliente.get(f"{URL}/{rid}", headers=cab(quem)).status_code == 404
        assert _acao(rec, rid, "pausar", quem).status_code == 404
        assert rec.cliente.get(URL, headers=cab(quem)).json() == []


# --- pausar, retomar, cancelar -------------------------------------------------------------


def test_pausar_retomar_e_cancelar(rec):
    rid = _ativa(rec, em=3 * D)
    assert _acao(rec, rid, "pausar", "t-prof").json()["status"] == "pausada"
    assert _acao(rec, rid, "pausar", "t-prof").status_code == 409
    # Retoma depois da data prevista: a próxima visita pula para a próxima data futura.
    rec.contexto.recorrencias.mudar_status(rid, ("pausada",), "pausada", AGORA)
    from dataclasses import replace

    antiga = AGORA - 10 * D
    rec.contexto.recorrencias._recs[rid] = replace(_serie(rec, rid), proxima_visita_em=antiga)
    retomada = _acao(rec, rid, "retomar").json()
    assert retomada["status"] == "ativa"
    assert datetime.fromisoformat(retomada["proxima_visita_em"]) > AGORA
    assert _acao(rec, rid, "retomar").status_code == 409
    cancelada = _acao(rec, rid, "cancelar", "t-prof").json()
    assert cancelada["status"] == "cancelada"
    assert _acao(rec, rid, "cancelar").status_code == 409
    assert _serie(rec, rid).cancelado_por == "pro-1"


# --- gerar visitas (agendador) ------------------------------------------------------------


def test_datas_da_serie():
    base = datetime(2026, 1, 31, 15, 0, tzinfo=UTC)
    assert somar_frequencia(base, "semanal") == base + 7 * D
    assert somar_frequencia(base, "quinzenal") == base + 14 * D
    assert somar_frequencia(base, "mensal") == datetime(2026, 2, 28, 15, 0, tzinfo=UTC)
    assert somar_frequencia(datetime(2026, 12, 5, 15, tzinfo=UTC), "mensal").month == 1


def test_agendador_gera_a_visita_e_o_pedido_sem_cobrar(rec):
    executor, avisos = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    assert executor.gerar_visitas_recorrentes(AGORA) == 1
    (visita,) = rec.contexto.recorrencias.visitas(rid)
    assert visita.status == "agendada" and visita.data_prevista_em == AGORA + 30 * H
    pedido = rec.contexto.pedidos.obter(visita.pedido_id)
    assert pedido.estado is Estado.ABERTO and pedido.cliente_id == "cli-1"
    (orcamento,) = rec.contexto.orcamentos.do_pedido(visita.pedido_id)
    assert orcamento.valor_centavos == 100_000
    assert not rec.contexto.ledger.lancamentos(visita.pedido_id)  # nenhuma cobrança
    assert _serie(rec, rid).proxima_visita_em == AGORA + 30 * H + 7 * D
    assert "recorrencia.visita" in [n.tipo for n in avisos.listar("cli-1", False, 10)]
    detalhe = rec.cliente.get(f"{URL}/{rid}", headers=cab("t-prof")).json()
    assert [(v["status"], v["pedido_id"]) for v in detalhe["visitas"]] == [
        ("agendada", visita.pedido_id)
    ]


def test_geracao_e_idempotente(rec):
    executor, _ = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    assert executor.gerar_visitas_recorrentes(AGORA) == 1
    assert executor.gerar_visitas_recorrentes(AGORA) == 0
    assert executor.gerar_visitas_recorrentes(AGORA + 1 * H) == 0
    assert len(rec.contexto.recorrencias.visitas(rid)) == 1
    # a data já usada nunca gera visita de novo (índice único série + data)
    assert rec.contexto.recorrencias.reservar_visita(rid, AGORA + 30 * H, AGORA) is None
    # série atrasada (ciclo repetido sem avançar): reusa a visita e só anda a série
    rec.contexto.recorrencias._recs[rid] = _re(rec, rid, proxima_visita_em=AGORA + 30 * H)
    assert executor.gerar_visitas_recorrentes(AGORA) == 0
    assert len(rec.contexto.recorrencias.visitas(rid)) == 1
    assert _serie(rec, rid).proxima_visita_em == AGORA + 30 * H + 7 * D


def _re(amb, rid, **campos):
    from dataclasses import replace

    return replace(_serie(amb, rid), **campos)


def test_so_gera_dentro_da_antecedencia_e_com_a_serie_ativa(rec):
    executor, _ = _executor(rec)
    rid = _ativa(rec, em=5 * D)
    assert executor.gerar_visitas_recorrentes(AGORA) == 0  # longe demais
    _acao(rec, rid, "pausar", "t-prof")
    assert executor.gerar_visitas_recorrentes(AGORA + 5 * D) == 0  # pausada não gera
    proposta = _propor(rec, quem="t-prof")  # já existe série: 409, nada novo
    assert proposta.status_code == 409


def test_visita_paga_vira_confirmada_e_sem_pagamento_expira_liberando_a_agenda(rec):
    executor, _ = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    executor.gerar_visitas_recorrentes(AGORA)
    (visita,) = rec.contexto.recorrencias.visitas(rid)
    # antes do limite (12 h antes) e sem pagamento: segue agendada
    executor.gerar_visitas_recorrentes(AGORA + 10 * H)
    assert rec.contexto.recorrencias.obter_visita(visita.id).status == "agendada"
    # passou do limite sem pagar: expira e o pedido aberto é cancelado
    executor.gerar_visitas_recorrentes(AGORA + 19 * H)
    assert rec.contexto.recorrencias.obter_visita(visita.id).status == "expirada"
    assert rec.contexto.pedidos.obter(visita.pedido_id).estado is Estado.CANCELADO
    assert _serie(rec, rid).status == "ativa"  # a série continua


def test_visita_paga_vira_confirmada_paga(rec):
    from dataclasses import replace

    executor, _ = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    executor.gerar_visitas_recorrentes(AGORA)
    (visita,) = rec.contexto.recorrencias.visitas(rid)
    pedido = rec.contexto.pedidos.obter(visita.pedido_id)
    rec.contexto.pedidos.salvar(replace(pedido, estado=Estado.PAGO_E_RETIDO))
    executor.gerar_visitas_recorrentes(AGORA + 19 * H)  # passou do limite, mas já está pago
    assert rec.contexto.recorrencias.obter_visita(visita.id).status == "confirmada_paga"
    assert rec.contexto.pedidos.obter(visita.pedido_id).estado is Estado.PAGO_E_RETIDO


# --- pular visita --------------------------------------------------------------------------


def test_pular_visita_gerada_cancela_o_pedido_e_a_serie_continua(rec):
    executor, _ = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    executor.gerar_visitas_recorrentes(AGORA)
    (visita,) = rec.contexto.recorrencias.visitas(rid)
    r = _acao(rec, rid, f"visitas/{visita.id}/pular", "t-prof")
    assert r.status_code == 200, r.text
    assert [v["status"] for v in r.json()["visitas"]] == ["pulada"]
    assert rec.contexto.recorrencias.obter_visita(visita.id).pulada_por == "pro-1"
    assert rec.contexto.pedidos.obter(visita.pedido_id).estado is Estado.CANCELADO
    assert r.json()["status"] == "ativa"
    de_novo = _acao(rec, rid, f"visitas/{visita.id}/pular")
    assert de_novo.status_code == 409
    assert de_novo.json()["detail"] == "Esta visita não pode mais ser pulada."
    assert _acao(rec, rid, "visitas/nao-existe/pular").status_code == 404


def test_pular_proxima_antes_de_gerar_anda_a_serie(rec):
    executor, _ = _executor(rec)
    rid = _ativa(rec, em=5 * D)
    r = _acao(rec, rid, "pular-proxima")
    assert r.status_code == 200, r.text
    assert [v["status"] for v in r.json()["visitas"]] == ["pulada"]
    assert _serie(rec, rid).proxima_visita_em == AGORA + 12 * D
    assert executor.gerar_visitas_recorrentes(AGORA + 6 * D) == 0  # a pulada não gera pedido
    # com a data da próxima já gerada, o caminho é pular pela lista de visitas
    rec.contexto.recorrencias.reservar_visita(rid, _serie(rec, rid).proxima_visita_em, AGORA)
    assert _acao(rec, rid, "pular-proxima").status_code == 409


def test_cancelar_a_serie_tira_as_visitas_abertas_da_agenda(rec):
    executor, _ = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    executor.gerar_visitas_recorrentes(AGORA)
    (visita,) = rec.contexto.recorrencias.visitas(rid)
    assert _acao(rec, rid, "cancelar").json()["status"] == "cancelada"
    assert rec.contexto.recorrencias.obter_visita(visita.id).status == "cancelada"
    assert rec.contexto.pedidos.obter(visita.pedido_id).estado is Estado.CANCELADO
    assert executor.gerar_visitas_recorrentes(AGORA + 8 * D) == 0


# --- reajuste -----------------------------------------------------------------------------


def test_reajuste_so_vale_com_o_aceite_do_cliente(rec):
    executor, _ = _executor(rec)
    rid = _ativa(rec, em=30 * H)
    assert (
        _acao(rec, rid, "reajuste", "t-cliente", json={"valor_centavos": 90_000}).status_code == 403
    )
    igual = _acao(rec, rid, "reajuste", "t-prof", json={"valor_centavos": 100_000})
    assert igual.status_code == 422
    novo = _acao(rec, rid, "reajuste", "t-prof", json={"valor_centavos": 120_000})
    assert novo.status_code == 200, novo.text
    assert novo.json()["valor_centavos"] == 100_000
    assert novo.json()["valor_proposto_centavos"] == 120_000
    # A visita gerada ANTES do aceite sai no valor antigo (nada é cobrado a mais).
    executor.gerar_visitas_recorrentes(AGORA)
    (v1,) = rec.contexto.recorrencias.visitas(rid)
    assert rec.contexto.orcamentos.do_pedido(v1.pedido_id)[0].valor_centavos == 100_000
    corpo_aceite = {"valor_centavos": 120_000}
    assert _acao(rec, rid, "reajuste/aceitar", "t-prof", json=corpo_aceite).status_code == 403
    ok = _acao(rec, rid, "reajuste/aceitar", "t-cliente", json=corpo_aceite)
    assert ok.status_code == 200
    assert (ok.json()["valor_centavos"], ok.json()["valor_proposto_centavos"]) == (120_000, None)
    assert _acao(rec, rid, "reajuste/aceitar", "t-cliente", json=corpo_aceite).status_code == 409
    executor.gerar_visitas_recorrentes(AGORA + 7 * D)
    novas = [v for v in rec.contexto.recorrencias.visitas(rid) if v.id != v1.id]
    assert rec.contexto.orcamentos.do_pedido(novas[0].pedido_id)[0].valor_centavos == 120_000


def test_reajuste_recusado_mantem_o_valor(rec):
    rid = _ativa(rec)
    _acao(rec, rid, "reajuste", "t-prof", json={"valor_centavos": 150_000})
    assert _acao(rec, rid, "reajuste/recusar", "t-prof").status_code == 403
    r = _acao(rec, rid, "reajuste/recusar", "t-cliente")
    assert (r.json()["valor_centavos"], r.json()["valor_proposto_centavos"]) == (100_000, None)
    assert _acao(rec, rid, "reajuste/recusar", "t-cliente").status_code == 409


def test_reajuste_so_em_serie_ativa_ou_pausada(rec):
    rid = _propor(rec).json()["id"]
    r = _acao(rec, rid, "reajuste", "t-prof", json={"valor_centavos": 90_000})
    assert r.status_code == 409


# --- Termos 5.2: orçamento da visita recorrente com prazo, validade e garantia ------------------


def test_visita_recorrente_herda_prazo_validade_e_garantia_da_origem(rec):
    from decimal import Decimal

    from trato.api.recorrencias import gerar_visitas
    from trato.api.repositorios import Contrato, ItemOrcamento

    orc_id = rec.contexto.orcamentos.enviar(
        pedido_id="ped-1",
        profissional_id="pro-1",
        itens=[ItemOrcamento("outro", "Limpeza", Decimal(1), 20_000)],
        agora=AGORA - 10 * D,
        prazo_execucao_dias=2,
        validade_ate=AGORA - 10 * D + timedelta(hours=48),
        garantia_dias=60,
        fora_do_escopo="Produtos químicos especiais",
    )
    rec.contexto.contratos._itens["ped-1"] = Contrato(
            pedido_id="ped-1",
            orcamento_id=orc_id,
            profissional_id="pro-1",
            valor_centavos=20_000,
            prazo_execucao_dias=2,
            garantia_dias=60,
    )
    rid = _ativa(rec, em=7 * D)
    agora_geracao = AGORA + 5 * D
    assert gerar_visitas(rec.contexto, agora_geracao) == 1
    visitas = rec.contexto.recorrencias.visitas(rid)
    assert len(visitas) == 1 and visitas[0].pedido_id is not None
    orcs = rec.contexto.orcamentos.do_pedido(visitas[0].pedido_id)
    assert len(orcs) == 1
    det = rec.contexto.orcamentos.detalhe(orcs[0].id)
    assert det is not None
    assert det.prazo_execucao_dias == 2
    assert det.garantia_dias == 60
    assert det.validade_ate == agora_geracao + timedelta(hours=48)
    assert det.fora_do_escopo == "Produtos químicos especiais"


def test_visita_recorrente_usa_fallback_quando_origem_nao_tem_campos_52(rec):
    from trato.api.recorrencias import PRAZO_EXECUCAO_PADRAO_VISITA_DIAS, gerar_visitas
    from trato.api.repositorios import Contrato

    # Contrato antigo sem prazo_execucao_dias, sem garantia_dias e sem orçamento detalhado
    rec.contexto.contratos._itens["ped-1"] = Contrato(
            pedido_id="ped-1",
            orcamento_id="orc-antigo-ausente",
            profissional_id="pro-1",
            valor_centavos=20_000,
            prazo_execucao_dias=None,
            garantia_dias=None,
    )
    rid = _ativa(rec, em=7 * D)
    agora_geracao = AGORA + 5 * D
    assert gerar_visitas(rec.contexto, agora_geracao) == 1
    visitas = rec.contexto.recorrencias.visitas(rid)
    orcs = rec.contexto.orcamentos.do_pedido(visitas[0].pedido_id)
    det = rec.contexto.orcamentos.detalhe(orcs[0].id)
    assert det is not None
    assert det.prazo_execucao_dias == PRAZO_EXECUCAO_PADRAO_VISITA_DIAS
    assert det.garantia_dias == rec.contexto.config.carregar().garantias.garantia_dias_padrao
    assert det.validade_ate == visitas[0].data_prevista_em
    assert det.validade_ate > agora_geracao
    from trato.api.validade import FORA_DO_ESCOPO_NAO_INFORMADO

    assert det.fora_do_escopo == FORA_DO_ESCOPO_NAO_INFORMADO
