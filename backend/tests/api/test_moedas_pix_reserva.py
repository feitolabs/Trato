# ruff: noqa: F811
"""R3: o Pix com moedas vence junto com a reserva; webhook tardio não debita em silêncio; o débito
vem ANTES da confirmação da reserva; a expiração acaba o serviço em 2 passos."""

from __future__ import annotations

from conftest import AGORA, CLIENTE
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.agendador.executor import ExecutorContexto
from trato.api.moedas import (
    ConfigMoedas,
    LancamentoMoeda,
    MoedasEmMemoria,
    chave_reserva,
    mes_ref,
)
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.provedor import TipoEvento
from trato.pagamentos.provedor.stripe_teste import ProvedorStripeTeste

MES = mes_ref(AGORA)


class RepoComRegistro(MoedasEmMemoria):
    """Anota a ordem das operações que mexem em saldo e reserva."""

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.ordem: list[str] = []

    def lancar(self, lancamento):
        self.ordem.append(f"lancar:{lancamento.tipo}")
        return super().lancar(lancamento)

    def confirmar_reserva(self, cobranca_id):
        self.ordem.append("confirmar_reserva")
        return super().confirmar_reserva(cobranca_id)


def _ligar(fluxo: Fluxo, saldo=5_000, repo_cls=MoedasEmMemoria, **cfg) -> MoedasEmMemoria:
    cfg = {
        "orcamento_mensal_desconto_centavos": 1_000_000,
        "teto_desconto_cliente_mes_centavos": 1_000_000,
        "teto_diario_desconto_centavos": 1_000_000,
        "dias_liberacao_bonus": 0,
        "valor_moeda_centavos": 1,
        **cfg,
    }
    repo = repo_cls(ConfigMoedas(ativo=True, **cfg))
    repo.lancar(LancamentoMoeda(CLIENTE.id, "bonus_avaliacao", saldo, "bonus:t", AGORA))
    repo.ordem = [] if hasattr(repo, "ordem") else None
    fluxo.ctx.moedas = repo
    return repo


def _cobrar(fluxo: Fluxo, pid, meio="pix", usar_moedas=True):
    return fluxo.chamar(
        "POST",
        f"/v1/contratos/{pid}/cobranca",
        "t-cliente",
        {"meio": meio, "usar_moedas": usar_moedas},
    )


def _pagar(fluxo: Fluxo, cobranca_id: str):
    fluxo.fake.marcar_paga(cobranca_id)
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca_id).status_code == 200


# --- 1) Pix com validade = reserva ---------------------------------------------------------------------


def test_pix_com_moedas_vence_junto_com_a_reserva_e_sem_moedas_fica_intacto(fluxo: Fluxo):
    repo = _ligar(fluxo, reserva_minutos=45)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    assert list(fluxo.fake.expiracoes.values()) == [45 * 60]  # Pix: reserva_minutos × 60
    reserva = repo._reservas[chave_reserva(cob["cobranca_id"])]
    # A reserva dura o Pix + 2 minutos de margem.
    assert (reserva.expira_em - AGORA).total_seconds() == (45 + 2) * 60

    fluxo.fake.expiracoes.clear()
    sem = _cobrar(fluxo, pid, usar_moedas=False)  # troca por uma cobrança sem moedas
    assert sem.status_code == 201 and sem.json()["valor_centavos"] == 100_000
    assert fluxo.fake.expiracoes == {}  # sem moedas: o provedor não recebe validade nenhuma


def test_cartao_com_moedas_nao_manda_validade_de_pix(fluxo: Fluxo):
    _ligar(fluxo)
    pid = fluxo.aceitar()
    assert _cobrar(fluxo, pid, meio="cartao").status_code == 201
    assert fluxo.fake.expiracoes == {}


