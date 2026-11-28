"""BE-REORCAR (Termos 5.2 e 6.3): sem pagamento no prazo o contrato cai, o pedido aceita um
orçamento NOVO e o dinheiro atrasado do contrato antigo volta. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace

import pytest
from conftest import PROFISSIONAL
from test_agendador import montar
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.api.repositorios import Contrato, Orcamento
from trato.financeiro.ledger import CUSTODIA
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.provedor.base import TipoEvento
from trato.pedidos.estados import Acao, Estado
from trato.persistencia.erros import Duplicado, RegraDoBanco
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina


def executor(f) -> ExecutorContexto:
    s = f.servico
    return ExecutorContexto(f.ctx, None, s.cobrancas, s.provedor, s)


def acao_de_expirar(pid) -> AcaoRotina:
    return AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"expira:{pid}", acao=Acao.EXPIRAR_PAGAMENTO
    )


def expirar(f, pid) -> None:
    f.amb.relogio.avancar(hours=25)
    executor(f).executar(acao_de_expirar(pid), f.ctx.agora())


def novo_orcamento(f, pid, oid="orc-novo") -> str:
    f.ctx.orcamentos.adicionar(Orcamento(oid, pid, PROFISSIONAL.id, VALOR, "pintura"))
    return oid


def aceitar(f, pid, oid):
    return f.acao(pid, "aceitar_orcamento", "t-cliente", {"orcamento_id": oid})


def estornos(f, cobranca_id):
    return [e.valor_centavos for e in f.fake.estornos_da_cobranca(cobranca_id)]


def pagar(f, cobranca_id, **kw):
    f.fake.marcar_paga(cobranca_id)
    return f.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca_id, **kw)


def estado(f, pid) -> Estado:
    return f.ctx.pedidos.obter(pid).estado


def test_expira_novo_orcamento_aceita_e_paga(fluxo):
    pid = fluxo.aceitar()
    velha = fluxo.cobrar(pid)
    expirar(fluxo, pid)
    assert estado(fluxo, pid) is Estado.ABERTO
    assert fluxo.ctx.contratos.obter_do_pedido(pid) is None
    assert fluxo.ctx.pedidos.obter(pid).profissional_id is None
    assert fluxo.ctx.orcamentos.detalhe("orc-e2e").status == "expirado"
    antiga = fluxo.servico.cobrancas.obter(velha["id"])
    assert antiga.status is EstadoCobranca.CANCELADA and antiga.contrato_encerrado
    assert ("cancelar_cobranca", velha["id"]) in fluxo.fake.chamadas
    assert aceitar(fluxo, pid, "orc-e2e").status_code >= 400  # o antigo não reabre
    assert estado(fluxo, pid) is Estado.ABERTO

    assert aceitar(fluxo, pid, novo_orcamento(fluxo, pid)).status_code == 200
    url = f"/v1/contratos/{pid}/pagamento"
    vista = fluxo.chamar("GET", url, "t-cliente").json()
    assert (vista["estado_pagamento"], vista["cobranca_id"]) == ("sem_cobranca", None)
    nova = fluxo.cobrar(pid)
    assert nova["id"] != velha["id"]
    assert pagar(fluxo, nova["id"]).status_code == 200
    assert estado(fluxo, pid) is Estado.PAGO_E_RETIDO
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR


@pytest.mark.parametrize("com_novo_aceite", [False, True])
def test_pagamento_atrasado_do_antigo_volta_e_nao_confirma_o_novo(fluxo, com_novo_aceite):
    pid = fluxo.aceitar()
    velha = fluxo.cobrar(pid)
    expirar(fluxo, pid)
    if com_novo_aceite:
        assert aceitar(fluxo, pid, novo_orcamento(fluxo, pid)).status_code == 200
    antes = estado(fluxo, pid)
    assert pagar(fluxo, velha["id"]).status_code == 200
    assert pagar(fluxo, velha["id"], evento_id="evt_repetido").status_code == 200
    assert estornos(fluxo, velha["id"]) == [velha["valor_centavos"]]
    assert fluxo.webhook(TipoEvento.ESTORNO_CONFIRMADO, velha["id"]).status_code == 200
    assert estado(fluxo, pid) is antes
    assert fluxo.tipos(pid) == []
    assert fluxo.servico.cobrancas.obter(velha["id"]).status is EstadoCobranca.DEVOLVIDA
    (alerta,) = fluxo.ctx.eventos_webhook.em_revisao()
    assert "contrato cancelado" in str(alerta)
    if com_novo_aceite:  # o contrato novo segue pagável, e o aviso antigo não tira nada dele
        nova = fluxo.cobrar(pid)
        assert pagar(fluxo, nova["id"]).status_code == 200
        outro = {"evento_id": "evt_est_2"}
        assert fluxo.webhook(TipoEvento.ESTORNO_CONFIRMADO, velha["id"], **outro).status_code == 200
        assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR
        assert not executor(fluxo)._pedido_estornado_ou_cancelado(pid)


def test_repetir_a_expiracao_nao_derruba_o_contrato_novo(fluxo):
    pid = fluxo.aceitar()
    expirar(fluxo, pid)
    assert aceitar(fluxo, pid, novo_orcamento(fluxo, pid)).status_code == 200
    executor(fluxo).executar(acao_de_expirar(pid), fluxo.ctx.agora())  # o prazo novo não venceu
    assert estado(fluxo, pid) is Estado.ORCAMENTO_ACEITO
    assert fluxo.ctx.contratos.obter_do_pedido(pid).orcamento_id == "orc-novo"


def test_contrato_com_dinheiro_nunca_e_cancelado(fluxo):
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    guardada = fluxo.servico.cobrancas.obter(cobranca["id"])
    fluxo.servico.cobrancas.salvar(replace(guardada, status=EstadoCobranca.PAGA))
    fluxo.amb.relogio.avancar(hours=25)
    with pytest.raises(Adiada, match="pagamento_recebido"):
        executor(fluxo).executar(acao_de_expirar(pid), fluxo.ctx.agora())
    assert estado(fluxo, pid) is Estado.ORCAMENTO_ACEITO
    assert fluxo.ctx.contratos.obter_do_pedido(pid).orcamento_id == "orc-e2e"


def test_pedido_reaberto_conta_a_validade_da_reabertura(fluxo):
    pid = fluxo.aceitar()
    fluxo.amb.relogio.avancar(days=30)  # bem além do prazo para receber orçamentos
    agendador, _, _ = montar(fluxo.amb, executor=executor(fluxo))
    agendador.rodar_uma_vez()
    assert estado(fluxo, pid) is Estado.ABERTO
    agendador.rodar_uma_vez()
    assert estado(fluxo, pid) is Estado.ABERTO


def test_memoria_imita_um_contrato_vigente_por_pedido(fluxo):
    pid = fluxo.aceitar()
    novo_orcamento(fluxo, pid)
    outro = Contrato(pid, "orc-novo", PROFISSIONAL.id, VALOR)
    with pytest.raises(Duplicado):
        fluxo.ctx.contratos.salvar(outro)
    expirar(fluxo, pid)
    with pytest.raises(RegraDoBanco):
        fluxo.ctx.contratos.salvar(Contrato(pid, "orc-e2e", PROFISSIONAL.id, VALOR))
    fluxo.ctx.contratos.salvar(outro)
    # como o banco (`regras_aplicadas`), o aceite grava o retrato das regras
    regras = fluxo.ctx.contratos.regras_no_aceite()
    assert regras
    assert fluxo.ctx.contratos.obter_do_pedido(pid) == replace(outro, regras=regras)


def test_cobranca_que_volta_depois_do_prazo_nao_e_entregue(fluxo):
    """O prazo vence enquanto o provedor cria a cobrança: ela é cancelada e não fica."""
    pid = fluxo.aceitar()
    criar = fluxo.fake.criar_cobranca
    criadas = []

    def criar_devagar(**kw):
        resultado = criar(**kw)
        criadas.append(resultado.id)
        expirar(fluxo, pid)
        return resultado

    fluxo.fake.criar_cobranca = criar_devagar
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", {"meio": "pix"})
    assert r.status_code == 409, r.text
    assert fluxo.servico.cobrancas.obter(criadas[0]) is None
    assert ("cancelar_cobranca", criadas[0]) in fluxo.fake.chamadas
    fluxo.fake.criar_cobranca = criar
    assert aceitar(fluxo, pid, novo_orcamento(fluxo, pid)).status_code == 200
    assert fluxo.cobrar(pid)["id"] != criadas[0]
