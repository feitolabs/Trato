"""B34 (Parte 1) no Postgres: pedido comum avisa profissional elegível e grava notificação."""

from __future__ import annotations

import uuid

import pytest

from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.postgres import NotificacoesServicoPostgres
from trato.notificacoes.servico import ServicoNotificacoes

from .test_rotas_app_postgres import post

pytestmark = pytest.mark.integracao


def test_pedido_comum_avisa_elegivel_e_ignora_nao_aprovado_no_postgres(cenario):
    c = cenario
    notif_repo = NotificacoesServicoPostgres(c.banco)
    notif = ServicoNotificacoes(
        notif_repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True), c.contexto.agora
    )
    ligar_ao_contexto(c.cliente.app, c.contexto, notif)
    c.cliente.app.state.notificador = notif

    # Cria um segundo profissional pendente na mesma categoria/cidade: não pode receber.
    pendente_id = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (pendente_id,))
        con.execute(
            "insert into public.usuarios (id, nome) values (%s, 'Pro Pendente')",
            (pendente_id,),
        )
        con.execute(
            "insert into public.perfis_profissional (usuario_id) values (%s)",
            (pendente_id,),
        )
        con.execute(
            "insert into public.profissional_categorias (profissional_id, categoria_id) "
            "values (%s, %s)",
            (pendente_id, c.categoria_id),
        )
        con.execute(
            "insert into public.profissional_regioes (profissional_id, cidade_id) values (%s, %s)",
            (pendente_id, c.cidade_id),
        )
        # Garante que o profissional principal do cenário está aprovado e ativo na categoria/cidade.
        con.execute(
            "update public.perfis_profissional set status = 'aprovado' where usuario_id = %s",
            (c.ids["profissional"],),
        )
        con.execute(
            "insert into public.profissional_categorias (profissional_id, categoria_id) "
            "values (%s, %s) on conflict do nothing",
            (c.ids["profissional"], c.categoria_id),
        )
        con.execute(
            "insert into public.profissional_regioes (profissional_id, cidade_id) "
            "values (%s, %s) on conflict do nothing",
            (c.ids["profissional"], c.cidade_id),
        )

    r = post(
        c,
        "/v1/pedidos",
        "cliente",
        {
            "categoria_id": c.categoria_id,
            "cidade_id": c.cidade_id,
            "titulo": "Trocar tomada da cozinha",
            "descricao": "Tomada parou de funcionar ontem.",
            "endereco": {
                "logradouro": "Rua Privada 123",
                "numero": "45",
                "bairro": "Vila Nova",
                "cep": "01001-000",
            },
        },
    )
    assert r.status_code == 201, r.text
    pedido_id = r.json()["id"]

    with c.local.admin() as con:
        linhas_ok = con.execute(
            "select tipo, titulo, corpo from public.notificacoes "
            "where usuario_id = %s and tipo = %s and dados->>'pedido_id' = %s",
            (c.ids["profissional"], Evento.PEDIDO_NOVO.value, pedido_id),
        ).fetchall()
        linhas_pend = con.execute(
            "select id from public.notificacoes "
            "where usuario_id = %s and tipo = %s and dados->>'pedido_id' = %s",
            (pendente_id, Evento.PEDIDO_NOVO.value, pedido_id),
        ).fetchall()

    assert len(linhas_ok) == 1
    assert linhas_ok[0][1] == "Novo pedido perto de você"
    assert "Vila Nova" in (linhas_ok[0][2] or "")
    assert "Rua Privada" not in (linhas_ok[0][2] or "")
    assert linhas_pend == []
