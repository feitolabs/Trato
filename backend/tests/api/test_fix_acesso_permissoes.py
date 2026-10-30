"""A2: papel errado = 403 em toda rota que lê dado de terceiros.

A matriz vem de `api/admin/papeis.py`: o teste compara a resposta de CADA papel da equipe com o
que `pode()` diz, então uma permissão nova ou trocada é pega aqui.
"""

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import AGORA, MEMBROS_EQUIPE, cab
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato import disputas
from trato.api.admin.papeis import Permissao, pode
from trato.pedidos.estados import Estado

TOKENS_EQUIPE = [*MEMBROS_EQUIPE, "t-equipe"]  # "t-equipe" (eq-1) não tem linha na tabela

# rota -> permissão que a libera para a equipe
ROTAS_PEDIDO = {
    "": Permissao.PEDIDOS_BUSCAR,
    "/eventos": Permissao.PEDIDOS_BUSCAR,
    "/orcamentos": Permissao.PEDIDOS_BUSCAR,
    "/saldo": Permissao.PAGAMENTOS_VER,
    "/extrato": Permissao.PAGAMENTOS_VER,
    "/pagamento": Permissao.PAGAMENTOS_VER,
    "/disputa": Permissao.DISPUTAS_VER,
}


def _semear(amb):
    amb.semear_pedido(Estado.EM_DISPUTA, estado_antes_da_disputa=Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro()
    cfg = amb.contexto.config.carregar().disputas
    amb.contexto.disputas.salvar(
        "ped-1",
        disputas.abrir(
            disputas.Ator.CLIENTE, 100_000, disputas.Motivo.MAL_FEITO, AGORA, AGORA, cfg
        ),
    )
    amb.contexto.conversas.abrir("ped-1", "pro-1")


def _permitido(token: str, permissao: Permissao) -> bool:
    membro = MEMBROS_EQUIPE.get(token)
    return membro is not None and pode(membro.papel, permissao)


@pytest.mark.parametrize("token", TOKENS_EQUIPE)
@pytest.mark.parametrize("rota", ROTAS_PEDIDO)
def test_equipe_so_le_o_que_a_matriz_permite(amb, rota, token):
    _semear(amb)
    r = amb.cliente.get(f"/v1/pedidos/ped-1{rota}", headers=cab(token))
    assert r.status_code == (200 if _permitido(token, ROTAS_PEDIDO[rota]) else 403), r.text


@pytest.mark.parametrize("token", TOKENS_EQUIPE)
def test_chat_so_para_quem_decide_disputa_e_so_com_disputa(amb, token):
    _semear(amb)
    r = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab(token))
    assert r.status_code == (200 if _permitido(token, Permissao.DISPUTAS_DECIDIR) else 403)


def test_chat_de_pedido_sem_disputa_e_negado_ate_ao_mediador(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    amb.contexto.conversas.abrir("ped-1", "pro-1")
    r = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-mediador"))
    assert r.status_code == 403


@pytest.mark.parametrize("token", TOKENS_EQUIPE)
@pytest.mark.parametrize("rota", ["/cobrancas", "/aditivos"])
def test_cobrancas_e_aditivos_so_com_pagamentos_ver(fluxo, rota, token):  # noqa: F811
    pid = fluxo.aceitar()
    r = fluxo.chamar("GET", f"/v1/pedidos/{pid}{rota}", token)
    assert r.status_code == (200 if _permitido(token, Permissao.PAGAMENTOS_VER) else 403)


@pytest.mark.parametrize("token", TOKENS_EQUIPE)
def test_decidir_disputa_exige_disputas_decidir(fluxo, token):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/disputa",
        "t-cliente",
        {"motivo": "mal_feito", "descricao": "Parede manchada"},
    )
    decisao = {"resultado": "reembolso_total", "justificativa": "Serviço não feito."}
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", token, decisao)
    if _permitido(token, Permissao.DISPUTAS_DECIDIR):
        assert r.status_code in (200, 409, 422), r.text  # passou da autorização
    else:
        assert r.status_code == 403


@pytest.mark.parametrize("token", TOKENS_EQUIPE)
def test_equipe_nao_age_no_pedido_pelas_rotas_do_app(amb, token):
    amb.semear_pedido(Estado.CONCLUIDO)
    r = amb.cliente.post("/v1/pedidos/ped-1/acoes/confirmar_conclusao", headers=cab(token))
    assert r.status_code == 403


@pytest.mark.parametrize(
    ("token", "esperado"),
    [("t-outro-cliente", 404), ("t-outro-prof", 404), (None, 401)],
)
@pytest.mark.parametrize("rota", [*ROTAS_PEDIDO, "/mensagens"])
def test_quem_nao_e_parte_nao_le_nada(amb, rota, token, esperado):
    _semear(amb)
    cabecalho = cab(token) if token else {}
    r = amb.cliente.get(f"/v1/pedidos/ped-1{rota}", headers=cabecalho)
    if rota == "/orcamentos" and token == "t-outro-prof":
        assert r.status_code == 404 or r.json() == []  # profissional só vê o próprio orçamento
    elif rota == "/pagamento" and token in ("t-outro-cliente", "t-outro-prof"):
        assert r.status_code in (403, 404)
    else:
        assert r.status_code == esperado


def test_leitura_da_equipe_fica_na_auditoria(amb):
    _semear(amb)
    assert (
        amb.cliente.get("/v1/pedidos/ped-1/extrato", headers=cab("t-financeiro")).status_code == 200
    )
    assert (
        amb.cliente.get("/v1/pedidos/ped-1/extrato", headers=cab("t-juridico")).status_code == 403
    )
    achados, _ = amb.admin.auditoria.listar(_filtro(), 50, 0)
    consultas = [e for e in achados if e.acao == "pedido.consulta_equipe"]
    assert [(e.ator_id, e.depois["consulta"]) for e in consultas] == [("eq-fin", "extrato")]


def _filtro():
    from trato.api.admin.repositorios import FiltroAuditoria

    return FiltroAuditoria()


def test_equipe_revogada_perde_o_acesso_na_hora(amb):
    from dataclasses import replace

    _semear(amb)
    membro = MEMBROS_EQUIPE["t-financeiro"]
    amb.admin.equipe.salvar(replace(membro, revogado_em=AGORA - timedelta(minutes=1)))
    assert (
        amb.cliente.get("/v1/pedidos/ped-1/saldo", headers=cab("t-financeiro")).status_code == 403
    )
