# ruff: noqa: F811
"""Testes dos novos fluxos de cliente: fotos do pedido aberto, cupom/parcelas, pedido direcionado
e negociação/remarcação de agenda pelo chat."""

from __future__ import annotations

from datetime import datetime, timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401
from test_profissional_upload import JPEG_COM_EXIF, e2  # noqa: F401

from trato.api.repositorios import DadosPedido, Orcamento
from trato.pagamentos.modelos import ConfigPagamento
from trato.pagamentos.parcelamento import ConfigParcelamento
from trato.pagamentos.taxa import ConfigTaxa
from trato.pedidos.estados import Estado, Pedido


def test_fotos_do_pedido_aberto_para_cliente_e_profissional(e2, amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    amb.contexto.pedidos.atualizar_dados(
        "ped-1",
        CLIENTE.id,
        DadosPedido("cat-pintura", "cid-bh", "Pintar quarto", "Paredes brancas", bairro="Centro"),
    )
    _, conc = e2.enviar("t-cliente", "pedido", JPEG_COM_EXIF, pedido_id="ped-1")
    assert conc.status_code == 200

    # Rota padrão continua sem devolver fotos de abertura
    assert e2.get("/v1/pedidos/ped-1/fotos", "t-cliente").json() == []

    # Com finalidade=pedido, tanto cliente quanto profissional elegível veem URLs assinadas
    r_cli = e2.get("/v1/pedidos/ped-1/fotos?finalidade=pedido", "t-cliente")
    r_pro = e2.get("/v1/pedidos/ped-1/fotos?finalidade=pedido", "t-prof")
    assert r_cli.status_code == 200 and len(r_cli.json()) == 1
    assert r_pro.status_code == 200 and len(r_pro.json()) == 1
    assert r_pro.json()[0]["url"].startswith("https://")

    # Outro cliente não vê
    assert e2.get("/v1/pedidos/ped-1/fotos?finalidade=pedido", "t-outro-cliente").status_code == 404

    # /dados e /profissional/pedidos-abertos/{id} já trazem fotos_urls
    dados = e2.get("/v1/pedidos/ped-1/dados", "t-cliente")
    assert dados.status_code == 200 and len(dados.json()["fotos_urls"]) == 1
    det = e2.get("/v1/profissional/pedidos-abertos/ped-1", "t-prof")
    assert det.status_code == 200 and len(det.json()["fotos_urls"]) == 1


def test_cupom_no_checkout_e_parcelamento(fluxo: Fluxo):
    fluxo.servico.config = lambda: ConfigPagamento(
        ConfigTaxa(750, 500),
        50_000,
        parcelamento=ConfigParcelamento({2: 300, 3: 450}),
    )
    fluxo.ctx.extras["cupons"] = {
        "TRATO10": {
            "codigo": "TRATO10",
            "tipo": "percentual",
            "valor": 10,
            "valor_minimo_centavos": 50_000,
            "limite_usos": 5,
            "usos_atuais": 0,
            "ativo": True,
        },
        "EXPIRADO": {
            "codigo": "EXPIRADO",
            "tipo": "fixo",
            "valor": 1_000,
            "valido_ate": (AGORA - timedelta(days=1)).isoformat(),
            "ativo": True,
        },
    }
    pid = fluxo.aceitar()

    # Simulação do cupom em GET pagamento e POST cupom
    r_prev = fluxo.chamar("GET", f"/v1/pedidos/{pid}/pagamento?cupom=trato10", "t-cliente")
    assert r_prev.status_code == 200, r_prev.text
    prev = r_prev.json()
    assert prev["valor_centavos"] == 100_000
    assert prev["desconto_centavos"] == 10_000
    assert prev["total_a_pagar_centavos"] == 90_000
    assert prev["cupom_codigo"] == "TRATO10"
    assert [o["parcelas"] for o in prev["opcoes_parcelamento"]] == [2, 3]

    r_cup = fluxo.chamar("POST", f"/v1/contratos/{pid}/cupom", "t-cliente", {"codigo": "trato10"})
    assert r_cup.status_code == 200
    assert r_cup.json()["desconto_centavos"] == 10_000

    # Cupom expirado dá 422
    assert (
        fluxo.chamar(
            "POST", f"/v1/contratos/{pid}/cupom", "t-cliente", {"codigo": "EXPIRADO"}
        ).status_code
        == 422
    )

    # Criar cobrança parcelada em 2x com cupom TRATO10 (90_000 + 3% = 92_700)
    r_cob = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        {"meio": "cartao", "parcelas": 2, "cupom": "TRATO10"},
    )
    assert r_cob.status_code == 201, r_cob.text
    cob = r_cob.json()
    assert cob["parcelas"] == 2
    assert cob["valor_centavos"] == 92_700
    assert fluxo.ctx.extras["cupons"]["TRATO10"]["usos_atuais"] == 1

    # Repetir chamada idempotente não incrementa duas vezes o uso do cupom
    r_rep = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        {"meio": "cartao", "parcelas": 2, "cupom": "TRATO10"},
    )
    assert r_rep.status_code == 201 and r_rep.json()["cobranca_id"] == cob["cobranca_id"]
    assert fluxo.ctx.extras["cupons"]["TRATO10"]["usos_atuais"] == 1


