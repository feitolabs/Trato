"""BE-AVISOS-30: texto livre com contato bloqueado (9.6) e avisos com pelo menos 30 dias (4.9,
13.11, I.12 e 23.2). Memória; nada é enviado de verdade."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import CLIENTE, PROFISSIONAL, cab
from test_cautela_rotas import bloqueada, encerrar, incidente, janela
from test_fixseg import com_equipe
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401
from test_termos_be2 import ouvir

from trato.api.cautela import RELATO_RETIDO
from trato.financeiro import periodo

URL = "/v1/admin/avisos-previos"


def test_reagendamento_e_recusado_com_contato_bloqueado(fluxo):
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    iid = incidente(fluxo.ctx, pid, "bloquear_contato")
    j = janela(fluxo, 72)
    corpo = {
        "nova_janela_inicio": j["inicio"],
        "nova_janela_fim": j["fim"],
        "motivo": "Me ligue no meu número.",
    }
    url = f"/v1/pedidos/{pid}/reagendamentos"
    for quem in ("t-cliente", "t-prof"):
        r = fluxo.chamar("POST", url, quem, corpo)
        assert bloqueada(r), (quem, r.text)
    assert fluxo.chamar("GET", url, "t-prof").json() in ([], {"itens": []})
    encerrar(fluxo.ctx, iid)
    assert fluxo.chamar("POST", url, "t-cliente", corpo).status_code == 201


def test_aditivo_e_recusado_com_contato_bloqueado(fluxo):
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    iid = incidente(fluxo.ctx, pid, "bloquear_contato")
    corpo = {"descricao": "Trocar o registro", "valor_centavos": 5_000}
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/aditivos", "t-prof", corpo)
    assert bloqueada(r), r.text
    assert list(fluxo.servico.aditivos.do_pedido(pid)) == []
    encerrar(fluxo.ctx, iid)
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/aditivos", "t-prof", corpo)
    assert r.status_code == 201, r.text


def test_relato_da_disputa_fica_retido_so_para_a_outra_parte(fluxo, monkeypatch):
    pid = fluxo.ate_em_confirmacao()
    texto = "A pintura ficou manchada na sala."
    corpo = {"motivo": "mal_feito", "descricao": texto}
    assert fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa", "t-cliente", corpo).status_code == 201
    # só o Postgres guarda o relato; na memória o teste devolve o texto gravado
    monkeypatch.setattr(fluxo.ctx.disputas, "descricao", lambda _: texto, raising=False)
    iid = incidente(fluxo.ctx, pid, "bloquear_contato")

    def lido(quem):
        r = fluxo.chamar("GET", f"/v1/pedidos/{pid}/disputa", quem)
        assert r.status_code == 200, r.text
        return r.json()["descricao"]

    assert lido("t-prof") == RELATO_RETIDO
    assert lido("t-cliente") == texto
    assert fluxo.ctx.disputas.descricao(pid) == texto  # o Trato continua lendo
    encerrar(fluxo.ctx, iid)
    assert lido("t-prof") == texto


def test_retrabalho_fica_retido_so_para_o_profissional(fluxo):
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    texto = "A torneira voltou a vazar na cozinha."
    url = f"/v1/pedidos/{pid}/retrabalho"
    r = fluxo.chamar("POST", url, "t-cliente", {"descricao": texto})
    assert r.status_code == 201, r.text
    iid = incidente(fluxo.ctx, pid, "bloquear_contato")

    def lido(quem):
        return fluxo.chamar("GET", url, quem).json()[0]["descricao"]

    assert lido("t-prof") == RELATO_RETIDO
    assert lido("t-cliente") == texto
    r = fluxo.chamar("POST", f"{url}/atender", "t-prof", {"etapa": "aceitar"})
    assert r.status_code == 200 and r.json()["descricao"] == RELATO_RETIDO, r.text
    encerrar(fluxo.ctx, iid)
    assert lido("t-prof") == texto


def preparar(amb):
    com_equipe(amb)
    for pessoa in (CLIENTE.id, PROFISSIONAL.id):
        amb.contexto.usuarios.garantir(pessoa)
    _, email = ouvir(amb.cliente.app, amb.contexto)
    return email


def dia(amb, dias) -> str:
    hoje = amb.contexto.agora().astimezone(periodo.BRASILIA).date()
    return (hoje + timedelta(days=dias)).isoformat()


def termos(amb, dias=30, **extra):
    corpo = {
        "tipo": "termos",
        "referencia": "proxima",
        "vigencia": dia(amb, dias),
        "resumo": "Mudam as regras de cancelamento.",
        "motivo": "Ajuste pedido pela revisão jurídica.",
        "link": "https://exemplo.invalid/termos",
    }
    return corpo | extra


def enviar(amb, corpo, quem="t-admin"):
    return amb.cliente.post(URL, json=corpo, headers=cab(quem))


def test_prazo_minimo_repeticao_e_campos_obrigatorios(fluxo):
    amb = fluxo.amb
    preparar(amb)
    curto = enviar(amb, termos(amb, 29))
    assert curto.status_code == 422 and "30 dias" in curto.json()["detail"], curto.text
    for falta in ("resumo", "motivo", "link"):
        corpo = termos(amb)
        corpo.pop(falta)
        assert enviar(amb, corpo).status_code == 422, falta
    r = enviar(amb, termos(amb))
    assert r.status_code == 200, r.text
    primeiro = r.json()
    assert primeiro["destinatarios"] > 0 and primeiro["avisos_novos"] > 0
    assert primeiro["falhas"] == 0
    assert enviar(amb, termos(amb)).json()["avisos_novos"] == 0  # repetir não avisa de novo
    assert enviar(amb, termos(amb, 45)).json()["avisos_novos"] > 0  # data nova, aviso novo


@pytest.mark.parametrize("publicado,minimo", [(10, 30), (60, 60)])
def test_configuracao_so_aumenta_o_prazo(fluxo, publicado, minimo):
    amb = fluxo.amb
    preparar(amb)
    amb.contexto.config.parametros["aviso_previo_tratinhos_dias"] = publicado
    corpo = {
        "tipo": "tratinhos",
        "referencia": "fim",
        "vigencia": dia(amb, minimo - 1),
        "resumo": "O programa deixa de creditar novos.",
    }
    assert enviar(amb, corpo).status_code == 422
    r = enviar(amb, corpo | {"vigencia": dia(amb, minimo)})
    assert r.status_code == 200 and r.json()["antecedencia_minima_dias"] == minimo, r.text


def test_inatividade_avisa_so_a_pessoa_e_cliente_nao_envia(fluxo):
    amb = fluxo.amb
    preparar(amb)
    amb.contexto.usuarios.garantir(CLIENTE.id)
    corpo = {"tipo": "inatividade", "referencia": "2027-01", "vigencia": dia(amb, 30)}
    assert enviar(amb, corpo).status_code == 422  # falta a pessoa
    corpo["usuario_id"] = CLIENTE.id
    assert enviar(amb, corpo, "t-cliente").status_code == 403
    r = enviar(amb, corpo)
    assert r.status_code == 200 and r.json()["destinatarios"] == 1, r.text
    assert enviar(amb, corpo | {"usuario_id": "ninguem"}).status_code == 404