def test_stripe_manda_expires_after_seconds_so_quando_pedido():
    chamadas = []

    def transporte(metodo, caminho, campos, cabecalhos):
        chamadas.append((metodo, caminho, dict(campos)))
        return 200, {"id": "pi_1", "amount": 5_000, "status": "requires_action", "metadata": {}}

    stripe = ProvedorStripeTeste("sk_test_" + "x" * 12, "segredo", transporte)
    kw = {"valor_centavos": 5_000, "meio": MeioPagamento.PIX, "metadados": {}}
    stripe.criar_cobranca(chave_idempotencia="a", expira_em_segundos=1_800, **kw)
    stripe.criar_cobranca(chave_idempotencia="b", **kw)
    assert chamadas[0][2]["payment_method_options[pix][expires_after_seconds]"] == "1800"
    assert "payment_method_options[pix][expires_after_seconds]" not in chamadas[1][2]
    stripe.cancelar_cobranca("pi_1")
    assert chamadas[2][:2] == ("POST", "/v1/payment_intents/pi_1/cancel")


# --- 2) webhook tardio: não debita em silêncio -----------------------------------------------------------


def test_webhook_tardio_com_reserva_devolvida_e_sem_espaco_vai_para_revisao(fluxo: Fluxo):
    repo = _ligar(fluxo, orcamento_mensal_desconto_centavos=5_000)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    repo.devolver_reserva(chave_reserva(cob["cobranca_id"]))  # a reserva expirou antes do pagamento
    repo.reservar_orcamento(MES, AGORA.date(), 5_000, 5_000, 1_000_000)  # outros levaram o mês
    _pagar(fluxo, cob["cobranca_id"])
    assert fluxo.servico.cobrancas.obter(cob["cobranca_id"]).status is EstadoCobranca.PAGA
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000  # NÃO debitou em silêncio
    revisoes = fluxo.ctx.eventos_webhook.em_revisao()
    assert len(revisoes) == 1 and "sem reserva válida" in revisoes[0][1]
    assert repo.orcamento_usado(MES) == 5_000  # só a reserva dos outros


