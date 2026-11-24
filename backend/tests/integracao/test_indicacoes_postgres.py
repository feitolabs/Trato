"""Indique e Ganhe no Postgres: código, aplicar, gatilho e liberação com as constraints reais."""

from __future__ import annotations

import uuid
from dataclasses import replace
from datetime import timedelta

import pytest

from trato.agendador.executor import ExecutorContexto
from trato.api.indicacoes import acionar_gatilho

from .test_dinheiro_postgres import contratar, pagar_pelo_webhook
from .test_fluxo_postgres import agora
from .test_rotas_app_postgres import get, post

pytestmark = pytest.mark.integracao


def _usuario_novo(c, nome: str) -> str:
    chave = f"novo-{uuid.uuid4().hex[:8]}"
    uid = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (uid,))
        con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, nome))
    c.ids[chave] = uid
    return chave


def test_codigo_aplicar_gatilho_e_liberacao_no_postgres(cenario):
    c = cenario
    indicador = "profissional2"

    # Código pessoal: estável, no formato do banco, e o mesmo nas duas chamadas.
    primeiro = get(c, "/v1/indicacoes/meu-codigo", indicador)
    assert primeiro.status_code == 200, primeiro.text
    codigo = primeiro.json()["codigo"]
    assert 6 <= len(codigo) <= 12 and codigo == codigo.upper()
    assert get(c, "/v1/indicacoes/meu-codigo", indicador).json()["codigo"] == codigo
    assert get(c, "/v1/indicacoes/meu-codigo", "equipe1").status_code == 403

    # Aplicar: conta nova entra (profissional indica cliente = 150/300), a 2ª tentativa dá 409.
    novo = _usuario_novo(c, "Beatriz Almeida Prado")
    r = post(c, "/v1/indicacoes/aplicar", novo, {"codigo": f" {codigo.lower()} "})
    assert r.status_code == 201, r.text
    assert (r.json()["tipo"], r.json()["bonus_indicado_tratinhos"]) == ("profissional_cliente", 300)
    segunda = post(c, "/v1/indicacoes/aplicar", novo, {"codigo": codigo})
    assert segunda.status_code == 409
    assert segunda.json()["detail"] == "Você já utilizou um código de indicação."
    assert post(c, "/v1/indicacoes/aplicar", indicador, {"codigo": codigo}).status_code == 422
    assert post(c, "/v1/indicacoes/aplicar", novo, {"codigo": "ZZZZZZZZ"}).status_code in (404, 409)
    nao = post(c, "/v1/indicacoes/aplicar", _usuario_novo(c, "Outro Nome"), {"codigo": "ZZZZZZZZ"})
    assert nao.status_code == 404

    # Quem já pediu serviço (o cliente do cenário) não usa mais código.
    contratado = contratar(c)
    assert post(c, "/v1/indicacoes/aplicar", "cliente", {"codigo": codigo}).status_code == 409

    # Lista do indicador: só nome curto.
    lista = get(c, "/v1/indicacoes/meu-codigo", indicador).json()["indicacoes"]
    assert any(i["indicado_nome"] == "Beatriz P." and i["status"] == "cadastrado" for i in lista)

    # Gatilho: o cliente do cenário (indicado por vínculo direto) paga um serviço de R$ 900.
    repo = c.contexto.indicacoes
    vinculo = repo.criar(
        c.ids[indicador], c.ids["cliente"], codigo, "profissional_cliente", 150, 300, agora()
    )
    assert pagar_pelo_webhook(c, contratado).status_code == 200
    pedido = c.contexto.pedidos.obter(contratado)
    armadas = acionar_gatilho(c.contexto, pedido, agora())
    assert [a.id for a in armadas] == [vinculo.id]
    assert acionar_gatilho(c.contexto, pedido, agora()) == []  # só o 1º serviço arma
    armada = repo.do_indicado(c.ids["cliente"])
    assert armada.status == "aguardando_liberacao" and armada.pedido_gatilho_id == contratado
    assert armada.liberacao_prevista_em - armada.criado_em >= timedelta(days=6)
    resumo = get(c, "/v1/indicacoes/meu-codigo", indicador).json()["resumo"]
    assert resumo["aguardando_liberacao"] == 1 and resumo["limite_mensal_restante"] == 4

    # Liberação: só depois dos 7 dias, uma vez, nas carteiras certas e com a chave idempotente.
    moedas = c.contexto.moedas
    moedas.salvar_config(replace(moedas.config(), ativo=True))
    executor = ExecutorContexto(c.contexto)
    assert executor.liberar_indicacoes(agora() + timedelta(days=3)) == 0
    assert executor.liberar_indicacoes(agora() + timedelta(days=8)) == 1
    assert executor.liberar_indicacoes(agora() + timedelta(days=9)) == 0
    with c.local.admin() as con:
        linhas = con.execute(
            "select usuario_id::text, quantidade, carteira, tipo, expira_em - criada_em "
            "from public.moedas_lancamentos where chave_idempotencia like %s "
            "order by chave_idempotencia",
            (f"indicacao:{vinculo.id}:%",),
        ).fetchall()
    assert [(l[0], l[1], l[2], l[3]) for l in linhas] == [  # noqa: E741
        (c.ids["cliente"], 300, "cliente", "bonus_indicacao"),  # indicado
        (c.ids[indicador], 150, "profissional", "bonus_indicacao"),  # indicador
    ]
    assert all(l[4] == timedelta(days=90) for l in linhas)  # noqa: E741
    assert repo.do_indicado(c.ids["cliente"]).status == "liberado"
    final = get(c, "/v1/indicacoes/meu-codigo", indicador).json()["resumo"]
    assert final["liberadas"] == 1 and final["aguardando_liberacao"] == 0
