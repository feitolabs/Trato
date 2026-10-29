"""F4.10: pedido de ponta a ponta pela API, com o provedor falso e repositórios em memória."""

from __future__ import annotations

from dataclasses import dataclass

import pytest
from conftest import AGORA, PROFISSIONAL, Ambiente, cab, janela_futura
from fastapi.testclient import TestClient

from trato.api.repositorios import Orcamento
from trato.api.rotas_pagamento import instalar_pagamento
from trato.financeiro.ledger import CUSTODIA, TAXA_TRATO, TipoLancamento, liberado
from trato.pagamentos.memoria import AditivosEmMemoria, CobrancasEmMemoria, TermosEmMemoria
from trato.pagamentos.modelos import ConfigPagamento
from trato.pagamentos.orquestrador import ServicoPagamento
from trato.pagamentos.provedor import ProvedorFake, TipoEvento
from trato.pagamentos.taxa import ConfigTaxa

VALOR = 100_000
TAXA_BPS = 750  # só nos testes; no sistema vem da configuração
TAXA_MINIMA = 500
TAXA_ESPERADA = 7_500


@dataclass
class Fluxo:
    amb: Ambiente
    fake: ProvedorFake
    servico: ServicoPagamento
    http: TestClient

    @property
    def ctx(self):
        return self.amb.contexto

    def chamar(self, metodo, url, token, json=None):
        return self.http.request(metodo, url, json=json, headers=cab(token))

    def webhook(self, tipo, cobranca_id, **kw):
        kw.setdefault("instante", int(self.amb.relogio.agora.timestamp()))
        corpo, cabecalhos = self.fake.evento_assinado(tipo, cobranca_id, **kw)
        return self.http.post("/v1/webhooks/stripe", content=corpo, headers=cabecalhos)

    def acao(self, pedido_id, acao, token, prova=None):
        corpo = {"prova": prova} if prova is not None else None
        return self.chamar("POST", f"/v1/pedidos/{pedido_id}/acoes/{acao}", token, corpo)

    def pedido(self, pedido_id, quem="t-cliente"):
        return self.chamar("GET", f"/v1/pedidos/{pedido_id}", quem).json()

    def saldo(self, pedido_id):
        return self.chamar("GET", f"/v1/pedidos/{pedido_id}/saldo", "t-cliente").json()

    # --- etapas reutilizáveis ----------------------------------------------------------------

    def aceitar(self) -> str:
        r = self.chamar("POST", "/v1/pedidos", "t-cliente")
        assert r.status_code == 201 and r.json()["estado"] == "aberto"
        pid = r.json()["id"]
        self.ctx.orcamentos.adicionar(Orcamento("orc-e2e", pid, PROFISSIONAL.id, VALOR, "pintura"))
        r = self.acao(pid, "aceitar_orcamento", "t-cliente", {"orcamento_id": "orc-e2e"})
        assert r.status_code == 200 and r.json()["estado"] == "orcamento_aceito"
        return pid

    def cobrar(self, pid, meio="pix") -> dict:
        r = self.chamar("POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", {"meio": meio})
        assert r.status_code == 201, r.text
        return r.json()

    def pagar(self, pid, meio="pix") -> dict:
        cobranca = self.cobrar(pid, meio)
        self.fake.marcar_paga(cobranca["id"])
        r = self.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"])
        assert r.status_code == 200, r.text
        return cobranca

    def agendar(self, pid) -> None:
        r = self.acao(pid, "confirmar_agenda", "t-prof", {"janela": janela_futura()})
        assert r.status_code == 200, r.text

    def foto(self):
        return {"arquivo_id": "f1", "tirada_em": AGORA.isoformat()}

    def iniciar(self, pid) -> None:
        codigo = self.pedido(pid)["codigo_inicio"]
        prova = {
            "foto": self.foto(),
            "localizacao": {"latitude": -23.5, "longitude": -46.6},
            "codigo_inicio": codigo,
        }
        r = self.acao(pid, "fazer_check_in", "t-prof", prova)
        assert r.status_code == 200, r.text

    def encerrar_execucao(self, pid) -> None:
        codigo = self.pedido(pid)["codigo_conclusao"]
        prova = {"foto_final": self.foto(), "codigo_conclusao": codigo}
        r = self.acao(pid, "fazer_check_out", "t-prof", prova)
        assert r.status_code == 200 and r.json()["estado"] == "em_confirmacao", r.text

    def ate_em_confirmacao(self) -> str:
        pid = self.aceitar()
        self.pagar(pid)
        self.agendar(pid)
        self.iniciar(pid)
        self.encerrar_execucao(pid)
        return pid

    def concluir(self, pid) -> None:
        r = self.acao(pid, "confirmar_conclusao", "t-cliente")
        assert r.status_code == 200 and r.json()["estado"] == "concluido", r.text

    def tipos(self, pid):
        return [i.tipo for i in self.ctx.ledger.lancamentos(pid)]