def test_webhook_tardio_com_reserva_devolvida_reabre_e_debita_se_couber(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    repo.devolver_reserva(chave_reserva(cob["cobranca_id"]))
    _pagar(fluxo, cob["cobranca_id"])
    reaberta = chave_reserva(f"reabertura:{cob['cobranca_id']}")
    assert repo.reserva_status(reaberta) == "confirmada" and repo.orcamento_usado(MES) == 5_000
    assert repo.saldo(CLIENTE.id, AGORA) == 0
    assert fluxo.ctx.eventos_webhook.em_revisao() == ()


def test_webhook_tardio_sem_reserva_reabre_se_couber(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    chave = chave_reserva(cob["cobranca_id"])
    repo.devolver_reserva(chave)
    repo._reservas.pop(chave)  # cobrança sem nenhuma reserva (ex.: criada antes da migration)
    _pagar(fluxo, cob["cobranca_id"])
    assert repo.saldo(CLIENTE.id, AGORA) == 0  # debitou
    assert repo.reserva_status(chave) == "confirmada" and repo.orcamento_usado(MES) == 5_000
    assert fluxo.ctx.eventos_webhook.em_revisao() == ()


def test_webhook_tardio_sem_reserva_e_sem_espaco_vai_para_revisao(fluxo: Fluxo):
    repo = _ligar(fluxo, orcamento_mensal_desconto_centavos=5_000)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    chave = chave_reserva(cob["cobranca_id"])
    repo.devolver_reserva(chave)
    repo._reservas.pop(chave)
    repo.reservar_orcamento(MES, AGORA.date(), 5_000, 5_000, 1_000_000)  # outros levaram o mês
    _pagar(fluxo, cob["cobranca_id"])
    assert repo.saldo(CLIENTE.id, AGORA) == 5_000
    assert len(fluxo.ctx.eventos_webhook.em_revisao()) == 1


def test_webhook_reentregue_depois_de_confirmado_nao_alerta_nem_debita_de_novo(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    _pagar(fluxo, cob["cobranca_id"])
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob["cobranca_id"]).status_code == 200
    assert repo.saldo(CLIENTE.id, AGORA) == 0
    assert fluxo.ctx.eventos_webhook.em_revisao() == ()


# --- 3) N1: debitar primeiro, confirmar depois -----------------------------------------------------------


def test_debita_o_uso_antes_de_confirmar_a_reserva(fluxo: Fluxo):
    repo = _ligar(fluxo, repo_cls=RepoComRegistro)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    repo.ordem.clear()
    _pagar(fluxo, cob["cobranca_id"])
    assert repo.ordem == ["lancar:uso", "confirmar_reserva"]
    assert repo.saldo(CLIENTE.id, AGORA) == 0
    # Reentrega: o débito é idempotente e a confirmação também (nada em dobro).
    fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob["cobranca_id"])
    assert repo.saldo(CLIENTE.id, AGORA) == 0


# --- 4) expiração em 2 passos --------------------------------------------------------------------------------


def test_cobranca_pendurada_com_reserva_devolvida_e_cancelada_no_ciclo_seguinte(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    rotina = ExecutorContexto(fluxo.ctx, None, fluxo.servico.cobrancas, fluxo.fake)

    # O processo caiu depois do SQL devolver e antes de cancelar a cobrança: reserva 'devolvida',
    # cobrança ainda AGUARDANDO, e `expirar_reservas` já não a traz na lista.
    repo.devolver_reserva(chave_reserva(cob["cobranca_id"]))
    assert fluxo.servico.cobrancas.obter(cob["cobranca_id"]).status is EstadoCobranca.AGUARDANDO
    assert repo.expirar_reservas(fluxo.ctx.agora()) == []

    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 1
    assert fluxo.servico.cobrancas.obter(cob["cobranca_id"]).status is EstadoCobranca.CANCELADA
    assert ("cancelar_cobranca", cob["cobranca_id"]) in fluxo.fake.chamadas  # e no provedor
    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 0  # idempotente
    assert fluxo.fake.chamadas.count(("cancelar_cobranca", cob["cobranca_id"])) == 1


def test_expiracao_cancela_no_provedor_e_ignora_cobranca_sem_moedas(fluxo: Fluxo):
    repo = _ligar(fluxo, reserva_minutos=30)
    pid = fluxo.aceitar()
    _cobrar(fluxo, pid)  # com moedas
    rotina = ExecutorContexto(fluxo.ctx, None, fluxo.servico.cobrancas, fluxo.fake)
    fluxo.amb.relogio.avancar(minutes=33)  # 30 min + 2 de margem + 1
    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 1
    assert [c for c in fluxo.fake.chamadas if c[0] == "cancelar_cobranca"]
    assert repo.orcamento_usado(MES) == 0


def test_falha_ao_cancelar_no_provedor_nao_impede_o_cancelamento_local(fluxo: Fluxo):
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    repo.devolver_reserva(chave_reserva(cob["cobranca_id"]))

    def quebrar(_id):
        raise RuntimeError("stripe fora do ar")

    fluxo.fake.cancelar_cobranca = quebrar
    rotina = ExecutorContexto(fluxo.ctx, None, fluxo.servico.cobrancas, fluxo.fake)
    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 1
    assert fluxo.servico.cobrancas.obter(cob["cobranca_id"]).status is EstadoCobranca.CANCELADA


def test_cobranca_sem_reserva_nenhuma_nao_e_cancelada_pela_expiracao(fluxo: Fluxo):
    """Cobrança antiga (sem linha em moedas_reservas) não é tocada: só 'devolvida' cancela."""
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    repo._reservas.pop(chave_reserva(cob["cobranca_id"]))
    rotina = ExecutorContexto(fluxo.ctx, None, fluxo.servico.cobrancas, fluxo.fake)
    assert rotina.expirar_reservas_moedas(fluxo.ctx.agora()) == 0
    assert fluxo.servico.cobrancas.obter(cob["cobranca_id"]).status is EstadoCobranca.AGUARDANDO
