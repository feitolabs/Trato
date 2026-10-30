from datetime import timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab, janela_futura

from trato.pedidos.estados import Estado, Janela, Pedido


def acao(amb, quem, acao, prova=None, pedido="ped-1"):
    corpo = {"prova": prova} if prova is not None else None
    return amb.cliente.post(f"/v1/pedidos/{pedido}/acoes/{acao}", json=corpo, headers=cab(quem))


def foto():
    return {"arquivo_id": "f1", "tirada_em": (AGORA - timedelta(minutes=5)).isoformat()}


# --- criar / consultar ------------------------------------------------------------------


def test_cliente_abre_pedido(amb):
    r = amb.cliente.post("/v1/pedidos", headers=cab("t-cliente"))

    assert r.status_code == 201
    corpo = r.json()
    assert corpo["estado"] == "aberto"
    assert corpo["cliente_id"] == CLIENTE.id
    assert "aceitar_orcamento" in corpo["acoes_permitidas"]
    assert amb.contexto.pedidos.obter(corpo["id"]) is not None


def test_profissional_nao_abre_pedido(amb):
    assert amb.cliente.post("/v1/pedidos", headers=cab("t-prof")).status_code == 403


def test_sem_login_da_401(amb):
    assert amb.cliente.post("/v1/pedidos").status_code == 401
    assert amb.cliente.get("/v1/pedidos", headers=cab("token-desconhecido")).status_code == 401


def test_listar_e_ver_pedido(amb):
    amb.semear_pedido(Estado.AGENDADO)

    lista = amb.cliente.get("/v1/pedidos", headers=cab("t-cliente")).json()
    assert [p["id"] for p in lista] == ["ped-1"]
    assert amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-prof")).status_code == 200
    assert amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-n1")).status_code == 200


def test_estranho_nao_ve_o_pedido(amb):
    amb.semear_pedido(Estado.AGENDADO)

    for token in ("t-outro-cliente", "t-outro-prof"):
        assert amb.cliente.get("/v1/pedidos/ped-1", headers=cab(token)).status_code == 404
    assert amb.cliente.get("/v1/pedidos/nao-existe", headers=cab("t-cliente")).status_code == 404


def test_codigos_so_aparecem_para_o_cliente(amb):
    amb.semear_pedido(Estado.AGENDADO, codigo_inicio="1234")

    cliente = amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-cliente")).json()
    prof = amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-prof")).json()

    assert cliente["codigo_inicio"] == "1234"
    assert prof["codigo_inicio"] is None


# --- transições -------------------------------------------------------------------------


def test_aceitar_orcamento_cria_contrato(amb):
    amb.contexto.pedidos.salvar(Pedido("ped-1", CLIENTE.id, AGORA))

    r = acao(amb, "t-cliente", "aceitar_orcamento", {"orcamento_id": "orc-1"})

    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "orcamento_aceito"
    assert r.json()["profissional_id"] == PROFISSIONAL.id
    contrato = amb.contexto.contratos.obter_do_pedido("ped-1")
    assert contrato.valor_centavos == 100_000 and contrato.categoria_id == "pintura"
    assert len(amb.contexto.pedidos.eventos("ped-1")) == 1


def test_aceitar_orcamento_de_outro_pedido_da_422(amb):
    amb.contexto.pedidos.salvar(Pedido("ped-1", CLIENTE.id, AGORA))

    r = acao(amb, "t-cliente", "aceitar_orcamento", {"orcamento_id": "orc-outro"})

    assert r.status_code == 422
    assert "orçamento" in r.json()["detail"].lower()


def test_prova_mal_formada_da_422(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)

    r = acao(amb, "t-prof", "confirmar_agenda", {"janela": {"inicio": "ontem"}})

    assert r.status_code == 422


def test_profissional_confirma_agenda_e_cliente_ve_o_codigo(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)

    r = acao(amb, "t-prof", "confirmar_agenda", {"janela": janela_futura()})

    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "agendado"
    assert r.json()["codigo_inicio"] is None  # profissional não vê
    visto = amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-cliente")).json()
    assert len(visto["codigo_inicio"]) == 4