@pytest.fixture
def fluxo(amb: Ambiente) -> Fluxo:
    fake = ProvedorFake()
    servico = ServicoPagamento(
        fake,
        lambda: ConfigPagamento(ConfigTaxa(TAXA_BPS, TAXA_MINIMA), alcada_disputa_centavos=10**9),
        CobrancasEmMemoria(),
        AditivosEmMemoria(),
        TermosEmMemoria(),
    )
    instalar_pagamento(amb.cliente.app, amb.contexto, servico)
    return Fluxo(amb, fake, servico, amb.cliente)


# --- caminho feliz ---------------------------------------------------------------------------


def test_pedido_de_ponta_a_ponta(fluxo: Fluxo):
    pid = fluxo.aceitar()
    assert fluxo.ctx.contratos.obter_do_pedido(pid).valor_centavos == VALOR
    assert fluxo.servico.termos.obter(pid).taxa == ConfigTaxa(TAXA_BPS, TAXA_MINIMA)

    cobranca = fluxo.cobrar(pid)
    assert cobranca["status"] == "aguardando" and cobranca["valor_centavos"] == VALOR
    # Criar a cobrança não é pagar: o pedido segue esperando o provedor (D13).
    assert fluxo.pedido(pid)["estado"] == "orcamento_aceito"
    assert fluxo.saldo(pid)["cliente_pagou_centavos"] == 0

    fluxo.fake.marcar_paga(cobranca["id"])
    primeiro = fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"])
    reenvio = fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"])
    assert primeiro.json() == {"recebido": True, "duplicado": False, "tratado": True}
    assert reenvio.json()["duplicado"] is True
    assert fluxo.pedido(pid)["estado"] == "pago_e_retido"
    assert fluxo.tipos(pid) == [TipoLancamento.COBRANCA]  # reenvio não duplicou
    assert fluxo.saldo(pid)["retido_centavos"] == VALOR

    fluxo.agendar(pid)
    assert fluxo.pedido(pid)["estado"] == "agendado"
    fluxo.iniciar(pid)
    assert fluxo.pedido(pid)["estado"] == "em_andamento"
    fluxo.encerrar_execucao(pid)

    fluxo.concluir(pid)
    saldo = fluxo.saldo(pid)
    assert saldo["retido_centavos"] == 0
    assert saldo["taxa_trato_centavos"] == TAXA_ESPERADA
    assert saldo["a_liberar_centavos"] == VALOR - TAXA_ESPERADA
    assert fluxo.ctx.garantias.obter_garantia(pid) is not None

    # O provedor liquida; o ledger só espelha (caminho A).
    r = fluxo.webhook(TipoEvento.LIQUIDACAO, cobranca["id"])
    assert r.status_code == 200
    saldo = fluxo.saldo(pid)
    assert saldo["a_liberar_centavos"] == 0 and saldo["liberado_centavos"] == VALOR - TAXA_ESPERADA
    fluxo.ctx.ledger.livro.verificar_partidas()
    assert fluxo.pedido(pid)["estado"] == "concluido"
    assert [
        e["para"] for e in fluxo.chamar("GET", f"/v1/pedidos/{pid}/eventos", "t-cliente").json()
    ] == [
        "orcamento_aceito",
        "pago_e_retido",
        "agendado",
        "em_andamento",
        "em_confirmacao",
        "concluido",
    ]


