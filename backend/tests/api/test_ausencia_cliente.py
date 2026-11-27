"""TERMOS-ET4b: cliente ausente (7.6 e 7.4). Memória e provedor falso; o serviço é pago em
29/10 e marcado para dois dias depois."""

from __future__ import annotations

import threading
from datetime import timedelta

import pytest
from conftest import AGORA, CLIENTE, PROFISSIONAL
from test_fluxo_pagamento_e2e import VALOR, Fluxo, fluxo  # noqa: F401 - fixtures
from test_termos_be2 import enviados, ouvir
from test_termos_m2_dinheiro import agendador, custodia, parcelado, total_estornado

from trato.financeiro.ledger import TAXA_TRATO, a_liberar
from trato.pedidos.estados import Estado

INICIO = AGORA + timedelta(days=2)
LONGE = timedelta(days=10)  # depois dos 7 dias do arrependimento


def prova(f: Fluxo):
    return {
        "foto": {"arquivo_id": "f1", "tirada_em": f.amb.relogio.agora.isoformat()},
        "localizacao": {"latitude": -23.5, "longitude": -46.6},
    }


def chegar(f: Fluxo, pid: str, quem="t-prof"):
    return f.chamar("POST", f"/v1/pedidos/{pid}/ausencia/chegada", quem, prova(f))


def ausente(f: Fluxo, pid: str):
    return f.acao(pid, "registrar_cliente_ausente", "t-prof", prova(f))


def ver(f: Fluxo, pid: str, quem="t-cliente"):
    return f.chamar("GET", f"/v1/pedidos/{pid}/ausencia", quem)


def justificar(f: Fluxo, pid: str, texto="Fiquei preso no hospital.", quem="t-cliente"):
    url = f"/v1/pedidos/{pid}/ausencia/justificativa"
    return f.chamar("POST", url, quem, {"texto": texto})


def estado(f: Fluxo, pid: str) -> Estado:
    return f.ctx.pedidos.obter(pid).estado


def pedido_marcado(f: Fluxo) -> tuple[str, str]:
    pid = f.aceitar()
    cobranca = f.pagar(pid)
    f.agendar(pid)
    return pid, cobranca["id"]


def registrado(f: Fluxo, pid: str, depois: timedelta = timedelta()) -> None:
    """Chegada no horário e ausência 20 minutos depois (`depois` empurra o dia do serviço)."""
    f.amb.relogio.agora = INICIO + depois
    assert chegar(f, pid).status_code == 200
    f.amb.relogio.avancar(minutes=20)
    r = ausente(f, pid)
    assert r.status_code == 200, r.text


def remarcado_para_longe(f: Fluxo) -> tuple[str, str]:
    """Pedido pago hoje e marcado para daqui a 12 dias: o serviço cai fora do arrependimento."""
    pid = f.aceitar()
    cobranca = f.pagar(pid)
    inicio = INICIO + LONGE
    janela = {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}
    assert f.acao(pid, "confirmar_agenda", "t-prof", {"janela": janela}).status_code == 200
    return pid, cobranca["id"]


def painel(f: Fluxo, pid: str, quem="t-mediador", rota="decisao", **corpo):
    base = {"motivo": "Conferido o prazo de contestação."}
    if rota == "decisao":
        base = {"justificativa": "Conferidas as fotos e o chat.", "aceitar_justificativa": False}
    return f.chamar("POST", f"/v1/admin/ausencias/{pid}/{rota}", quem, base | corpo)


RETENCAO = {
    "retencao_centavos": 30_000,
    "retencao_justificativa": "Deslocamento e material comprado para o serviço.",
    "retencao_comprovantes": ["nota-1"],
}


# --- chegada e espera ----------------------------------------------------------------------------


def test_ausencia_so_depois_de_20_minutos_sem_resposta(fluxo):  # noqa: F811
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid, _ = pedido_marcado(fluxo)
    fluxo.amb.relogio.agora = INICIO - timedelta(minutes=10)
    primeira = chegar(fluxo, pid)
    assert primeira.status_code == 200, primeira.text
    assert chegar(fluxo, pid).json() == primeira.json()
    fluxo.amb.relogio.agora = INICIO + timedelta(minutes=19, seconds=59)  # conta do horário
    assert ausente(fluxo, pid).status_code == 409
    fluxo.amb.relogio.agora = INICIO + timedelta(minutes=20)
    assert ausente(fluxo, pid).status_code == 200
    dados = ver(fluxo, pid).json()
    assert dados["status"] == "aguardando_justificativa"
    assert (
        dados["justificativa_ate"]
        == (INICIO + timedelta(hours=24, minutes=20)).isoformat()[:19] + "Z"
    )
    assert enviados(email, "Justifique a ausência") == [CLIENTE.id]
    assert ausente(fluxo, pid).status_code == 409  # repetir não reabre o prazo


