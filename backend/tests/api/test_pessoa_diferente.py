"""BE-95-96: relato de pessoa diferente cancela com reembolso integral (Termos 9.5) e a cautela
atrasada aparece depois de 24 h (9.6). Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

from conftest import cab
from test_ausencia_cliente import LONGE, registrado, remarcado_para_longe
from test_cliente_bloqueado_pedido import bloquear
from test_fixseg import com_equipe
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401
from test_termos_m2_dinheiro import custodia, total_estornado

from trato.pedidos.estados import Estado

URL = "/v1/admin/incidentes"


def relatar(f, pid, quem="t-cliente"):
    return f.chamar("POST", f"/v1/pedidos/{pid}/seguranca/pessoa-diferente", quem, {})


def agendado(f) -> tuple[str, str]:
    pid = f.aceitar()
    cobranca = f.pagar(pid)
    f.agendar(pid)
    return pid, cobranca["id"]


def estado(f, pid) -> Estado:
    return f.ctx.pedidos.obter(pid).estado


def incidentes(f, pid):
    return f.ctx.incidentes.listar(None, pid, 100, 0)[0]


def test_relato_cancela_com_reembolso_integral_uma_vez(fluxo):
    pid, cobranca = agendado(fluxo)
    with ThreadPoolExecutor(4) as grupo:
        respostas = list(grupo.map(lambda _: relatar(fluxo, pid), range(4)))
    respostas.append(relatar(fluxo, pid))
    assert {r.status_code for r in respostas} == {200}, [r.text for r in respostas]
    assert all(r.json()["cancelado"] for r in respostas)
    assert len({r.json()["protocolo"] for r in respostas}) == 1
    assert estado(fluxo, pid) is Estado.CANCELADO and custodia(fluxo, pid) == 0
    assert total_estornado(fluxo, cobranca) == VALOR
    assert len(incidentes(fluxo, pid)) == 1  # a investigação segue aberta


def test_so_o_cliente_e_mesmo_bloqueado(fluxo):
    pid, _ = agendado(fluxo)
    assert relatar(fluxo, pid, "t-outro-cliente").status_code == 404
    assert relatar(fluxo, pid, "t-prof").status_code == 403
    assert estado(fluxo, pid) is Estado.AGENDADO and incidentes(fluxo, pid) == []
    bloquear(fluxo, "bloqueio_preventivo")  # suspensão cancelaria o pedido (20.6)
    r = relatar(fluxo, pid)
    assert r.status_code == 200 and r.json()["cancelado"], r.text


def test_depois_do_check_in_so_registra_e_segura_o_valor(fluxo):
    pid, cobranca = agendado(fluxo)
    fluxo.iniciar(pid)
    r = relatar(fluxo, pid)
    assert r.status_code == 200 and r.json()["cancelado"] is False, r.text
    assert relatar(fluxo, pid).json()["protocolo"] == r.json()["protocolo"]
    assert estado(fluxo, pid) is Estado.EM_ANDAMENTO and custodia(fluxo, pid) == VALOR
    assert total_estornado(fluxo, cobranca) == 0 and len(incidentes(fluxo, pid)) == 1


def test_com_ausencia_do_cliente_registrada_quem_decide_e_a_equipe(fluxo):
    pid, _ = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    r = relatar(fluxo, pid)
    assert r.status_code == 200 and r.json()["cancelado"] is False, r.text
    assert estado(fluxo, pid) is Estado.AGENDADO and custodia(fluxo, pid) == VALOR


def test_pedido_sem_contratacao_e_recusado(fluxo):
    pid = fluxo.aceitar()
    assert relatar(fluxo, pid).status_code == 409
    assert incidentes(fluxo, pid) == []


def abrir_no_painel(f, pid, tipo="pessoa_diferente") -> str:
    corpo = {
        "tipo": tipo,
        "descricao": "Relato recebido por telefone.",
        "contato": "11 99999-0000",
        "canal": "telefone",
        "pedido_id": pid,
    }
    r = f.http.post(URL, json=corpo, headers=cab("t-seguranca"))
    assert r.status_code == 201, r.text
    assert r.json()["cautela_atrasada"] is False
    return r.json()["id"]


def medida(f, iid, texto="Cancelado com reembolso integral."):
    corpo = {"tipo": "cancelar_pedido_reembolso", "descricao": texto}
    return f.http.post(f"{URL}/{iid}/medidas", json=corpo, headers=cab("t-seguranca"))


def test_medida_do_painel_executa_o_cancelamento_uma_vez(fluxo):
    com_equipe(fluxo.amb)
    pid, cobranca = agendado(fluxo)
    iid = abrir_no_painel(fluxo, pid)
    assert estado(fluxo, pid) is Estado.AGENDADO  # abrir não cancela
    assert medida(fluxo, iid).status_code == 200
    assert medida(fluxo, iid).status_code == 200
    assert medida(fluxo, iid, "Registro repetido com outro texto.").status_code == 200
    assert estado(fluxo, pid) is Estado.CANCELADO and custodia(fluxo, pid) == 0
    assert total_estornado(fluxo, cobranca) == VALOR


def test_painel_nao_cancela_servico_iniciado_nem_outro_tipo(fluxo):
    com_equipe(fluxo.amb)
    pid, _ = agendado(fluxo)
    outro = abrir_no_painel(fluxo, pid, "comportamento_suspeito")
    assert medida(fluxo, outro).status_code == 200  # só registra
    assert estado(fluxo, pid) is Estado.AGENDADO
    fluxo.iniciar(pid)
    iid = abrir_no_painel(fluxo, pid)
    r = medida(fluxo, iid)
    assert r.status_code == 409, r.text
    assert fluxo.ctx.incidentes.obter(iid).medidas == ()
    assert custodia(fluxo, pid) == VALOR


def test_cautela_atrasada_depois_de_24_horas(fluxo):
    com_equipe(fluxo.amb)
    pid, _ = agendado(fluxo)
    iid = abrir_no_painel(fluxo, pid)

    def atrasada() -> bool:
        return fluxo.http.get(f"{URL}/{iid}", headers=cab("t-seguranca")).json()["cautela_atrasada"]

    fluxo.amb.relogio.avancar(hours=24)
    assert atrasada() is False
    fluxo.amb.relogio.avancar(seconds=1)
    assert atrasada() is True