def test_taxa_congelada_no_aceite_nao_muda_com_a_configuracao(fluxo: Fluxo):
    pid = fluxo.aceitar()
    fluxo.servico.config = lambda: ConfigPagamento(ConfigTaxa(2_000, 0), 10**9)
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)
    assert fluxo.saldo(pid)["taxa_trato_centavos"] == TAXA_ESPERADA


def test_so_o_cliente_cria_cobranca_e_so_com_orcamento_aceito(fluxo: Fluxo):
    r = fluxo.chamar("POST", "/v1/pedidos", "t-cliente")
    pid = r.json()["id"]
    assert (
        fluxo.chamar(
            "POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", {"meio": "pix"}
        ).status_code
        == 409
    )
    pid = fluxo.aceitar()
    assert (
        fluxo.chamar("POST", f"/v1/pedidos/{pid}/cobranca", "t-prof", {"meio": "pix"}).status_code
        == 403
    )
    assert (
        fluxo.chamar(
            "POST", f"/v1/pedidos/{pid}/cobranca", "t-outro-cliente", {"meio": "pix"}
        ).status_code
        == 404
    )


def test_cobranca_repetida_devolve_a_mesma(fluxo: Fluxo):
    pid = fluxo.aceitar()
    a, b = fluxo.cobrar(pid), fluxo.cobrar(pid)
    assert a["id"] == b["id"]
    assert len(fluxo.servico.cobrancas.do_pedido(pid)) == 1


# --- ramos de pagamento ----------------------------------------------------------------------


def test_pagamento_falho_deixa_tentar_de_novo(fluxo: Fluxo):
    pid = fluxo.aceitar()
    primeira = fluxo.cobrar(pid, "cartao")
    fluxo.fake.marcar_falha(primeira["id"])
    assert fluxo.webhook(TipoEvento.PAGAMENTO_FALHOU, primeira["id"]).status_code == 200
    assert fluxo.pedido(pid)["estado"] == "orcamento_aceito"
    assert fluxo.tipos(pid) == []
    assert fluxo.servico.cobrancas.obter(primeira["id"]).status.value == "falhou"

    segunda = fluxo.cobrar(pid, "pix")
    assert segunda["id"] != primeira["id"]
    fluxo.fake.marcar_paga(segunda["id"])
    fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, segunda["id"])
    assert fluxo.pedido(pid)["estado"] == "pago_e_retido"


