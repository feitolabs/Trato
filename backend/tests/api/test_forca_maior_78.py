"""BE-FORCA-MAIOR-78 (Termos 7.8 e 22.6): solicitação de isenção por força maior no app,
fila admin, aprovação de cancelamento com estorno integral sem multa, aprovação de reagendamento,
recusa, idempotência, alçada, permissões e 503 sem tabela."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace

from conftest import PROFISSIONAL
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.pedidos.estados import Estado as E

DESC = "Chuva forte e alagamento impediram o acesso ao endereço do serviço."
JUST = "Comprovante de alerta da Defesa Civil conferido pela equipe."


def _agendado(fluxo) -> str:
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    return pid


def test_aprovar_cancelar_com_estorno_integral_idempotencia_e_auditoria(fluxo):
    pid = _agendado(fluxo)

    assert (
        fluxo.chamar(
            "POST",
            f"/v1/pedidos/{pid}/forca-maior",
            "t-outro-cliente",
            {"acao_solicitada": "cancelar", "descricao": DESC, "comprovantes": ["comp-1"]},
        ).status_code
        == 403
    )

    r_sol = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/forca-maior",
        "t-cliente",
        {"acao_solicitada": "cancelar", "descricao": DESC, "comprovantes": ["comp-1"]},
    )
    assert r_sol.status_code == 201, r_sol.text
    ev = r_sol.json()
    assert ev["status"] == "pendente" and ev["solicitante_papel"] == "cliente"
    assert ev["comprovantes"] == ["comp-1"]
    assert "analista_id" not in ev and "chave_idempotencia" not in ev
    # Duplicado pendente no mesmo pedido -> 409; comprovante vazio -> 422
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/pedidos/{pid}/forca-maior",
            "t-cliente",
            {"acao_solicitada": "reagendar", "descricao": DESC, "comprovantes": []},
        ).status_code
        == 409
    )
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/pedidos/{pid}/forca-maior",
            "t-cliente",
            {"acao_solicitada": "reagendar", "descricao": DESC, "comprovantes": ["   "]},
        ).status_code
        == 422
    )

    assert len(fluxo.chamar("GET", f"/v1/pedidos/{pid}/forca-maior", "t-prof").json()) == 1
    fila = fluxo.chamar("GET", "/v1/admin/forca-maior?status=pendente", "t-mediador")
    assert fila.status_code == 200 and fila.json()["total"] == 1

    assert (
        fluxo.chamar(
            "POST",
            f"/v1/admin/forca-maior/{ev['id']}/decisao",
            "t-n1",
            {"decisao": "aprovado", "justificativa": JUST, "chave_idempotencia": "ch-fm-0001"},
        ).status_code
        == 403
    )

    med = fluxo.amb.admin.equipe.obter("eq-med")
    fluxo.amb.admin.equipe.salvar(replace(med, alcada_centavos=50_000))
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/admin/forca-maior/{ev['id']}/decisao",
            "t-mediador",
            {"decisao": "aprovado", "justificativa": JUST, "chave_idempotencia": "ch-fm-alc1"},
        ).status_code
        == 403
    )
    assert fluxo.ctx.pedidos.obter(pid).estado is E.AGENDADO
    fluxo.amb.admin.equipe.salvar(med)

    r_dec = fluxo.chamar(
        "POST",
        f"/v1/admin/forca-maior/{ev['id']}/decisao",
        "t-mediador",
        {"decisao": "aprovado", "justificativa": JUST, "chave_idempotencia": "ch-fm-0001"},
    )
    assert r_dec.status_code == 200, r_dec.text
    assert r_dec.json()["status"] == "aprovado" and r_dec.json()["idempotente"] is False
    assert fluxo.ctx.pedidos.obter(pid).estado is E.CANCELADO
    saldos = fluxo.ctx.ledger.saldos_pedido(pid, PROFISSIONAL.id)
    assert saldos.retido == 0 and saldos.a_liberar == 0
    assert fluxo.servico.ordens.do_pedido(pid)

    r_idem = fluxo.chamar(
        "POST",
        f"/v1/admin/forca-maior/{ev['id']}/decisao",
        "t-mediador",
        {"decisao": "aprovado", "justificativa": JUST, "chave_idempotencia": "ch-fm-0001"},
    )
    assert r_idem.status_code == 200 and r_idem.json()["idempotente"] is True

    assert (
        fluxo.chamar(
            "POST",
            f"/v1/admin/forca-maior/{ev['id']}/decisao",
            "t-mediador",
            {"decisao": "recusado", "justificativa": JUST, "chave_idempotencia": "ch-fm-0002"},
        ).status_code
        == 409
    )

    acoes = [e.acao for e in fluxo.amb.admin.auditoria.listar(FiltroAuditoria(), 100, 0)[0]]
    assert "forca_maior.decidido" in acoes


def test_recusar_aprovar_reagendar_e_sem_tabela(fluxo):
    pid = _agendado(fluxo)
    ev1 = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/forca-maior",
        "t-prof",
        {"acao_solicitada": "reagendar", "descricao": DESC, "comprovantes": []},
    ).json()
    r_rec = fluxo.chamar(
        "POST",
        f"/v1/admin/forca-maior/{ev1['id']}/decisao",
        "t-mediador",
        {"decisao": "recusado", "justificativa": JUST, "chave_idempotencia": "ch-fm-rec1"},
    )
    assert r_rec.status_code == 200 and r_rec.json()["status"] == "recusado"
    assert fluxo.ctx.pedidos.obter(pid).estado is E.AGENDADO

    ev2 = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/forca-maior",
        "t-cliente",
        {"acao_solicitada": "reagendar", "descricao": DESC, "comprovantes": []},
    ).json()
    r_apr = fluxo.chamar(
        "POST",
        f"/v1/admin/forca-maior/{ev2['id']}/decisao",
        "t-mediador",
        {"decisao": "aprovado", "justificativa": JUST, "chave_idempotencia": "ch-fm-reag1"},
    )
    assert r_apr.status_code == 200 and r_apr.json()["status"] == "aprovado"
    assert fluxo.ctx.pedidos.obter(pid).estado is E.AGENDADO

    # Sem status -> retorna todos os status; com status -> filtra
    todos = fluxo.chamar("GET", "/v1/admin/forca-maior", "t-mediador")
    assert todos.status_code == 200 and todos.json()["total"] == 2
    assert {i["status"] for i in todos.json()["itens"]} == {"recusado", "aprovado"}
    so_apr = fluxo.chamar("GET", "/v1/admin/forca-maior?status=aprovado", "t-mediador")
    assert so_apr.status_code == 200 and so_apr.json()["total"] == 1
    assert so_apr.json()["itens"][0]["status"] == "aprovado"

    fluxo.ctx.forca_maior.disponivel = lambda: False
    assert fluxo.chamar("GET", "/v1/admin/forca-maior", "t-mediador").status_code == 503
    assert fluxo.chamar("GET", f"/v1/pedidos/{pid}/forca-maior", "t-cliente").status_code == 503
    assert fluxo.chamar("GET", f"/v1/pedidos/{pid}", "t-cliente").status_code == 200
