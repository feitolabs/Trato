"""B30 no Postgres local descartável: quem perde pelo aceite de outro orçamento é avisado 1 vez."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal

import pytest

from trato.api.repositorios import EtapaProposta, ItemOrcamento
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.postgres import NotificacoesServicoPostgres
from trato.notificacoes.servico import ServicoNotificacoes

from .test_fluxo_postgres import abrir_pedido, acao
from .test_rotas_app_postgres import post

pytestmark = pytest.mark.integracao


def _novo_profissional(c) -> str:
    novo = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (novo,))
        con.execute("insert into public.usuarios (id, nome) values (%s, 'Pro B30')", (novo,))
        con.execute("insert into public.perfis_profissional (usuario_id) values (%s)", (novo,))
        con.execute(
            "update public.perfis_profissional set status = 'aprovado', "
            "nivel_verificacao = 'verificado' where usuario_id = %s",
            (novo,),
        )
    return novo


def _orcar(c, pedido_id: str, pro: str) -> str:
    return c.contexto.orcamentos.enviar(
        pedido_id=pedido_id,
        profissional_id=pro,
        itens=[ItemOrcamento("horas", "Mão de obra", Decimal("8"), 10_000)],
        etapas=[EtapaProposta("Serviço", 80_000)],
        agora=datetime.now(UTC),
        prazo_execucao_dias=5,
        garantia_dias=90,
    )


def _total(c, usuario: str, evento: str) -> int:
    with c.local.admin() as con:
        return con.execute(
            "select count(*) from public.notificacoes where usuario_id = %s "
            "and dados ->> 'evento' = %s",
            (usuario, evento),
        ).fetchone()[0]


@pytest.fixture
def c(cenario):
    servico = ServicoNotificacoes(
        NotificacoesServicoPostgres(cenario.banco),
        Canais(CanalApp(), None, None),
        ConfigNotificacoes(_env_file=None),
    )
    ligar_ao_contexto(cenario.cliente.app, cenario.contexto, servico)
    cenario.cliente.app.state.notificador = servico
    return cenario


def test_aceitar_avisa_so_os_perdedores_uma_vez(c):
    pedido_id = abrir_pedido(c)
    ganhador, b, d = (_novo_profissional(c) for _ in range(3))
    orc_g, orc_b, orc_d = (_orcar(c, pedido_id, p) for p in (ganhador, b, d))

    r = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc_g})
    assert r.status_code == 200, r.text

    with c.local.admin() as con:  # o banco recusou os outros no aceite
        status = dict(
            con.execute(
                "select id::text, status from public.orcamentos where pedido_id = %s", (pedido_id,)
            ).fetchall()
        )
    assert status[orc_g] == "aceito" and status[orc_b] == status[orc_d] == "recusado"

    novo = "orcamento.nao_escolhido"
    assert _total(c, b, novo) == 1 and _total(c, d, novo) == 1
    assert _total(c, ganhador, novo) == 0
    assert _total(c, b, "orcamento.recusado") == 0  # não é a recusa individual

    # aceitar de novo não duplica nem avisa de novo
    assert (
        acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc_g}).status_code
        >= 400
    )
    assert _total(c, b, novo) == 1 and _total(c, d, novo) == 1


def test_recusa_individual_no_postgres_so_tem_o_evento_de_recusa(c):
    pedido_id = abrir_pedido(c)
    pro = _novo_profissional(c)
    orc = _orcar(c, pedido_id, pro)
    r = post(c, f"/v1/pedidos/{pedido_id}/orcamentos/{orc}/recusar", "cliente")
    assert r.status_code == 200, r.text
    assert _total(c, pro, "orcamento.recusado") == 1
    assert _total(c, pro, "orcamento.nao_escolhido") == 0
