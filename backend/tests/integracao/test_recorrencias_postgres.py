"""Serviço recorrente no Postgres: série, visita única por data, pedido da visita e transições."""

from __future__ import annotations

from datetime import timedelta

import pytest

from trato.agendador.executor import ExecutorContexto

from .test_b32_nota_decimal_postgres import _concluir
from .test_fluxo_postgres import agora
from .test_rotas_app_postgres import get, post

pytestmark = pytest.mark.integracao

URL = "/v1/recorrencias"


def test_recorrencia_completa_no_postgres(cenario):
    c = cenario
    origem = _concluir(c)
    primeira = agora() + timedelta(hours=30)
    corpo = {
        "pedido_origem_id": origem,
        "frequencia": "quinzenal",
        "proxima_visita_em": primeira.isoformat(),
    }

    # Propor (cliente) -> aceitar (só a outra parte) -> ativa.
    r = post(c, URL, "cliente", corpo)
    assert r.status_code == 201, r.text
    rid = r.json()["id"]
    assert r.json()["valor_centavos"] > 0 and r.json()["status"] == "proposta"
    assert post(c, URL, "profissional", corpo).status_code == 409  # já existe série para o pedido
    assert post(c, f"{URL}/{rid}/aceitar", "cliente").status_code == 403
    ok = post(c, f"{URL}/{rid}/aceitar", "profissional")
    assert ok.status_code == 200 and ok.json()["status"] == "ativa"
    assert post(c, f"{URL}/{rid}/aceitar", "profissional").status_code == 409
    assert get(c, f"{URL}/{rid}", "profissional2").status_code == 404  # terceiro
    valor = ok.json()["valor_centavos"]

    # Reajuste: só o profissional propõe, só o cliente aceita; a série não cobra nada antes.
    assert post(c, f"{URL}/{rid}/reajuste", "cliente", {"valor_centavos": 1}).status_code == 403
    proposto = post(c, f"{URL}/{rid}/reajuste", "profissional", {"valor_centavos": valor + 500})
    assert proposto.json()["valor_proposto_centavos"] == valor + 500
    assert proposto.json()["valor_centavos"] == valor

    # Agendador: gera a visita e o pedido dela (orçamento enviado, nenhuma cobrança), uma vez.
    executor = ExecutorContexto(c.contexto)
    assert executor.gerar_visitas_recorrentes(agora()) == 1
    assert executor.gerar_visitas_recorrentes(agora()) == 0
    detalhe = get(c, f"{URL}/{rid}", "cliente").json()
    (visita,) = detalhe["visitas"]
    assert visita["status"] == "agendada" and visita["pedido_id"]
    assert detalhe["proxima_visita_em"] is not None
    with c.local.admin() as con:
        pedido = con.execute(
            "select cliente_id::text, status from public.pedidos where id = %s",
            (visita["pedido_id"],),
        ).fetchone()
        orcamento = con.execute(
            "select valor_total_centavos, status from public.orcamentos where pedido_id = %s",
            (visita["pedido_id"],),
        ).fetchall()
        visitas = con.execute(
            "select count(*) from public.recorrencia_visitas where recorrencia_id = %s", (rid,)
        ).fetchone()[0]
    assert pedido[0] == c.ids["cliente"]
    assert [(o[0], o[1]) for o in orcamento] == [(valor, "enviado")]  # valor ANTIGO
    assert visitas == 1
    # o índice único (série + data) barra a mesma data de novo
    reservada = c.contexto.recorrencias.reservar_visita(rid, primeira, agora())
    assert reservada is None

    # Cliente aceita o reajuste: vale daqui para frente.
    aceite = {"valor_centavos": valor + 500}
    novo = post(c, f"{URL}/{rid}/reajuste/aceitar", "cliente", aceite)
    assert (novo.json()["valor_centavos"], novo.json()["valor_proposto_centavos"]) == (
        valor + 500,
        None,
    )
    assert post(c, f"{URL}/{rid}/reajuste/aceitar", "cliente", aceite).status_code == 409

    # Pular a visita gerada cancela o pedido; pausar/retomar/cancelar com UPDATE condicional.
    pulou = post(c, f"{URL}/{rid}/visitas/{visita['id']}/pular", "profissional")
    assert pulou.status_code == 200, pulou.text
    assert pulou.json()["visitas"][0]["status"] == "pulada"
    assert post(c, f"{URL}/{rid}/visitas/{visita['id']}/pular", "cliente").status_code == 409
    with c.local.admin() as con:
        estado = con.execute(
            "select status from public.pedidos where id = %s", (visita["pedido_id"],)
        ).fetchone()[0]
    assert estado == "cancelado"
    assert post(c, f"{URL}/{rid}/pausar", "cliente").json()["status"] == "pausada"
    assert post(c, f"{URL}/{rid}/pausar", "cliente").status_code == 409
    assert post(c, f"{URL}/{rid}/retomar", "profissional").json()["status"] == "ativa"
    cancelada = post(c, f"{URL}/{rid}/cancelar", "cliente")
    assert cancelada.json()["status"] == "cancelada"
    assert post(c, f"{URL}/{rid}/cancelar", "profissional").status_code == 409
    assert executor.gerar_visitas_recorrentes(agora() + timedelta(days=60)) == 0
    # Cancelada: pode propor outra série para o mesmo pedido.
    assert post(c, URL, "profissional", corpo).status_code == 201
