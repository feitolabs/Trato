"""TERMOS-ET4a: desistir do pedido (7.1 a 7.4 e 7.9), consentimento (7.3) e decisão do analista.
Memória e provedor falso; AGORA = 29/10/2026 09:00 em Brasília."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

import pytest
from admin_ambiente import PEDIDO, adm  # noqa: F401 - fixture
from admin_ambiente import cab as cab_admin
from conftest import AGORA, CLIENTE, PROFISSIONAL
from test_fluxo_pagamento_e2e import VALOR, Fluxo, fluxo  # noqa: F401 - fixtures
from test_termos_be2 import enviados, ouvir
from test_termos_m2_dinheiro import custodia, parcelado, total_estornado

from trato.api.desistencia import arrependimento_ate
from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Estado
from trato.persistencia.cancelamentos import Cancelamento

# AGORA + 7 dias corridos em Brasília: 05/11 23:59:59 BRT = 06/11 02:59:59 UTC
ULTIMO_INSTANTE = datetime(2026, 11, 6, 2, 59, 59, tzinfo=UTC)
DEPOIS = datetime(2026, 11, 6, 3, 0, 0, tzinfo=UTC)


def desistir(f: Fluxo, pid: str, corpo=None, quem="t-cliente"):
    return f.chamar("POST", f"/v1/pedidos/{pid}/desistir", quem, corpo)


def situacao(f: Fluxo, pid: str, quem="t-cliente"):
    return f.chamar("GET", f"/v1/pedidos/{pid}/desistencia", quem)


def pago(f: Fluxo, agendado: bool = True) -> tuple[str, str]:
    pid = f.aceitar()
    cobranca = f.pagar(pid)
    if agendado:
        f.agendar(pid)
    return pid, cobranca["id"]


def iniciado(f: Fluxo, consentimento: bool) -> str:
    pid = f.aceitar()
    r = f.chamar(
        "POST",
        f"/v1/pedidos/{pid}/cobranca",
        "t-cliente",
        {"meio": "pix", "consentimento_execucao_imediata": consentimento},
    )
    assert r.status_code == 201, r.text
    f.fake.marcar_paga(r.json()["id"])
    assert f.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, r.json()["id"]).status_code == 200
    f.agendar(pid)
    f.iniciar(pid)
    return pid


def estado(f: Fluxo, pid: str) -> Estado:
    return f.ctx.pedidos.obter(pid).estado


# --- prazo -------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "contratado,ultimo_dia",
    [
        (datetime(2026, 11, 1, 2, 59, tzinfo=UTC), "2026-11-07"),  # 31/10 23:59 em Brasília
        (datetime(2026, 11, 1, 3, 0, tzinfo=UTC), "2026-11-08"),  # 01/11 00:00 em Brasília
    ],
)
def test_prazo_conta_dias_do_calendario_de_brasilia(contratado, ultimo_dia):
    ate = arrependimento_ate(contratado, 7)
    assert ate.date().isoformat() == ultimo_dia and ate.hour == 23 and ate.minute == 59
    assert ate.utcoffset() == timedelta(hours=-3)


@pytest.mark.parametrize(
    "agora,dentro,tipo",
    [
        (ULTIMO_INSTANTE, True, "desistencia_arrependimento"),
        (DEPOIS, False, "cancelamento_cliente"),
    ],
)
def test_setimo_dia_e_o_seguinte_sem_check_in_devolvem_tudo(fluxo, agora, dentro, tipo):  # noqa: F811
    pid, cobranca = pago(fluxo)
    fluxo.amb.relogio.agora = agora
    antes = situacao(fluxo, pid).json()
    assert antes["pode_desistir"] and antes["efeito"] == "reembolso_integral"
    assert antes["dentro_do_arrependimento"] is dentro
    r = desistir(fluxo, pid)  # sem motivo e sem corpo
    assert r.status_code == 200, r.text
    assert r.json()["situacao"] == "reembolso_integral"
    assert r.json()["reembolso_centavos"] == VALOR
    assert r.json()["estado_pedido"] == "cancelado" and r.json()["protocolo"]
    registro = fluxo.ctx.cancelamentos.do_pedido(pid)
    assert registro.tipo == tipo and registro.dentro_do_arrependimento is dentro
    assert registro.status == "cancelado_sem_retencao" and registro.recebido_em == agora
    assert total_estornado(fluxo, cobranca) == VALOR and custodia(fluxo, pid) == 0
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_prazo_conta_do_pagamento_confirmado_e_nao_do_aceite(fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    fluxo.amb.relogio.avancar(hours=20)  # paga no dia seguinte ao aceite
    fluxo.pagar(pid)
    dados = situacao(fluxo, pid).json()
    assert dados["arrependimento_ate"].startswith("2026-11-06T23:59:59")


def test_menos_de_24_horas_do_horario_tambem_devolve_tudo(fluxo):  # noqa: F811
    pid, cobranca = pago(fluxo)
    fluxo.amb.relogio.agora = AGORA + timedelta(days=2, hours=-1)
    r = desistir(fluxo, pid, {"motivo": "Mudei de ideia"})
    assert r.json()["reembolso_centavos"] == VALOR
    assert total_estornado(fluxo, cobranca) == VALOR
    assert fluxo.ctx.cancelamentos.do_pedido(pid).motivo == "Mudei de ideia"


def test_parcelado_volta_por_inteiro(fluxo):  # noqa: F811
    pid, cobranca = parcelado(fluxo)
    cobrado = fluxo.servico.cobrancas.obter(cobranca).valor_centavos
    assert desistir(fluxo, pid).json()["reembolso_centavos"] == cobrado
    assert total_estornado(fluxo, cobranca) == cobrado and custodia(fluxo, pid) == 0


@pytest.mark.parametrize("ate", ["aberto", "orcamento_aceito", "pago_e_retido"])
def test_antes_de_pagar_ou_agendar_tambem_desiste(fluxo, ate):  # noqa: F811
    if ate == "aberto":
        pid = fluxo.chamar("POST", "/v1/pedidos", "t-cliente").json()["id"]
    elif ate == "orcamento_aceito":
        pid = fluxo.aceitar()
        fluxo.cobrar(pid)
    else:
        pid, _ = pago(fluxo, agendado=False)
    r = desistir(fluxo, pid)
    assert r.status_code == 200, r.text
    assert r.json()["reembolso_centavos"] == (VALOR if ate == "pago_e_retido" else 0)
    assert estado(fluxo, pid) is Estado.CANCELADO


# --- repetição, concorrência e quem pode ---------------------------------------------------------


def test_repetir_devolve_o_mesmo_registro_e_um_so_estorno(fluxo):  # noqa: F811
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid, cobranca = pago(fluxo)
    primeiro = desistir(fluxo, pid).json()
    fluxo.amb.relogio.avancar(days=30)
    assert desistir(fluxo, pid, {"motivo": "de novo"}).json() == primeiro
    assert len(fluxo.servico.ordens.do_pedido(pid)) == 1
    assert total_estornado(fluxo, cobranca) == VALOR
    assert enviados(email, "Desistência recebida") == sorted([CLIENTE.id, PROFISSIONAL.id])
    assert situacao(fluxo, pid).json()["registro"] == primeiro


@pytest.mark.parametrize("com_check_in", [False, True])
def test_oito_toques_juntos_geram_um_registro_e_um_efeito(fluxo, com_check_in):  # noqa: F811
    pid = iniciado(fluxo, True) if com_check_in else pago(fluxo)[0]
    respostas = []
    threads = [
        threading.Thread(target=lambda: respostas.append(desistir(fluxo, pid))) for _ in range(8)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert [r.status_code for r in respostas] == [200] * 8
    assert len({r.json()["protocolo"] for r in respostas}) == 1
    assert len(fluxo.servico.ordens.do_pedido(pid)) == (0 if com_check_in else 1)
    abertas = [e for e in fluxo.ctx.pedidos.eventos(pid) if e.acao.value == "abrir_disputa"]
    assert len(abertas) == (1 if com_check_in else 0)


def test_so_o_cliente_do_pedido(fluxo):  # noqa: F811
    pid, _ = pago(fluxo)
    assert desistir(fluxo, pid, quem="t-prof").status_code == 403
    assert situacao(fluxo, pid, "t-prof").status_code == 403
    assert desistir(fluxo, pid, quem="t-outro-cliente").status_code in (401, 403, 404)
    assert desistir(fluxo, pid, {"valor": 1}).status_code == 422
    assert estado(fluxo, pid) is Estado.AGENDADO and fluxo.servico.ordens.do_pedido(pid) == []


# --- depois do check-in (7.2 e 7.3) --------------------------------------------------------------


def test_com_pedido_expresso_abre_caso_sem_mover_dinheiro(fluxo):  # noqa: F811
    pid = iniciado(fluxo, True)
    dados = situacao(fluxo, pid).json()
    assert dados["efeito"] == "analise"
    assert dados["consentimento_execucao_imediata"] is True
    r = desistir(fluxo, pid)
    assert r.status_code == 200, r.text
    assert r.json()["situacao"] == "em_analise" and r.json()["reembolso_centavos"] is None
    assert estado(fluxo, pid) is Estado.EM_DISPUTA
    assert fluxo.ctx.disputas.obter(pid).valor_congelado == VALOR
    assert fluxo.servico.ordens.do_pedido(pid) == [] and custodia(fluxo, pid) == VALOR
    assert "proporcional" in fluxo.ctx.pedidos.eventos(pid)[-1].prova.descricao
    assert desistir(fluxo, pid).json() == r.json()


@pytest.mark.parametrize("executado", [False, True])
def test_sem_pedido_expresso_devolve_tudo_na_hora(fluxo, executado):  # noqa: F811
    pid = iniciado(fluxo, False)
    if executado:
        fluxo.encerrar_execucao(pid)
    fluxo.amb.relogio.agora = ULTIMO_INSTANTE
    assert situacao(fluxo, pid).json()["efeito"] == "reembolso_integral"
    r = desistir(fluxo, pid)
    assert r.status_code == 200, r.text
    assert r.json()["situacao"] == "reembolso_integral"
    assert r.json()["reembolso_centavos"] == VALOR and r.json()["estado_pedido"] == "cancelado"
    assert desistir(fluxo, pid).json() == r.json()
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert ordem.valor_centavos == VALOR and custodia(fluxo, pid) == 0
    assert fluxo.ctx.cancelamentos.do_pedido(pid).servico_iniciado
    assert fluxo.ctx.disputas.obter(pid) is None
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_sem_como_saber_do_consentimento_nada_sai_automatico(fluxo, monkeypatch):  # noqa: F811
    pid = iniciado(fluxo, False)
    monkeypatch.setattr(fluxo.ctx.cancelamentos, "consentimento_disponivel", lambda: False)
    assert desistir(fluxo, pid).json()["situacao"] == "em_analise"
    assert fluxo.servico.ordens.do_pedido(pid) == []


def test_sistema_so_ninguem_chama_o_cancelamento_por_arrependimento(fluxo):  # noqa: F811
    pid = iniciado(fluxo, False)
    for acao in ("cancelar_arrependimento", "cancelar_cliente_ausente"):
        assert fluxo.acao(pid, acao, "t-cliente").status_code == 403


def test_analista_decide_o_proporcional_e_o_registro_fecha(fluxo):  # noqa: F811
    pid = iniciado(fluxo, True)
    desistir(fluxo, pid)
    url = f"/v1/pedidos/{pid}/disputa/decisao"
    resposta = f"/v1/pedidos/{pid}/disputa/resposta"  # o profissional é ouvido antes
    assert fluxo.chamar("POST", resposta, "t-prof").status_code == 200
    parcial = {
        "resultado": "reembolso_parcial",
        "valor_cliente_centavos": 60_000,
        "justificativa": "40% do serviço foi executado.",
    }
    for quem in ("t-cliente", "t-prof"):  # as partes não decidem
        assert fluxo.chamar("POST", url, quem, parcial).status_code == 403
    nova_visita = {"resultado": "nova_visita", "justificativa": "Refazer o serviço."}
    assert fluxo.chamar("POST", url, "t-mediador", nova_visita).status_code == 409
    assert fluxo.ctx.cancelamentos.do_pedido(pid).status == "aguardando_analise"
    r = fluxo.chamar("POST", url, "t-mediador", parcial)
    assert r.status_code == 200, r.text
    assert fluxo.chamar("POST", url, "t-mediador", parcial).status_code == 409
    registro = fluxo.ctx.cancelamentos.do_pedido(pid)
    assert registro.status == "confirmado" and registro.reembolso_centavos == 60_000
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert ordem.valor_centavos == 60_000
    final = desistir(fluxo, pid).json()
    assert final["situacao"] == "analisado" and final["reembolso_centavos"] == 60_000
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_analista_recusa_e_o_cliente_continua_vendo_o_resultado(fluxo):  # noqa: F811
    pid = iniciado(fluxo, True)
    desistir(fluxo, pid)
    fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/resposta", "t-prof")
    corpo = {"resultado": "liberar_tudo", "justificativa": "Serviço executado por inteiro."}
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-mediador", corpo)
    assert r.status_code == 200, r.text
    registro = situacao(fluxo, pid).json()["registro"]
    assert registro["situacao"] == "analisado" and registro["reembolso_centavos"] == 0
    assert desistir(fluxo, pid).json() == registro
    assert fluxo.servico.ordens.do_pedido(pid) == []


def _caso_no_painel(adm):  # noqa: F811
    adm.semear_disputa()
    adm.contexto.cancelamentos.registrar(
        Cancelamento(
            pedido_id=PEDIDO,
            solicitado_por=CLIENTE.id,
            tipo="desistencia_arrependimento",
            status="aguardando_analise",
            recebido_em=AGORA,
            servico_iniciado=True,
            dentro_do_arrependimento=True,
        )
    )


def _decidir_no_painel(adm, quem, rota="decisao"):  # noqa: F811
    corpo = {"justificativa": "Metade do serviço foi executada."}
    if rota == "decisao":
        corpo |= {"resultado": "reembolso_parcial", "valor_cliente_centavos": 50_000}
    return adm.cliente.post(
        f"/v1/admin/disputas/{PEDIDO}/{rota}", json=corpo, headers=cab_admin(quem)
    )


@pytest.mark.parametrize(
    "quem", ["t-financeiro", "t-atendente_n1", "t-cadastro", "t-sem-linha", "t-cliente", "t-prof"]
)
def test_painel_sem_a_permissao_nao_decide_a_desistencia(adm, quem):  # noqa: F811
    _caso_no_painel(adm)
    assert _decidir_no_painel(adm, quem).status_code == 403
    assert adm.contexto.cancelamentos.do_pedido(PEDIDO).status == "aguardando_analise"
    assert adm.pedido().estado is Estado.EM_DISPUTA


def test_painel_acima_da_alcada_so_fecha_na_aprovacao(adm):  # noqa: F811
    _caso_no_painel(adm)
    adm.pagamento  # noqa: B018 - liga o serviço de pagamento
    assert _decidir_no_painel(adm, "t-mediador_sem_alcada").status_code == 200
    assert adm.contexto.cancelamentos.do_pedido(PEDIDO).status == "aguardando_analise"
    assert _decidir_no_painel(adm, "t-administrador", "aprovacao").status_code == 200
    registro = adm.contexto.cancelamentos.do_pedido(PEDIDO)
    assert registro.status == "confirmado" and registro.reembolso_centavos == 50_000
    assert (
        adm.contexto.cancelamentos.decisoes[PEDIDO][0] == "eq-mediador_sem_alcada"
    )  # quem analisou


# --- quando não cabe -----------------------------------------------------------------------------


def test_servico_iniciado_depois_do_prazo_nao_desiste(fluxo):  # noqa: F811
    pid = iniciado(fluxo, True)
    fluxo.amb.relogio.agora = DEPOIS
    r = desistir(fluxo, pid)
    assert r.status_code == 409 and "Relatar problema" in r.text
    assert estado(fluxo, pid) is Estado.EM_ANDAMENTO
    assert fluxo.ctx.cancelamentos.do_pedido(pid) is None


def test_executado_por_inteiro_com_pedido_expresso_nao_desiste(fluxo):  # noqa: F811
    pid = iniciado(fluxo, True)
    fluxo.encerrar_execucao(pid)
    assert desistir(fluxo, pid).status_code == 409
    assert fluxo.servico.ordens.do_pedido(pid) == []


def test_concluido_nao_desiste(fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    r = desistir(fluxo, pid)
    assert r.status_code == 409 and "concluído" in r.text


# --- consentimento (7.3) -------------------------------------------------------------------------


def cobrar_com(f: Fluxo, pid: str, consentimento: bool) -> dict:
    corpo = {"meio": "pix", "consentimento_execucao_imediata": consentimento}
    r = f.chamar("POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", corpo)
    assert r.status_code in (200, 201), r.text
    return r.json()


def confirmar(f: Fluxo, cobranca: str) -> None:
    f.fake.marcar_paga(cobranca)
    assert f.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca).status_code == 200


@pytest.mark.parametrize("ultima", [True, False])
def test_vale_a_escolha_da_cobranca_paga(fluxo, ultima):  # noqa: F811
    pid = fluxo.aceitar()
    primeira = cobrar_com(fluxo, pid, not ultima)
    assert cobrar_com(fluxo, pid, not ultima)["id"] == primeira["id"]  # reaproveita
    segunda = cobrar_com(fluxo, pid, ultima)
    assert segunda["id"] != primeira["id"]
    assert situacao(fluxo, pid).json()["consentimento_execucao_imediata"] is False  # não pagou
    fluxo.amb.relogio.avancar(minutes=5)
    confirmar(fluxo, segunda["id"])
    dados = situacao(fluxo, pid).json()
    assert dados["consentimento_execucao_imediata"] is ultima
    if ultima:
        quando = datetime.fromisoformat(dados["consentimento_em"])
        assert quando == AGORA + timedelta(minutes=5)


def test_sem_data_de_pagamento_conta_como_dentro_do_prazo(fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    fluxo.amb.relogio.agora = AGORA + timedelta(days=30)
    dados = situacao(fluxo, pid).json()
    assert dados["dentro_do_arrependimento"] is True and dados["contratado_em"] is None


def test_registro_de_ausencia_nao_aparece_como_desistencia(fluxo):  # noqa: F811
    pid, _ = pago(fluxo)
    fluxo.ctx.cancelamentos.registrar(
        Cancelamento(pid, "eq-med", "cliente_ausente", "proposta_retencao_enviada", AGORA)
    )
    assert situacao(fluxo, pid).json()["registro"] is None
    r = desistir(fluxo, pid)
    assert r.json()["tipo"] == "desistencia_arrependimento", r.text


@pytest.mark.parametrize("corpo,esperado", [({}, False), ({"consentimento": True}, True)])
def test_consentimento_tambem_pela_rota_do_contrato(fluxo, corpo, esperado):  # noqa: F811
    pid = fluxo.aceitar()
    envio = {"meio": "pix"}
    if corpo:
        envio["consentimento_execucao_imediata"] = True
    r = fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", envio)
    assert r.status_code in (200, 201), r.text
    confirmar(fluxo, r.json()["cobranca_id"])
    assert situacao(fluxo, pid).json()["consentimento_execucao_imediata"] is esperado