def test_pedido_direcionado_notifica_e_prioriza_profissional(amb):
    amb.contexto.pedidos.salvar(
        Pedido("ped-comum", CLIENTE.id, AGORA),
        None,
        DadosPedido("pintura", "bh", "Pintura sala", "Parede", bairro="Centro"),
    )
    corpo = {
        "categoria_id": "pintura",
        "cidade_id": "bh",
        "titulo": "Pintura direcionada",
        "descricao": "Preciso do seu orçamento",
        "modalidade": "presencial",
        "endereco": {
            "logradouro": "Rua A",
            "numero": "10",
            "bairro": "Centro",
            "cep": "30100-000",
        },
        "profissional_convidado_id": PROFISSIONAL.id,
    }
    r = amb.cliente.post("/v1/pedidos", json=corpo, headers=cab("t-cliente"))
    assert r.status_code == 201, r.text
    novo_id = r.json()["id"]

    # Dados do pedido trazem o profissional_convidado_id
    dados = amb.cliente.get(f"/v1/pedidos/{novo_id}/dados", headers=cab("t-cliente")).json()
    assert dados["profissional_convidado_id"] == PROFISSIONAL.id

    # Profissional convidado recebe notificação e vê o pedido com convidado=True no topo
    notas = amb.cliente.get("/v1/notificacoes", headers=cab("t-prof")).json()
    assert any(n["tipo"] == "pedido.direcionado" for n in notas)

    abertos = amb.cliente.get("/v1/profissional/pedidos-abertos", headers=cab("t-prof")).json()
    assert abertos[0]["id"] == novo_id and abertos[0]["convidado"] is True
    outros = amb.cliente.get("/v1/profissional/pedidos-abertos", headers=cab("t-outro-prof")).json()
    achado_outro = next(p for p in outros if p["id"] == novo_id)
    assert achado_outro["convidado"] is False

    # Não pode direcionar pedido para si mesmo
    auto = amb.cliente.post("/v1/pedidos", json=corpo, headers=cab("t-prof"))
    assert auto.status_code == 422


def _janela(horas: int) -> dict[str, str]:
    inicio = AGORA + timedelta(hours=horas)
    return {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}


def test_negociacao_e_remarcacao_de_agenda_no_chat(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    amb.contexto.orcamentos.adicionar(
        Orcamento("orc-1", "ped-1", PROFISSIONAL.id, 50_000, "pintura")
    )

    # Cliente sugere horário enquanto PAGO_E_RETIDO
    j1 = _janela(24)
    r_prop = amb.cliente.post(
        "/v1/pedidos/ped-1/agenda/propor",
        json={"janela": j1, "justificativa": "Prefiro pela tarde"},
        headers=cab("t-cliente"),
    )
    assert r_prop.status_code == 201, r_prop.text
    msg = r_prop.json()
    assert msg["texto"].startswith("[agenda:") and not msg["mascarada"]

    # Quem propôs não pode aceitar a própria proposta
    proprio = amb.cliente.post(
        "/v1/pedidos/ped-1/agenda/aceitar",
        json={"mensagem_id": msg["id"]},
        headers=cab("t-cliente"),
    )
    assert proprio.status_code == 422

    # Profissional aceita -> pedido vai para agendado
    r_ok = amb.cliente.post(
        "/v1/pedidos/ped-1/agenda/aceitar",
        json={"mensagem_id": msg["id"]},
        headers=cab("t-prof"),
    )
    assert r_ok.status_code == 200, r_ok.text
    assert r_ok.json()["estado"] == "agendado"
    assert datetime.fromisoformat(r_ok.json()["janela"]["inicio"]) == datetime.fromisoformat(
        j1["inicio"]
    )

    # Profissional sugere novo horário no chat -> cliente aceita (remarcação)
    j2 = _janela(48)
    r_prop2 = amb.cliente.post(
        "/v1/pedidos/ped-1/agenda/propor",
        json={"janela": j2, "justificativa": "Reagendando visita"},
        headers=cab("t-prof"),
    )
    assert r_prop2.status_code == 201
    r_ok2 = amb.cliente.post(
        "/v1/pedidos/ped-1/agenda/aceitar",
        json={"mensagem_id": r_prop2.json()["id"]},
        headers=cab("t-cliente"),
    )
    assert r_ok2.status_code == 200, r_ok2.text
    assert r_ok2.json()["estado"] == "agendado"
    assert datetime.fromisoformat(r_ok2.json()["janela"]["inicio"]) == datetime.fromisoformat(
        j2["inicio"]
    )
