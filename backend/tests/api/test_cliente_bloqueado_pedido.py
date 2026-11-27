"""BE-2AC (Termos 5.8, 20.6 e 20.10): cliente bloqueado não tem pedido concluído por prazo e só
vê, confirma e relata nos próprios pedidos já contratados. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import re
from datetime import timedelta

import pytest
from conftest import AGORA, CLIENTE, cab
from test_agendador import montar
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.api.medidas import aplicar, reverter
from trato.financeiro.ledger import TipoLancamento
from trato.pedidos.estados import Acao, Estado
from trato.persistencia.medidas import Medida
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

TIPOS = ["bloqueio_preventivo", "suspensao", "encerramento"]
LIBERADAS = {"confirmar_conclusao", "abrir_disputa"}


def bloquear(f, tipo="suspensao", quem="t-cliente", usuario=CLIENTE.id) -> Medida:
    medida, _ = aplicar(
        f.ctx,
        Medida(
            usuario_id=usuario,
            tipo=tipo,
            motivo="Análise de segurança.",
            clausulas=("20.1",),
            inicio_em=f.ctx.agora(),
            efeito="Segue a cláusula 20.6.",
            como_contestar="Pelo atendimento.",
            aplicada_por="eq-mediador",
        ),
    )
    f.amb.contexto.auth.bloqueados.add(quem)
    return medida


def por_prazo(pid) -> AcaoRotina:
    return AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"teste:{pid}", acao=Acao.CONCLUIR_POR_PRAZO
    )


def disputa(f, pid, quem="t-cliente"):
    corpo = {"motivo": "mal_feito", "descricao": "A pintura ficou manchada."}
    return f.chamar("POST", f"/v1/pedidos/{pid}/disputa", quem, corpo)


def repasses(f, pid) -> int:
    return len(f.ctx.repasses.do_pedido(pid))


def recusado(r) -> bool:
    return r.status_code == 403 and r.json().get("codigo") == "conta_bloqueada"


@pytest.mark.parametrize("tipo", TIPOS)
def test_bloqueado_nao_conclui_por_prazo_e_volta_a_regra_ao_desbloquear(fluxo, tipo):
    pid = fluxo.ate_em_confirmacao()
    medida = bloquear(fluxo, tipo)
    fluxo.amb.relogio.avancar(days=8)
    antes = fluxo.tipos(pid)
    with pytest.raises(Adiada, match="cliente_bloqueado"):
        ExecutorContexto(fluxo.ctx).executar(por_prazo(pid), fluxo.ctx.agora())
    agendador, _, _ = montar(fluxo.amb)
    for _ in range(2):  # repetir não conclui nem marca a chave
        assert agendador.rodar_uma_vez().falhas == 0
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.EM_CONFIRMACAO
    assert fluxo.tipos(pid) == antes and repasses(fluxo, pid) == 0
    assert reverter(fluxo.ctx, medida, "eq-mediador")
    agendador.rodar_uma_vez()  # a janela recomeça no desbloqueio
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.EM_CONFIRMACAO
    fluxo.amb.relogio.avancar(days=8)
    agendador.rodar_uma_vez()
    agendador.rodar_uma_vez()
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CONCLUIDO
    assert repasses(fluxo, pid) == 1


def test_profissional_bloqueado_nao_segura_a_conclusao_por_prazo(fluxo):
    pid = fluxo.ate_em_confirmacao()
    profissional = fluxo.ctx.pedidos.obter(pid).profissional_id
    bloquear(fluxo, quem="t-prof", usuario=profissional)
    fluxo.amb.relogio.avancar(days=8)
    ExecutorContexto(fluxo.ctx).executar(por_prazo(pid), fluxo.ctx.agora())
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CONCLUIDO


def test_ve_e_confirma_uma_vez_so(fluxo):
    pid = fluxo.ate_em_confirmacao()
    bloquear(fluxo)
    lista = fluxo.chamar("GET", "/v1/pedidos", "t-cliente")
    assert lista.status_code == 200 and [p["id"] for p in lista.json()] == [pid]
    visto = fluxo.pedido(pid)
    assert set(visto["acoes_permitidas"]) == LIBERADAS
    r = fluxo.acao(pid, "confirmar_conclusao", "t-cliente")
    assert r.status_code == 200 and r.json()["estado"] == "concluido", r.text
    assert r.json()["acoes_permitidas"] == []
    lancamentos = fluxo.tipos(pid)
    r = fluxo.acao(pid, "confirmar_conclusao", "t-cliente")
    assert r.status_code == 200, r.text
    assert fluxo.tipos(pid) == lancamentos and repasses(fluxo, pid) == 1
    assert TipoLancamento.REPASSE not in lancamentos  # a liberação segue o prazo de sempre


def test_relata_o_problema_e_o_valor_fica_retido(fluxo):
    pid = fluxo.ate_em_confirmacao()
    bloquear(fluxo, "encerramento")
    antes = fluxo.tipos(pid)
    r = disputa(fluxo, pid)
    assert r.status_code == 201, r.text
    assert fluxo.chamar("GET", f"/v1/pedidos/{pid}/disputa", "t-cliente").status_code == 200
    assert disputa(fluxo, pid).status_code == 409  # repetir não abre outra
    fluxo.amb.relogio.avancar(days=8)
    ExecutorContexto(fluxo.ctx).executar(por_prazo(pid), fluxo.ctx.agora())
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.EM_DISPUTA
    assert fluxo.tipos(pid) == antes and repasses(fluxo, pid) == 0


def test_nenhuma_outra_rota_nem_acao_abre(fluxo):
    """Varre a API com o id do próprio pedido contratado: só as rotas do escopo respondem."""
    pid = fluxo.ate_em_confirmacao()
    bloquear(fluxo)
    abertas = set()
    for caminho, metodos in fluxo.http.app.openapi()["paths"].items():
        if not caminho.startswith("/v1/pedidos"):
            continue
        acoes = [a.value for a in Acao] if "{acao}" in caminho else [""]
        for metodo in metodos:
            for acao in acoes:
                url = caminho.replace("{pedido_id}", pid).replace("{acao}", acao)
                url = re.sub(r"\{[^}]+\}", "x", url)
                if fluxo.http.request(metodo.upper(), url).status_code != 401:
                    continue  # pública
                r = fluxo.http.request(metodo.upper(), url, headers=cab("t-cliente"))
                if not recusado(r):
                    abertas.add(f"{metodo.upper()} {caminho} {acao}".strip())
    assert abertas == {
        "GET /v1/pedidos",
        "GET /v1/pedidos/{pedido_id}",
        "GET /v1/pedidos/{pedido_id}/disputa",
        "POST /v1/pedidos/{pedido_id}/disputa",
        # 20.10: defender-se no próprio pedido (ausência 7.6 e contestação da decisão 8.7)
        "POST /v1/pedidos/{pedido_id}/seguranca/pessoa-diferente",
        "GET /v1/pedidos/{pedido_id}/ausencia",
        "GET /v1/pedidos/{pedido_id}/ausencia/anexos",
        "POST /v1/pedidos/{pedido_id}/ausencia/justificativa",
        "POST /v1/pedidos/{pedido_id}/ausencia/contestacao",
        "GET /v1/pedidos/{pedido_id}/disputa/contestacoes",
        "POST /v1/pedidos/{pedido_id}/disputa/contestacoes",
        "POST /v1/pedidos/{pedido_id}/acoes/{acao} confirmar_conclusao",
    }
    assert recusado(fluxo.chamar("GET", "/v1/me", "t-cliente"))
    assert recusado(fluxo.chamar("GET", "/v1/pedidos?como=profissional", "t-cliente"))


@pytest.mark.parametrize("quem", ["t-outro-cliente", "t-prof"])
def test_outra_pessoa_bloqueada_nao_ve_nem_age(fluxo, quem):
    pid = fluxo.ate_em_confirmacao()
    fluxo.amb.contexto.auth.bloqueados.add(quem)
    for r in (
        fluxo.chamar("GET", "/v1/pedidos", quem),
        fluxo.chamar("GET", f"/v1/pedidos/{pid}", quem),
        fluxo.chamar("GET", "/v1/pedidos/nao-existe", quem),
        fluxo.chamar("GET", f"/v1/pedidos/{pid}/disputa", quem),
        fluxo.acao(pid, "confirmar_conclusao", quem),
        disputa(fluxo, pid, quem),
    ):
        assert recusado(r), r.text
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.EM_CONFIRMACAO


def test_pedido_ainda_nao_contratado_fica_fechado(fluxo):
    fluxo.amb.semear_pedido(Estado.ABERTO, aberto_em=AGORA - timedelta(hours=1))
    bloquear(fluxo)
    for url in ("/v1/pedidos", "/v1/pedidos/ped-1"):
        assert recusado(fluxo.chamar("GET", url, "t-cliente")), url
    pid = "ped-1"
    assert recusado(fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti."}))
