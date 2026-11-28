"""B24: Tratinhos apos cartao recusado, cupom + Tratinhos, pedido urgente, LGPD /me,
recusar orcamento e responder avaliacao."""

from __future__ import annotations

from dataclasses import replace
from decimal import Decimal
from types import SimpleNamespace

import pytest
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_fluxo_pagamento_e2e import VALOR, Fluxo, fluxo  # noqa: F401
from test_profissional_upload import _aprovar, e2  # noqa: F401
from test_qa5_backend import _montar_app_com_seguranca

from trato.api.modelos import AbrirPedidoIn
from trato.api.moedas import (
    ConfigMoedas,
    LancamentoMoeda,
    MoedasEmMemoria,
    chave_reserva,
    dia_ref,
    mes_ref,
    situacao_reserva,
)
from trato.api.repositorios import ItemOrcamento
from trato.api.repositorios_app import Avaliacao
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.provedor import TipoEvento


@pytest.fixture(autouse=True)
def oferta_antiga_ligada(request):
    """Estes testes cobrem a prioridade paga pelo profissional, hoje desligada por padrão."""
    if "amb" in request.fixturenames:
        config = request.getfixturevalue("amb").contexto.config
        config._config = replace(config.carregar(), exclusividade_profissional_ofertada=True)


def _habilitar_moedas(fluxo_obj: Fluxo, saldo: int = 500) -> MoedasEmMemoria:
    moedas = MoedasEmMemoria(
        ConfigMoedas(
            ativo=True,
            valor_moeda_centavos=1,
            max_desconto_percentual=50,
            teto_diario_desconto_centavos=50_000,
            orcamento_mensal_desconto_centavos=200_000,
            teto_desconto_cliente_mes_centavos=50_000,
        )
    )
    moedas.lancar(
        LancamentoMoeda(
            usuario_id=CLIENTE.id,
            tipo="bonus_avaliacao",
            quantidade=saldo,
            chave_idempotencia=f"seed-b24:{CLIENTE.id}",
            criada_em=AGORA,
        )
    )
    fluxo_obj.ctx.moedas = moedas
    return moedas


def _habilitar_notificacoes(amb) -> RepositorioEmMemoria:
    repo = RepositorioEmMemoria()
    notif = ServicoNotificacoes(repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True))
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    amb.cliente.app.state.notificador = notif
    return repo


# --- Item 1: Tratinhos apos cartao recusado -----------------------------------------------------


def test_tratinhos_cartao_recusado_e_nova_tentativa_debita_uma_vez(fluxo: Fluxo):  # noqa: F811
    moedas = _habilitar_moedas(fluxo, saldo=100)
    pid = fluxo.aceitar()
    contrato = fluxo.ctx.contratos.obter_do_pedido(pid)
    assert contrato is not None

    # Tentativa 1: cliente usa 100 Tratinhos (R$ 1,00 de desconto sobre R$ 200,00)
    r1 = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        json={"meio": "cartao", "parcelas": 1, "usar_moedas": True},
    )
    assert r1.status_code == 201
    cob1 = r1.json()
    assert cob1["valor_centavos"] == VALOR - 100
    assert situacao_reserva(moedas, cobranca_id=cob1["cobranca_id"]) == "reservada"

    # Cartao recusado -> webhook payment_intent.payment_failed devolve reserva e cancela no provedor
    fluxo.webhook(TipoEvento.PAGAMENTO_FALHOU, cob1["cobranca_id"], evento_id="ev-falha-1")
    assert situacao_reserva(moedas, cobranca_id=cob1["cobranca_id"]) == "devolvida"
    assert ("cancelar_cobranca", cob1["cobranca_id"]) in fluxo.fake.chamadas
    assert moedas.saldo(CLIENTE.id, AGORA) == 100
    assert moedas.orcamento_usado_dia(dia_ref(AGORA)) == 0
    assert moedas.orcamento_usado(mes_ref(AGORA)) == 0

    # Mesmo se a cobranca antiga ainda estivesse AGUARDANDO, cobrar de novo nao a reaproveita
    c_antiga = fluxo.servico.cobrancas.obter(cob1["cobranca_id"])
    assert c_antiga is not None and c_antiga.status is EstadoCobranca.FALHOU

    # Tentativa 2: cria nova cobranca com nova reserva atomica e paga com sucesso
    r2 = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        json={"meio": "cartao", "parcelas": 1, "usar_moedas": True},
    )
    assert r2.status_code == 201
    cob2 = r2.json()
    assert cob2["cobranca_id"] != cob1["cobranca_id"]
    assert cob2["valor_centavos"] == VALOR - 100
    assert situacao_reserva(moedas, cobranca_id=cob2["cobranca_id"]) == "reservada"

    fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob2["cobranca_id"], evento_id="ev-ok-2")

    assert moedas.saldo(CLIENTE.id, AGORA) == 0
    assert moedas.orcamento_usado_dia(dia_ref(AGORA)) == 100
    assert moedas.orcamento_usado(mes_ref(AGORA)) == 100
    assert situacao_reserva(moedas, cobranca_id=cob2["cobranca_id"]) == "confirmada"