def test_resposta_do_cliente_no_chat_impede_o_registro(fluxo):  # noqa: F811
    pid, _ = pedido_marcado(fluxo)
    fluxo.amb.relogio.agora = INICIO
    chegar(fluxo, pid)
    conversa = fluxo.ctx.conversas.abrir(pid, PROFISSIONAL.id)
    fluxo.amb.relogio.avancar(minutes=5)
    fluxo.ctx.conversas.enviar(conversa, CLIENTE.id, "Estou descendo")
    fluxo.amb.relogio.avancar(minutes=30)
    r = ausente(fluxo, pid)
    assert r.status_code == 409 and "respondeu" in r.text


def test_exigencia_de_chegada_vem_da_configuracao(fluxo):  # noqa: F811
    from dataclasses import replace

    pid, _ = pedido_marcado(fluxo)
    fluxo.amb.relogio.agora = INICIO
    config = fluxo.ctx.config
    config._config = replace(config.carregar(), ausencia_exigir_chegada=True)
    assert ausente(fluxo, pid).status_code == 409
    config._config = replace(config.carregar(), ausencia_exigir_chegada=False)
    assert ausente(fluxo, pid).status_code == 200  # app antigo: registra, sem prazo nem efeito
    assert ver(fluxo, pid).status_code == 404


def test_falta_automatica_do_profissional_fica_bloqueada_desde_a_chegada(fluxo):  # noqa: F811
    pid, _ = pedido_marcado(fluxo)
    fluxo.amb.relogio.agora = INICIO
    chegar(fluxo, pid)
    fluxo.amb.relogio.agora = INICIO + timedelta(days=3)
    agendador(fluxo).rodar_uma_vez()
    assert estado(fluxo, pid) is Estado.AGENDADO
    assert fluxo.servico.ordens.do_pedido(pid) == []


def test_so_o_profissional_chega_e_so_o_cliente_justifica(fluxo):  # noqa: F811
    pid, _ = pedido_marcado(fluxo)
    fluxo.amb.relogio.agora = INICIO
    assert chegar(fluxo, pid, "t-cliente").status_code == 403
    registrado(fluxo, pid)
    assert justificar(fluxo, pid, quem="t-prof").status_code == 403


# --- justificativa -------------------------------------------------------------------------------


@pytest.mark.parametrize("atraso,esperado", [(timedelta(), 200), (timedelta(seconds=1), 409)])
def test_prazo_de_24_horas_no_limite(fluxo, atraso, esperado):  # noqa: F811
    pid, _ = pedido_marcado(fluxo)
    registrado(fluxo, pid)
    fluxo.amb.relogio.avancar(hours=24)
    fluxo.amb.relogio.agora += atraso
    assert justificar(fluxo, pid).status_code == esperado


def test_justificativa_e_gravada_uma_vez(fluxo):  # noqa: F811
    pid, _ = pedido_marcado(fluxo)
    registrado(fluxo, pid)
    primeira = justificar(fluxo, pid)
    assert primeira.json()["status"] == "em_analise"
    assert justificar(fluxo, pid).json() == primeira.json()
    assert justificar(fluxo, pid, "Outra história.").status_code == 409


def test_aceita_remarca_sem_custo(fluxo):  # noqa: F811
    pid, _ = pedido_marcado(fluxo)
    registrado(fluxo, pid)
    justificar(fluxo, pid)
    r = painel(fluxo, pid, aceitar_justificativa=True)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "justificativa_aceita"
    assert estado(fluxo, pid) is Estado.AGENDADO and custodia(fluxo, pid) == VALOR
    inicio = fluxo.amb.relogio.agora + timedelta(days=3)
    proposta = {
        "nova_janela_inicio": inicio.isoformat(),
        "nova_janela_fim": (inicio + timedelta(hours=3)).isoformat(),
        "motivo": "Nova data combinada",
    }
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/reagendamentos", "t-cliente", proposta)
    assert r.status_code == 201, r.text
    aceite = f"/v1/pedidos/{pid}/reagendamentos/{r.json()['id']}/aceitar"
    r = fluxo.chamar("POST", aceite, "t-prof")
    assert r.status_code == 200, r.text
    assert ver(fluxo, pid).status_code == 404  # nova data: o caso antigo ficou para trás