def test_falha_que_chega_depois_do_pagamento_e_ignorada(fluxo: Fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    r = fluxo.webhook(TipoEvento.PAGAMENTO_FALHOU, cobranca["id"])
    assert r.status_code == 200
    assert fluxo.pedido(pid)["estado"] == "pago_e_retido"
    assert fluxo.servico.cobrancas.obter(cobranca["id"]).status.value == "paga"


def test_assinatura_invalida_nao_muda_nada(fluxo: Fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    instante = int(fluxo.amb.relogio.agora.timestamp())
    corpo, _ = fluxo.fake.evento_assinado(
        TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"], instante=instante
    )
    falso = {"Stripe-Signature": fluxo.fake.assinar(corpo, instante, "segredo-errado")}
    assert fluxo.http.post("/v1/webhooks/stripe", content=corpo, headers=falso).status_code == 400
    assert fluxo.http.post("/v1/webhooks/stripe", content=corpo).status_code == 400
    adulterado = corpo.replace(b'"amount":100000', b'"amount":1')
    _, certo = fluxo.fake.evento_assinado(
        TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"], instante=instante
    )
    assert (
        fluxo.http.post("/v1/webhooks/stripe", content=adulterado, headers=certo).status_code == 400
    )
    assert fluxo.pedido(pid)["estado"] == "orcamento_aceito"
    assert fluxo.tipos(pid) == []


def test_webhook_antigo_demais_e_recusado(fluxo: Fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    velho = int(fluxo.amb.relogio.agora.timestamp()) - 3_600
    r = fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"], instante=velho)
    assert r.status_code == 400


def test_webhook_de_pagamento_com_valor_diferente_nao_confirma(fluxo: Fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    quieto = TestClient(fluxo.http.app, raise_server_exceptions=False)
    corpo, cabs = fluxo.fake.evento_assinado(
        TipoEvento.PAGAMENTO_CONFIRMADO,
        cobranca["id"],
        valor_centavos=1,
        instante=int(fluxo.amb.relogio.agora.timestamp()),
    )
    assert quieto.post("/v1/webhooks/stripe", content=corpo, headers=cabs).status_code == 422
    assert fluxo.pedido(pid)["estado"] == "orcamento_aceito"


def test_liquidacao_fora_de_ordem_espera_e_aplica_no_reenvio(fluxo: Fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    quieto = TestClient(fluxo.http.app, raise_server_exceptions=False)
    instante = int(fluxo.amb.relogio.agora.timestamp())
    corpo, cabs = fluxo.fake.evento_assinado(
        TipoEvento.LIQUIDACAO, cobranca["id"], instante=instante
    )

    # chegou antes de concluir: não aplica e o provedor reenvia depois
    assert quieto.post("/v1/webhooks/stripe", content=corpo, headers=cabs).status_code == 500
    assert fluxo.saldo(pid)["liberado_centavos"] == 0

    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)
    assert quieto.post("/v1/webhooks/stripe", content=corpo, headers=cabs).status_code == 200
    assert fluxo.saldo(pid)["liberado_centavos"] == VALOR - TAXA_ESPERADA


def test_pagamento_que_chega_depois_do_prazo_volta_ao_cliente(fluxo: Fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    # o pedido expira o pagamento e volta a Aberto (rotina do sistema)
    pedido = fluxo.ctx.pedidos.obter(pid)
    from trato.pedidos.estados import Acao, Ator, Papel, transicionar

    fluxo.amb.relogio.avancar(hours=25)
    prazos = fluxo.ctx.config.carregar().prazos_pedido
    t = transicionar(
        pedido,
        Acao.EXPIRAR_PAGAMENTO,
        Ator(Papel.SISTEMA, "rotina"),
        fluxo.amb.relogio(),
        None,
        prazos,
    )
    fluxo.ctx.pedidos.salvar(t.pedido, t.evento)

    fluxo.fake.marcar_paga(cobranca["id"])
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"]).status_code == 200
    assert fluxo.pedido(pid)["estado"] == "aberto"
    assert fluxo.tipos(pid) == []  # nunca entrou no ledger
    assert fluxo.servico.cobrancas.obter(cobranca["id"]).status.value == "devolvida"
    assert ("estornar", f"orfao/{cobranca['id']}") in fluxo.fake.chamadas


def test_duas_cobrancas_pagas_a_segunda_e_devolvida(fluxo: Fluxo):
    pid = fluxo.aceitar()
    pix = fluxo.cobrar(pid, "pix")
    cartao = fluxo.cobrar(pid, "cartao")  # cancela a anterior localmente
    assert pix["id"] != cartao["id"]
    for c in (pix, cartao):
        fluxo.fake.marcar_paga(c["id"])
    fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, pix["id"])
    fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cartao["id"])
    assert fluxo.saldo(pid)["retido_centavos"] == VALOR
    assert fluxo.servico.cobrancas.obter(cartao["id"]).status.value == "devolvida"


# --- cancelamento ----------------------------------------------------------------------------


def test_cancelamento_antes_de_pagar_cancela_a_cobranca(fluxo: Fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    r = fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "desisti"})
    assert r.status_code == 200 and r.json()["estado"] == "cancelado"
    assert fluxo.servico.cobrancas.obter(cobranca["id"]).status.value == "cancelada"
    assert fluxo.tipos(pid) == []


def test_cancelamento_depois_de_pagar_devolve_tudo(fluxo: Fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    fluxo.agendar(pid)
    r = fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "mudei de ideia"})
    assert r.json()["estado"] == "cancelado"
    saldo = fluxo.saldo(pid)
    assert saldo["retido_centavos"] == 0 and saldo["cliente_pagou_centavos"] == 0
    assert [c for c in fluxo.fake.chamadas if c[0] == "estornar"] == [
        ("estornar", f"din/{pid}/1/{cobranca['id']}")
    ]
    assert fluxo.servico.cobrancas.obter(cobranca["id"]).estornado_centavos == VALOR
    fluxo.ctx.ledger.livro.verificar_partidas()


# --- disputa -----------------------------------------------------------------------------------

DISPUTA = {
    "motivo": "mal_feito",
    "descricao": "Parede com mancha.",
    "fotos": [{"arquivo_id": "f2", "tirada_em": AGORA.isoformat()}],
}


def _abrir_e_responder_disputa(fluxo: Fluxo, pid: str) -> None:
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa", "t-cliente", DISPUTA)
    assert r.status_code == 201, r.text
    assert r.json()["valor_congelado_centavos"] == VALOR
    assert fluxo.pedido(pid)["estado"] == "em_disputa"
    assert fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/resposta", "t-prof").status_code == 200


def test_disputa_congela_e_reembolso_parcial_divide_o_valor(fluxo: Fluxo):
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    assert fluxo.saldo(pid)["retido_centavos"] == VALOR  # congelado, nada foi repartido

    decisao = {
        "resultado": "reembolso_parcial",
        "justificativa": "Mancha confirmada nas fotos.",
        "percentual_cliente_bps": 2_500,
    }
    assert (
        fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-prof", decisao).status_code
        == 403
    )
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-equipe", decisao)
    assert r.status_code == 200, r.text
    assert r.json()["para_cliente_centavos"] == 25_000
    assert r.json()["para_profissional_centavos"] == 75_000
    assert fluxo.pedido(pid)["estado"] == "concluido"

    saldo = fluxo.saldo(pid)
    taxa = 5_625  # 7,5% de 75.000 (taxa congelada no contrato)
    assert saldo["taxa_trato_centavos"] == taxa
    assert saldo["a_liberar_centavos"] == 75_000 - taxa
    assert saldo["retido_centavos"] == 0
    assert [c[0] for c in fluxo.fake.chamadas].count("estornar") == 1
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_disputa_reembolso_total_cancela_e_devolve(fluxo: Fluxo):
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    decisao = {"resultado": "reembolso_total", "justificativa": "Serviço não feito."}
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-equipe", decisao)
    assert r.status_code == 200 and r.json()["estado_pedido"] == "cancelado"
    saldo = fluxo.saldo(pid)
    assert saldo["retido_centavos"] == 0 and saldo["taxa_trato_centavos"] == 0
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    assert fluxo.ctx.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0


def test_disputa_liberar_tudo_conclui_com_taxa_cheia(fluxo: Fluxo):
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    decisao = {"resultado": "liberar_tudo", "justificativa": "Serviço conforme combinado."}
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-equipe", decisao)
    assert r.json()["estado_pedido"] == "concluido"
    assert fluxo.saldo(pid)["taxa_trato_centavos"] == TAXA_ESPERADA
    assert [c[0] for c in fluxo.fake.chamadas].count("estornar") == 0


def test_liquidacao_durante_disputa_espera(fluxo: Fluxo):
    pid = fluxo.ate_em_confirmacao()
    cobranca = fluxo.servico.cobrancas.do_pedido(pid)[0]
    _abrir_e_responder_disputa(fluxo, pid)
    quieto = TestClient(fluxo.http.app, raise_server_exceptions=False)
    corpo, cabs = fluxo.fake.evento_assinado(
        TipoEvento.LIQUIDACAO, cobranca.id, instante=int(fluxo.amb.relogio.agora.timestamp())
    )
    assert quieto.post("/v1/webhooks/stripe", content=corpo, headers=cabs).status_code == 500
    assert fluxo.ctx.ledger.saldo_da_conta(liberado(PROFISSIONAL.id)) == 0


def test_disputa_encerrada_por_acordo_reparte_normalmente(fluxo: Fluxo):
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    r = fluxo.acao(pid, "encerrar_disputa_por_acordo", "t-cliente")
    assert r.status_code == 200 and r.json()["estado"] == "concluido"
    assert fluxo.saldo(pid)["taxa_trato_centavos"] == TAXA_ESPERADA


# --- retrabalho ---------------------------------------------------------------------------------


def test_retrabalho_nao_mexe_no_dinheiro(fluxo: Fluxo):
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    antes = list(fluxo.ctx.ledger.lancamentos(pid))

    r = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/retrabalho",
        "t-cliente",
        {
            "descricao": "Rodapé solto.",
            "fotos": [{"arquivo_id": "f3", "tirada_em": AGORA.isoformat()}],
        },
    )
    assert r.status_code == 201, r.text
    assert fluxo.pedido(pid)["estado"] == "retrabalho"
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)
    assert list(fluxo.ctx.ledger.lancamentos(pid)) == antes
    assert fluxo.saldo(pid)["taxa_trato_centavos"] == TAXA_ESPERADA