def test_tratinhos_mesmo_payment_intent_aprovado_apos_falha_re_reserva_e_debita(
    fluxo: Fluxo,  # noqa: F811
):
    moedas = _habilitar_moedas(fluxo, saldo=100)
    pid = fluxo.aceitar()
    contrato = fluxo.ctx.contratos.obter_do_pedido(pid)
    assert contrato is not None

    r1 = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        json={"meio": "cartao", "parcelas": 1, "usar_moedas": True},
    )
    cob_id = r1.json()["cobranca_id"]

    # Falha devolve a reserva
    fluxo.webhook(TipoEvento.PAGAMENTO_FALHOU, cob_id, evento_id="ev-falha-pi")
    assert situacao_reserva(moedas, cobranca_id=cob_id) == "devolvida"

    # Se o mesmo PaymentIntent ainda aprovar (ex.: 3DS tardio), re-reserva e debita 1x
    fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob_id, evento_id="ev-ok-pi")
    assert moedas.saldo(CLIENTE.id, AGORA) == 0
    assert moedas.orcamento_usado_dia(dia_ref(AGORA)) == 100
    assert moedas.orcamento_usado(mes_ref(AGORA)) == 100
    assert situacao_reserva(moedas, cobranca_id=f"reabertura:{cob_id}") == "confirmada"


def test_cobrar_nao_reaproveita_cobranca_aguardando_com_reserva_devolvida(fluxo: Fluxo):  # noqa: F811
    moedas = _habilitar_moedas(fluxo, saldo=100)
    pid = fluxo.aceitar()
    contrato = fluxo.ctx.contratos.obter_do_pedido(pid)
    assert contrato is not None

    r1 = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        json={"meio": "pix", "parcelas": 1, "usar_moedas": True},
    )
    cob1 = r1.json()["cobranca_id"]
    moedas.devolver_reserva(chave_reserva(cob1))
    assert situacao_reserva(moedas, cobranca_id=cob1) == "devolvida"

    r2 = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        json={"meio": "pix", "parcelas": 1, "usar_moedas": True},
    )
    cob2 = r2.json()["cobranca_id"]
    assert cob2 != cob1
    assert situacao_reserva(moedas, cobranca_id=cob2) == "reservada"


# --- Item 2: Cupom + Tratinhos -----------------------------------------------------------------