# --- decisão e dinheiro --------------------------------------------------------------------------


@pytest.mark.parametrize("com_justificativa", [True, False])
def test_sem_retencao_devolve_tudo(fluxo, com_justificativa):  # noqa: F811
    pid, cobranca = pedido_marcado(fluxo)
    registrado(fluxo, pid)
    if com_justificativa:
        justificar(fluxo, pid)
    else:
        assert painel(fluxo, pid).status_code == 409  # o cliente ainda está no prazo
        fluxo.amb.relogio.avancar(hours=24, seconds=1)
        assert painel(fluxo, pid, aceitar_justificativa=True).status_code == 409
    r = painel(fluxo, pid)
    assert r.status_code == 200, r.text
    esperado = "justificativa_recusada" if com_justificativa else "expirada_sem_justificativa"
    assert r.json()["status"] == esperado and r.json()["reembolso_centavos"] == VALOR
    assert painel(fluxo, pid).status_code == 409
    assert estado(fluxo, pid) is Estado.CANCELADO
    assert total_estornado(fluxo, cobranca) == VALOR and custodia(fluxo, pid) == 0
    assert len(fluxo.servico.ordens.do_pedido(pid)) == 1
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_retencao_e_mostrada_antes_e_so_depois_confirmada(fluxo):  # noqa: F811
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid, cobranca = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    justificar(fluxo, pid)
    r = painel(fluxo, pid, **RETENCAO)
    assert r.status_code == 200, r.text
    visto = ver(fluxo, pid).json()
    assert visto["retencao_centavos"] == 30_000 and visto["retencao_comprovantes"] == ["nota-1"]
    assert visto["cancelamento_status"] == "proposta_retencao_enviada"
    assert estado(fluxo, pid) is Estado.AGENDADO and fluxo.servico.ordens.do_pedido(pid) == []
    assert enviados(email, "Ausência analisada") == sorted([CLIENTE.id, PROFISSIONAL.id])
    # o cliente não troca a análise por um cancelamento comum
    assert fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "x"}).status_code == 409
    assert fluxo.chamar("POST", f"/v1/pedidos/{pid}/desistir", "t-cliente").status_code == 409
    fluxo.amb.relogio.avancar(days=10)  # passou o prazo de contestação (8.7)
    for _ in range(2):
        painel(fluxo, pid, rota="confirmar")
    assert estado(fluxo, pid) is Estado.CANCELADO
    assert total_estornado(fluxo, cobranca) == VALOR - 30_000 and custodia(fluxo, pid) == 0
    assert fluxo.ctx.ledger.saldo_da_conta(a_liberar(PROFISSIONAL.id), pid) == 30_000
    assert fluxo.repasse(pid).valor_bruto_centavos == 30_000
    assert ver(fluxo, pid).json()["cancelamento_status"] == "confirmado"
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_analista_pode_retirar_a_retencao(fluxo):  # noqa: F811
    pid, cobranca = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    justificar(fluxo, pid)
    painel(fluxo, pid, **RETENCAO)
    r = painel(fluxo, pid, rota="confirmar", retirar_retencao=True)
    assert r.status_code == 200, r.text
    assert r.json()["retencao_centavos"] == 0 and total_estornado(fluxo, cobranca) == VALOR


def test_proposta_de_horario_remarcado_nao_se_confirma(fluxo):  # noqa: F811
    pid, cobranca = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    justificar(fluxo, pid)
    painel(fluxo, pid, **RETENCAO)
    inicio = fluxo.amb.relogio.agora + timedelta(days=3)
    proposta = {
        "nova_janela_inicio": inicio.isoformat(),
        "nova_janela_fim": (inicio + timedelta(hours=3)).isoformat(),
        "motivo": "Nova data combinada",
    }
    base = f"/v1/pedidos/{pid}/reagendamentos"
    r = fluxo.chamar("POST", base, "t-cliente", proposta)
    assert fluxo.chamar("POST", f"{base}/{r.json()['id']}/aceitar", "t-prof").status_code == 200
    assert painel(fluxo, pid, rota="confirmar").status_code == 409
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/desistir", "t-cliente")
    assert r.status_code == 200, r.text
    assert r.json()["situacao"] == "reembolso_integral"
    assert total_estornado(fluxo, cobranca) == VALOR