# --- aditivo -------------------------------------------------------------------------------------


def _em_andamento(fluxo: Fluxo) -> str:
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    return pid


def test_aditivo_so_cobra_depois_da_aprovacao_do_cliente(fluxo: Fluxo):
    pid = _em_andamento(fluxo)
    corpo = {"descricao": "Trocar cano escondido", "valor_centavos": 20_000}
    assert (
        fluxo.chamar("POST", f"/v1/pedidos/{pid}/aditivos", "t-cliente", corpo).status_code == 403
    )
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/aditivos", "t-prof", corpo)
    assert r.status_code == 201 and r.json()["estado"] == "proposto"
    aid = r.json()["id"]
    # Proposto não é cobrado nem entra no ledger.
    assert len(fluxo.servico.cobrancas.do_pedido(pid)) == 1
    assert fluxo.saldo(pid)["cliente_pagou_centavos"] == VALOR

    url = f"/v1/pedidos/{pid}/aditivos/{aid}/aprovacao"
    assert fluxo.chamar("POST", url, "t-prof", {"meio": "pix"}).status_code == 403
    r = fluxo.chamar("POST", url, "t-cliente", {"meio": "pix"})
    assert r.status_code == 200, r.text
    assert r.json()["aditivo"]["estado"] == "aprovado"
    cobranca = r.json()["cobranca"]
    assert cobranca["valor_centavos"] == 20_000 and cobranca["status"] == "aguardando"
    assert fluxo.chamar("POST", url, "t-cliente", {"meio": "pix"}).status_code == 409  # já aprovado

    fluxo.fake.marcar_paga(cobranca["id"])
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"]).status_code == 200
    assert fluxo.pedido(pid)["estado"] == "em_andamento"
    assert fluxo.saldo(pid)["retido_centavos"] == VALOR + 20_000
    assert fluxo.servico.aditivos.obter(aid).estado.value == "pago"

    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)
    taxa = 9_000  # 7,5% de 120.000
    saldo = fluxo.saldo(pid)
    assert saldo["taxa_trato_centavos"] == taxa
    assert saldo["a_liberar_centavos"] == 120_000 - taxa


def test_aditivo_so_com_servico_em_andamento(fluxo: Fluxo):
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    corpo = {"descricao": "Extra", "valor_centavos": 1_000}
    assert fluxo.chamar("POST", f"/v1/pedidos/{pid}/aditivos", "t-prof", corpo).status_code == 409
    assert (
        fluxo.chamar(
            "POST", f"/v1/pedidos/{pid}/aditivos", "t-prof", {**corpo, "valor_centavos": 0}
        ).status_code
        == 422
    )


def test_cancelar_devolve_principal_e_aditivo(fluxo: Fluxo):
    pid = _em_andamento(fluxo)
    # com o serviço em andamento o cancelamento não é permitido; o aditivo segue o pedido
    r = fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "x"})
    assert r.status_code == 409