def test_cupom_teste5_sozinho_e_com_tratinhos_incrementa_usos(fluxo: Fluxo):  # noqa: F811
    _habilitar_moedas(fluxo, saldo=300)
    fluxo.ctx.extras["cupons"] = {
        "TESTE5": {
            "codigo": "TESTE5",
            "tipo": "fixo",
            "valor": 500,
            "valor_minimo_centavos": 1000,
            "limite_usos": 10,
            "usos_atuais": 0,
            "ativo": True,
        }
    }
    pid = fluxo.aceitar()
    contrato = fluxo.ctx.contratos.obter_do_pedido(pid)
    assert contrato is not None

    # Resumo com cupom sozinho
    res_cupom = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?cupom=TESTE5&usar_moedas=false", "t-cliente"
    ).json()
    assert res_cupom["cupom_codigo"] == "TESTE5"
    assert res_cupom["desconto_cupom_centavos"] == 500
    assert res_cupom["total_a_pagar_centavos"] == VALOR - 500

    # Resumo com cupom + Tratinhos (300 moedas = 300 centavos)
    res_misto = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?cupom=TESTE5&usar_moedas=true", "t-cliente"
    ).json()
    assert res_misto["cupom_codigo"] == "TESTE5"
    assert res_misto["desconto_cupom_centavos"] == 500
    assert res_misto["moedas_desconto_centavos"] == 300
    assert res_misto["desconto_centavos"] == 800
    assert res_misto["total_a_pagar_centavos"] == VALOR - 800

    # Cria cobranca com cupom sozinho primeiro (outro pedido)
    pid_so = fluxo.aceitar()
    cob_so = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid_so}/cobranca",
        "t-cliente",
        json={"meio": "cartao", "parcelas": 1, "cupom": "TESTE5", "usar_moedas": False},
    )
    assert cob_so.status_code == 201
    assert cob_so.json()["valor_centavos"] == VALOR - 500

    # Cria cobranca com cupom + Tratinhos
    cob = fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        json={"meio": "cartao", "parcelas": 1, "cupom": "TESTE5", "usar_moedas": True},
    )
    assert cob.status_code == 201
    cob_json = cob.json()
    assert cob_json["valor_centavos"] == VALOR - 800
    cob_local = fluxo.servico.cobrancas.obter(cob_json["cobranca_id"])
    assert cob_local is not None
    assert cob_local.cupom_codigo == "TESTE5"
    assert cob_local.desconto_centavos == 800
    assert cob_local.moedas_usadas == 300

    # Webhook confirma pagamento -> usos_atuais sobe para 1 (idempotente se repetir)
    fluxo.webhook(
        TipoEvento.PAGAMENTO_CONFIRMADO,
        cob_json["cobranca_id"],
        evento_id="ev-cupom-1",
    )
    fluxo.webhook(
        TipoEvento.PAGAMENTO_CONFIRMADO,
        cob_json["cobranca_id"],
        evento_id="ev-cupom-2",
    )
    assert fluxo.ctx.extras["cupons"]["TESTE5"]["usos_atuais"] == 1


# --- Item 3: Pedido urgente --------------------------------------------------------------------


def test_pedido_urgente_persiste_retorna_notifica_e_bloqueia_exclusividade(amb):
    notif = _habilitar_notificacoes(amb)
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True))
    amb.contexto.moedas.lancar(
        LancamentoMoeda(
            usuario_id=PROFISSIONAL.id,
            tipo="bonus_avaliacao",
            quantidade=100,
            chave_idempotencia="seed-exc",
            criada_em=AGORA,
        )
    )

    # Profissional apto na categoria para receber aviso de pedido urgente
    amb.cliente.app.state.modulo_profissional = SimpleNamespace(
        repo=SimpleNamespace(
            listar_disponiveis_agora=lambda: [
                SimpleNamespace(usuario_id=PROFISSIONAL.id, categorias=["eletrica"])
            ]
        )
    )

    corpo = AbrirPedidoIn(
        categoria_id="eletrica",
        cidade_id="sp",
        titulo="Curto circuito na cozinha",
        descricao="Disjuntor caindo toda hora",
        urgente=True,
        modalidade="presencial",
        endereco={"logradouro": "Rua A", "numero": "10", "bairro": "Centro", "cep": "01001000"},
    ).model_dump(mode="json")
    resp = amb.cliente.post("/v1/pedidos", headers=cab("t-cliente"), json=corpo)
    assert resp.status_code == 201, resp.text
    criado = resp.json()
    assert criado["urgente"] is True
    pid = criado["id"]

    # Dados persistidos e PedidoAbertoOut tambem trazem urgente=True
    dados = amb.contexto.pedidos.dados_do_pedido(pid)
    assert dados is not None and dados.urgente is True
    abertos = amb.cliente.get("/v1/profissional/pedidos-abertos", headers=cab("t-prof")).json()
    assert any(p["id"] == pid and p["urgente"] is True for p in abertos)

    # Dispara notificacao pedido.urgente
    avisos = notif.listar(PROFISSIONAL.id, False, 50)
    assert any(n.titulo == "Pedido urgente disponível" for n in avisos)

    # Bloqueia exclusividade de 48h
    exc = amb.cliente.post(
        "/v1/profissional/exclusividades",
        headers=cab("t-prof"),
        json={"pedido_id": pid, "chave_idempotencia": "exc-urgente-1"},
    )
    assert exc.status_code in (409, 422)
    assert exc.json()["codigo"] == "pedido_urgente"