def test_cliente_nao_confirma_agenda(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)

    r = acao(amb, "t-cliente", "confirmar_agenda", {"janela": janela_futura()})

    assert r.status_code == 403
    assert "Cliente não pode" in r.json()["detail"]


def test_profissional_de_outro_pedido_da_404_ou_403(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)

    assert (
        acao(amb, "t-outro-prof", "confirmar_agenda", {"janela": janela_futura()}).status_code
        == 404
    )


def test_estado_invalido_da_409_em_portugues(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None)

    r = acao(amb, "t-cliente", "confirmar_conclusao")

    assert r.status_code == 409
    assert "Em" in r.json()["detail"] or "Aberto" in r.json()["detail"]


def test_check_in_com_codigo_errado_da_422(amb):
    amb.semear_pedido(
        Estado.AGENDADO,
        codigo_inicio="1234",
        janela=Janela(AGORA + timedelta(hours=1), AGORA + timedelta(hours=3)),
    )
    prova = {
        "foto": foto(),
        "localizacao": {"latitude": -19.9, "longitude": -43.9},
        "codigo_inicio": "0000",
    }

    r = acao(amb, "t-prof", "fazer_check_in", prova)

    assert r.status_code == 422
    assert "código" in r.json()["detail"]
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.AGENDADO


def test_fluxo_check_in_check_out_e_conclusao(amb):
    amb.semear_pedido(Estado.AGENDADO, codigo_inicio="1234")
    check_in = {
        "foto": foto(),
        "localizacao": {"latitude": -19.9, "longitude": -43.9},
        "codigo_inicio": "1234",
    }
    assert acao(amb, "t-prof", "fazer_check_in", check_in).json()["estado"] == "em_andamento"

    codigo = amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-cliente")).json()[
        "codigo_conclusao"
    ]
    saida = acao(
        amb, "t-prof", "fazer_check_out", {"foto_final": foto(), "codigo_conclusao": codigo}
    )
    assert saida.json()["estado"] == "em_confirmacao"

    fim = acao(amb, "t-cliente", "confirmar_conclusao")
    assert fim.status_code == 200
    assert fim.json()["estado"] == "concluido"
    garantia = amb.contexto.garantias.obter_garantia("ped-1")
    assert garantia.dias == 30 and garantia.inicio_em == AGORA

    eventos = amb.cliente.get("/v1/pedidos/ped-1/eventos", headers=cab("t-cliente")).json()
    assert [e["acao"] for e in eventos] == [
        "fazer_check_in",
        "fazer_check_out",
        "confirmar_conclusao",
    ]


def test_cancelar_exige_motivo(amb):
    amb.semear_pedido(Estado.AGENDADO)

    assert acao(amb, "t-cliente", "cancelar", {"motivo": "  "}).status_code == 422
    r = acao(amb, "t-cliente", "cancelar", {"motivo": "mudei de ideia"})
    assert r.status_code == 200 and r.json()["estado"] == "cancelado"


def test_acao_do_sistema_nao_passa_pela_api(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)

    for nome in ("confirmar_pagamento", "expirar_pedido", "concluir_por_prazo"):
        assert acao(amb, "t-cliente", nome).status_code == 403


def test_acoes_com_rota_propria_ou_em_aberto(amb):
    amb.semear_pedido(Estado.CONCLUIDO)

    assert acao(amb, "t-cliente", "abrir_disputa").status_code == 400
    assert acao(amb, "t-cliente", "pedir_retrabalho").status_code == 400
    assert acao(amb, "t-cliente", "remarcar").status_code == 501
    assert acao(amb, "t-mediador", "decidir_disputa").status_code == 403


def test_acao_desconhecida_da_422(amb):
    amb.semear_pedido(Estado.AGENDADO)

    assert acao(amb, "t-cliente", "voar").status_code == 422


def test_prova_nao_aceita_em_acao_sem_prova(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)

    assert acao(amb, "t-cliente", "confirmar_conclusao", {"x": 1}).status_code == 422
