"""BE-INDISPONIBILIDADE-22.3-C no Postgres local, com as migrations 20261127213000 e
20261127220000: orçamento, reserva do Pix, exclusividade e visita, com falha ativa e
encerrada."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from trato.agendador.executor import ExecutorContexto
from trato.api.recorrencias import V_AGENDADA, V_EXPIRADA, fechar_visitas
from trato.persistencia.indisponibilidades import Janela

from .test_ausencia_cliente_postgres import _no_passado
from .test_b32_nota_decimal_postgres import _concluir
from .test_exclusividade_cliente_postgres import dar_moedas
from .test_fluxo_postgres import abrir_pedido, enviar_orcamento
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401
from .test_rotas_app_postgres import get, post

pytestmark = pytest.mark.integracao
H = timedelta(hours=1)
M = timedelta(minutes=1)
ENVELHECER = "update public.orcamentos set enviado_em = %s, validade_ate = %s where pedido_id = %s"


@pytest.fixture
def limpar_janelas(cenario):
    """O histórico é imutável; só no banco descartável apagamos, para não vazar entre testes."""
    yield
    with cenario.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.janelas_indisponibilidade")


def agora() -> datetime:
    return datetime.now(UTC).replace(microsecond=0)


def falha(contexto, inicio, fim=None, origem="app"):
    janela, _ = contexto.indisponibilidades.criar(
        Janela(
            origem,
            inicio,
            "Falha registrada no teste.",
            "operador-teste",
            fim_em=fim,
            encerrada_por="operador-teste" if fim else None,
        )
    )
    return janela


def orcamento_vencido_ha_uma_hora(c) -> tuple[str, str]:
    pid = abrir_pedido(c)
    oid = enviar_orcamento(c, pid)
    _no_passado(c, ENVELHECER, (agora() - 5 * H, agora() - H, pid))
    return pid, oid


def aceitar(c, pid, oid):
    url = f"/v1/pedidos/{pid}/acoes/aceitar_orcamento"
    return c.pagto[0].post(url, json={"prova": {"orcamento_id": oid}}, headers=c.token("cliente"))


@pytest.mark.parametrize("ativa", [False, True])
def test_aceite_com_orcamento_prorrogado(pg, limpar_janelas, ativa):
    contexto = pg.pagto[1]
    pid, oid = orcamento_vencido_ha_uma_hora(pg)
    r = aceitar(pg, pid, oid)
    assert r.status_code == 409 and r.json()["codigo"] == "orcamento_vencido", r.text
    falha(contexto, agora() - 4 * H, None if ativa else agora() - 2 * H)
    r = aceitar(pg, pid, oid)
    assert r.status_code == 200, r.text
    assert contexto.contratos.obter_do_pedido(pid).orcamento_id.replace("-", "") == (
        oid.replace("-", "")
    )


@pytest.mark.parametrize("ativa", [False, True])
def test_exclusividade_do_cliente_respeita_a_validade_prorrogada(pg, limpar_janelas, ativa):
    dar_moedas(pg)
    contexto = pg.pagto[1]
    pid, oid = orcamento_vencido_ha_uma_hora(pg)

    def pedir():
        corpo = {"orcamento_id": oid, "chave_idempotencia": f"chave-{uuid.uuid4().hex}"}
        url = f"/v1/pedidos/{pid}/exclusividade-cliente"
        return pg.pagto[0].post(url, json=corpo, headers=pg.token("cliente"))

    r = pedir()
    assert r.json().get("codigo") == "orcamento_invalido", r.text
    falha(contexto, agora() - 4 * H, None if ativa else agora() - 2 * H, "pagamento")
    r = pedir()
    assert r.status_code == 201, r.text


def test_reserva_do_pix_ganha_de_volta_o_tempo_da_falha(pg, limpar_janelas):
    dar_moedas(pg)
    _, contexto, servico = pg.pagto
    validade = contexto.moedas.config().reserva_minutos * M
    base = agora()
    chave = str(uuid.uuid4())
    vence = base - 10 * M  # sem falha, já estaria vencida há 10 minutos
    assert (
        contexto.moedas.reservar_desconto(
            chave, pg.ids["cliente"], base.date(), base.date(), 10, 10,
            10**9, 10**9, 10**9, 10**6, vence,
        )
        == "ok"
    )  # fmt: skip
    executor = ExecutorContexto(contexto, None, servico.cobrancas, servico.provedor, servico)
    criada = vence - validade
    janela = falha(contexto, criada + 5 * M)  # ativa: só 5 minutos correram
    executor.expirar_reservas_moedas(base)
    assert contexto.moedas.reserva_status(chave) == "reservada"
    assert contexto.indisponibilidades.encerrar(janela.id, base, "operador-teste")
    quase = base + (validade - 5 * M) - M
    executor.expirar_reservas_moedas(quase)
    assert contexto.moedas.reserva_status(chave) == "reservada"
    executor.expirar_reservas_moedas(quase + 2 * M)
    executor.expirar_reservas_moedas(quase + 3 * M)
    assert contexto.moedas.reserva_status(chave) == "devolvida"


def test_oferta_do_profissional_suspensa_prorrogada_e_aceita(pg, limpar_janelas):
    dar_moedas(pg)
    contexto = pg.pagto[1]
    pro, cliente = pg.ids["profissional"], pg.ids["cliente"]
    with pg.local.admin() as con:
        con.execute(
            "insert into public.moedas_lancamentos (usuario_id, tipo, quantidade, "
            "chave_idempotencia, carteira, expira_em, criada_em) values "
            "(%s, 'bonus_avaliacao_profissional', 500, %s, 'profissional', %s, now())",
            (pro, f"teste:{uuid.uuid4()}", agora() + timedelta(days=90)),
        )
    pid = abrir_pedido(pg)
    criada = agora() - 10 * H
    repo = contexto.exclusividades
    r = repo.solicitar(pro, pid, f"chave-{uuid.uuid4().hex}", criada, 100, 50, 2, 30)
    assert r.resultado == "ok", r
    item = repo.obter(r.exclusividade_id)
    assert repo.prazo_de_resposta(item) == item.responder_ate
    janela = falha(contexto, criada + H)  # ativa: 1 hora de prazo correu
    assert repo.prazo_de_resposta(item) is None
    assert item.id not in [e.exclusividade_id for e in repo.expirar(agora())]
    assert repo.obter(item.id).status == "aguardando_cliente"
    fim = agora()
    assert contexto.indisponibilidades.encerrar(janela.id, fim, "operador-teste")
    assert repo.prazo_de_resposta(item) == item.responder_ate + (fim - (criada + H))
    assert item.id not in [e.exclusividade_id for e in repo.expirar(agora())]
    oferta = pg.pagto[0].get(f"/v1/pedidos/{pid}/exclusividade", headers=pg.token("cliente"))
    visto = datetime.fromisoformat(oferta.json()["responder_ate"])
    assert visto == repo.prazo_de_resposta(item)
    assert repo.responder(item.id, cliente, "aceitar", agora(), 48).resultado == "ok"


def test_visita_recorrente_com_falha_ativa_e_encerrada(cenario, limpar_janelas):
    c = cenario
    origem = _concluir(c)
    corpo = {
        "pedido_origem_id": origem,
        "frequencia": "quinzenal",
        "proxima_visita_em": (agora() + 30 * H).isoformat(),
    }
    r = post(c, "/v1/recorrencias", "cliente", corpo)
    assert r.status_code == 201, r.text
    rid = r.json()["id"]
    assert post(c, f"/v1/recorrencias/{rid}/aceitar", "profissional").status_code == 200
    ExecutorContexto(c.contexto).gerar_visitas_recorrentes(agora())
    (vista,) = get(c, f"/v1/recorrencias/{rid}", "cliente").json()["visitas"]
    repo = c.contexto.recorrencias
    visita = repo.obter_visita(vista["id"])
    limite = visita.data_prevista_em - repo.config().limite_confirmacao_horas * H

    def status(quando) -> str:
        fechar_visitas(c.contexto, quando)
        return repo.obter_visita(visita.id).status

    janela = falha(c.contexto, visita.criado_em + M)
    assert status(limite + H) == V_AGENDADA  # ativa: não vence
    assert c.contexto.indisponibilidades.encerrar(
        janela.id, janela.inicio_em + 3 * H, "operador-teste"
    )
    assert status(limite + 3 * H - M) == V_AGENDADA
    assert status(limite + 3 * H + M) == V_EXPIRADA
    assert post(c, f"/v1/recorrencias/{rid}/cancelar", "cliente").status_code == 200