def test_b25_urgente_aparece_na_lista_e_no_detalhe_do_cliente(amb):
    """Tudo que o app cliente lê (lista, detalhe, /dados) devolve `urgente` gravado no POST."""
    base = AbrirPedidoIn(
        categoria_id="eletrica",
        cidade_id="sp",
        titulo="Tomada soltando faísca",
        descricao="Preciso hoje",
        modalidade="presencial",
        endereco={"logradouro": "Rua A", "numero": "10", "bairro": "Centro", "cep": "01001000"},
    ).model_dump(mode="json")
    urgente = amb.cliente.post(
        "/v1/pedidos", headers=cab("t-cliente"), json={**base, "urgente": True}
    ).json()
    normal = amb.cliente.post(
        "/v1/pedidos", headers=cab("t-cliente"), json={**base, "urgente": False}
    ).json()
    assert urgente["urgente"] is True and normal["urgente"] is False

    lista = amb.cliente.get("/v1/pedidos?como=cliente", headers=cab("t-cliente")).json()
    por_id = {p["id"]: p for p in lista}
    assert por_id[urgente["id"]]["urgente"] is True
    assert por_id[normal["id"]]["urgente"] is False
    for pedido in (urgente, normal):
        det = amb.cliente.get(f"/v1/pedidos/{pedido['id']}", headers=cab("t-cliente")).json()
        assert det["urgente"] is pedido["urgente"]
        dados = amb.cliente.get(f"/v1/pedidos/{pedido['id']}/dados", headers=cab("t-cliente"))
        assert dados.json()["urgente"] is pedido["urgente"]


# --- Item 4: LGPD exclusao agendada em /v1/me --------------------------------------------------


def test_lgpd_exclusao_agendada_em_no_me_e_cancelamento():
    http, _, _, _, _, _ = _montar_app_com_seguranca(limites=[])

    assert http.get("/v1/me", headers=cab("t-cliente")).json()["exclusao_agendada_em"] is None

    pedir = http.post("/v1/me/exclusao", headers=cab("t-cliente"), json={})
    assert pedir.status_code == 200
    token = pedir.json()["token_confirmacao"]

    confirmar = http.post(
        "/v1/me/exclusao", headers=cab("t-cliente"), json={"token_confirmacao": token}
    )
    assert confirmar.status_code == 200

    me_agendado = http.get("/v1/me", headers=cab("t-cliente")).json()
    assert me_agendado["exclusao_agendada_em"] is not None

    cancelar = http.delete("/v1/me/exclusao", headers=cab("t-cliente"))
    assert cancelar.status_code == 204
    assert http.get("/v1/me", headers=cab("t-cliente")).json()["exclusao_agendada_em"] is None


# --- Item 5: Recusar orcamento e Responder avaliacao -------------------------------------------


def test_recusar_orcamento_idempotente_e_notifica_profissional(amb):
    notif = _habilitar_notificacoes(amb)
    r_ped = amb.cliente.post(
        "/v1/pedidos",
        headers=cab("t-cliente"),
        json=AbrirPedidoIn(
            categoria_id="eletrica",
            cidade_id="sp",
            titulo="Troca de tomada",
            descricao="Duas tomadas na sala",
            modalidade="presencial",
            endereco={"logradouro": "Rua A", "numero": "10", "bairro": "Centro", "cep": "01001000"},
        ).model_dump(mode="json"),
    )
    assert r_ped.status_code == 201, r_ped.text
    pid = r_ped.json()["id"]
    oid = amb.contexto.orcamentos.enviar(
        pedido_id=pid,
        profissional_id=PROFISSIONAL.id,
        itens=[ItemOrcamento("mao_de_obra", "Instalacao", Decimal("1"), 15_000)],
        agora=AGORA,
    )

    # Outro usuario nao pode recusar (carregar_pedido oculta como 404)
    assert amb.cliente.post(
        f"/v1/pedidos/{pid}/orcamentos/{oid}/recusar", headers=cab("t-prof")
    ).status_code in (403, 404)

    # Cliente dono recusa (1a vez)
    r1 = amb.cliente.post(f"/v1/pedidos/{pid}/orcamentos/{oid}/recusar", headers=cab("t-cliente"))
    assert r1.status_code == 200
    assert r1.json() == {"orcamento_id": oid, "pedido_id": pid, "status": "recusado"}

    # Idempotente na 2a chamada
    r2 = amb.cliente.post(f"/v1/pedidos/{pid}/orcamentos/{oid}/recusar", headers=cab("t-cliente"))
    assert r2.status_code == 200
    assert r2.json()["status"] == "recusado"

    # Notificou o profissional 1 vez e nao aparece mais na lista de ativos do pedido
    avisos = [
        n for n in notif.listar(PROFISSIONAL.id, False, 50) if n.titulo == "Orçamento recusado"
    ]
    assert len(avisos) == 1
    assert amb.contexto.orcamentos.do_pedido(pid) == ()