def test_com_parcelado_volta_o_pago_menos_a_retencao(fluxo):  # noqa: F811
    pid, cobranca = parcelado(fluxo)
    cobrado = fluxo.servico.cobrancas.obter(cobranca).valor_centavos
    fluxo.amb.relogio.agora = INICIO + LONGE  # fora dos 7 dias
    janela = fluxo.ctx.pedidos.obter(pid).janela
    assert janela.inicio < fluxo.amb.relogio.agora
    assert chegar(fluxo, pid).status_code == 200
    fluxo.amb.relogio.avancar(minutes=20)
    assert ausente(fluxo, pid).status_code == 200
    justificar(fluxo, pid)
    assert painel(fluxo, pid, **RETENCAO).status_code == 200
    fluxo.amb.relogio.avancar(days=10)
    assert painel(fluxo, pid, rota="confirmar").status_code == 200
    assert total_estornado(fluxo, cobranca) == cobrado - 30_000
    assert fluxo.ctx.ledger.saldo_da_conta(a_liberar(PROFISSIONAL.id), pid) == 30_000
    assert fluxo.ctx.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0 and custodia(fluxo, pid) == 0
    fluxo.ctx.ledger.livro.verificar_partidas()


@pytest.mark.parametrize(
    "mudanca,codigo",
    [
        ({"retencao_centavos": 30_001}, 422),
        ({"retencao_comprovantes": []}, 422),
        ({"retencao_justificativa": "curta"}, 422),
        ({"retencao_centavos": 100.5}, 422),
        ({"aceitar_justificativa": True}, 422),
    ],
)
def test_retencao_acima_de_30_ou_sem_prova_e_recusada(fluxo, mudanca, codigo):  # noqa: F811
    pid, _ = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    justificar(fluxo, pid)
    assert painel(fluxo, pid, **(RETENCAO | mudanca)).status_code == codigo
    assert ver(fluxo, pid).json()["status"] == "em_analise"


def test_dentro_dos_7_dias_nao_ha_retencao_e_o_cliente_pode_cancelar(fluxo):  # noqa: F811
    pid, cobranca = pedido_marcado(fluxo)
    registrado(fluxo, pid)
    justificar(fluxo, pid)
    r = painel(fluxo, pid, **RETENCAO)
    assert r.status_code == 409 and "7 dias" in r.text
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/desistir", "t-cliente")
    assert r.status_code == 200, r.text
    assert total_estornado(fluxo, cobranca) == VALOR


@pytest.mark.parametrize("quem", ["t-financeiro", "t-cliente", "t-prof"])
def test_sem_permissao_nao_decide(fluxo, quem):  # noqa: F811
    pid, _ = pedido_marcado(fluxo)
    registrado(fluxo, pid)
    justificar(fluxo, pid)
    for rota in ("decisao", "confirmar"):
        assert painel(fluxo, pid, quem, rota).status_code == 403
    assert estado(fluxo, pid) is Estado.AGENDADO


def test_oito_decisoes_juntas_um_so_estorno(fluxo):  # noqa: F811
    pid, cobranca = pedido_marcado(fluxo)
    registrado(fluxo, pid)
    justificar(fluxo, pid)
    codigos = []
    threads = [
        threading.Thread(target=lambda: codigos.append(painel(fluxo, pid).status_code))
        for _ in range(8)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(codigos) == [200] + [409] * 7
    assert total_estornado(fluxo, cobranca) == VALOR
    assert len(fluxo.servico.ordens.do_pedido(pid)) == 1


def test_fila_so_mostra_o_que_falta_decidir(fluxo):  # noqa: F811
    pid, _ = pedido_marcado(fluxo)
    registrado(fluxo, pid)

    def fila():
        return fluxo.chamar("GET", "/v1/admin/ausencias", "t-mediador").json()

    assert [c["pedido_id"] for c in fila()] == [pid]
    justificar(fluxo, pid)
    painel(fluxo, pid)
    assert fila() == []