def test_responder_avaliacao_uma_vez(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)

    av = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/avaliacao",
        "t-cliente",
        json={"nota_geral": 5, "comentario": "Excelente servico", "etiquetas": ["pontual"]},
    )
    assert av.status_code == 201
    av_id = av.json()["id"]
    assert av_id is not None

    # Outro usuario (cliente) nao pode responder avaliacao do profissional
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/avaliacoes/{av_id}/responder",
            "t-cliente",
            json={"resposta": "Obrigado!"},
        ).status_code
        == 403
    )

    # Profissional responde
    resp = fluxo.chamar(
        "POST",
        f"/v1/avaliacoes/{av_id}/responder",
        "t-prof",
        json={"resposta": "Muito obrigado pela confianca!"},
    )
    assert resp.status_code == 200
    assert resp.json()["resposta"] == "Muito obrigado pela confianca!"

    # Segunda resposta e bloqueada (409)
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/avaliacoes/{av_id}/responder",
            "t-prof",
            json={"resposta": "Outra resposta"},
        ).status_code
        == 409
    )


def test_avaliacao_resposta_aparece_nas_listagens(e2):  # noqa: F811
    _aprovar(e2)
    e2.amb.contexto.avaliacoes.salvar(
        Avaliacao(
            "ped-resp",
            "cliente_para_profissional",
            "cli-secreto",
            "pro-1",
            5,
            "Otimo",
            ("pontual",),
            AGORA,
            id="av-resp-1",
            resposta="Muito obrigado pela confianca!",
        )
    )
    pub = e2.amb.cliente.get("/v1/publico/profissionais/pro-1")
    assert pub.status_code == 200
    assert pub.json()["avaliacoes_recentes"][0]["resposta"] == "Muito obrigado pela confianca!"

    perfil_logado = e2.get("/v1/profissionais/pro-1", "t-cliente")
    assert perfil_logado.status_code == 200
    assert perfil_logado.json()["avaliacoes"][0]["resposta"] == "Muito obrigado pela confianca!"
    assert perfil_logado.json()["avaliacoes"][0]["id"] == "av-resp-1"


def test_avaliacoes_postgres_de_linha_sem_type_error():
    from trato.persistencia.dinheiro import AvaliacoesPostgres

    repo = AvaliacoesPostgres(None)  # type: ignore[arg-type]
    av = repo._de_linha(
        {
            "id": "av-pg-1",
            "pedido_id": "ped-pg-1",
            "direcao": "cliente_para_profissional",
            "avaliador_id": "cli-1",
            "avaliado_id": "pro-1",
            "nota_geral": 5,
            "comentario": "Otimo",
            "etiquetas": ["pontual"],
            "criada_em": AGORA,
            "resposta": "Obrigado!",
        }
    )
    assert av.id == "av-pg-1"
    assert av.resposta == "Obrigado!"


def test_cliente_avaliado_pode_responder_avaliacao_uma_vez(fluxo):  # noqa: F811
    """BE-RESPOSTA-12.7 (Termos 12.7): cliente avaliado pelo profissional também pode responder."""
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)
    av = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/avaliacao",
        "t-prof",
        json={"nota_geral": 5, "comentario": "Cliente pontual e educado."},
    )
    assert av.status_code == 201, av.text
    av_id = av.json()["id"]
    assert av_id is not None

    # Quem avaliou (profissional) e outro cliente não podem responder (403)
    for token in ("t-prof", "t-outro-cliente"):
        assert (
            fluxo.chamar(
                "POST",
                f"/v1/avaliacoes/{av_id}/responder",
                token,
                json={"resposta": "Obrigado!"},
            ).status_code
            == 403
        )

    # Resposta vazia/só espaços é recusada (422)
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/avaliacoes/{av_id}/responder",
            "t-cliente",
            json={"resposta": "   "},
        ).status_code
        == 422
    )

    # Cliente avaliado responde com sucesso e resposta fica visível na consulta
    resp = fluxo.chamar(
        "POST",
        f"/v1/avaliacoes/{av_id}/responder",
        "t-cliente",
        json={"resposta": "Obrigado pelo ótimo atendimento!"},
    )
    assert resp.status_code == 200, resp.text
    corpo = resp.json()
    assert corpo["direcao"] == "profissional_para_cliente"
    assert corpo["resposta"] == "Obrigado pelo ótimo atendimento!"
    recebidas = fluxo.ctx.avaliacoes.recebidas(fluxo.ctx.pedidos.obter(pid).cliente_id)
    assert any(a.id == av_id and a.resposta == "Obrigado pelo ótimo atendimento!" for a in recebidas)

    # Segunda resposta é recusada (409)
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/avaliacoes/{av_id}/responder",
            "t-cliente",
            json={"resposta": "Segunda tentativa"},
        ).status_code
        == 409
    )


def test_avaliacao_nao_publicada_nao_aceita_resposta(fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)
    av = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/avaliacao",
        "t-prof",
        json={"nota_geral": 4, "comentario": "Bom atendimento."},
    )
    assert av.status_code == 201, av.text
    av_id = av.json()["id"]
    fluxo.ctx.avaliacoes.definir_status(av_id, "em_revisao")
    r = fluxo.chamar(
        "POST",
        f"/v1/avaliacoes/{av_id}/responder",
        "t-cliente",
        json={"resposta": "Tentativa em revisão"},
    )
    assert r.status_code == 409, r.text


def test_cliente_lista_avaliacoes_recebidas_publicadas_com_resposta(fluxo):  # noqa: F811
    """BE-AVALIACOES-RECEBIDAS-12.7: GET /v1/me/avaliacoes/recebidas lista só publicadas do usuário."""
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)

    av = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/avaliacao",
        "t-prof",
        json={"nota_geral": 5, "comentario": "Excelente cliente."},
    )
    assert av.status_code == 201, av.text
    av_id = av.json()["id"]

    # Avaliação em moderação e avaliação descartada para o mesmo cliente não aparecem
    fluxo.ctx.usuarios.atualizar_nome(PROFISSIONAL.id, "Carlos Eduardo Silva")
    cli_id = fluxo.ctx.pedidos.obter(pid).cliente_id
    fluxo.ctx.avaliacoes.salvar(
        Avaliacao(
            "ped-mod",
            "profissional_para_cliente",
            PROFISSIONAL.id,
            cli_id,
            2,
            "Em revisão",
            (),
            AGORA,
            id="av-mod",
            status="em_revisao",
        )
    )
    fluxo.ctx.avaliacoes.salvar(
        Avaliacao(
            "ped-desc",
            "profissional_para_cliente",
            PROFISSIONAL.id,
            cli_id,
            1,
            "Descartada",
            (),
            AGORA,
            id="av-desc",
            status="descartada",
        )
    )
    # Avaliação destinada a outro usuário não aparece
    fluxo.ctx.avaliacoes.salvar(
        Avaliacao(
            "ped-outro",
            "profissional_para_cliente",
            PROFISSIONAL.id,
            "cli-outro",
            5,
            "De outro cliente",
            (),
            AGORA,
            id="av-outro",
            status="publicada",
        )
    )

    antes = fluxo.chamar("GET", "/v1/me/avaliacoes/recebidas", "t-cliente")
    assert antes.status_code == 200, antes.text
    itens = antes.json()
    assert [i["id"] for i in itens] == [av_id]
    assert itens[0]["nota_geral"] == 5
    assert itens[0]["comentario"] == "Excelente cliente."
    assert itens[0]["resposta"] is None
    assert itens[0]["criada_em"] is not None
    assert itens[0]["cliente_nome"] == "Carlos S."

    # Após responder, a resposta aparece na listagem
    resp = fluxo.chamar(
        "POST",
        f"/v1/avaliacoes/{av_id}/responder",
        "t-cliente",
        json={"resposta": "Muito obrigado!"},
    )
    assert resp.status_code == 200, resp.text
    depois = fluxo.chamar("GET", "/v1/me/avaliacoes/recebidas", "t-cliente")
    assert depois.status_code == 200, depois.text
    assert depois.json()[0]["resposta"] == "Muito obrigado!"

    # Outro cliente não vê avaliações deste cliente
    outro = fluxo.chamar("GET", "/v1/me/avaliacoes/recebidas", "t-outro-cliente")
    assert outro.status_code == 200, outro.text
    assert [i["id"] for i in outro.json()] == []
