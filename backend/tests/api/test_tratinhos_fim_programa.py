"""BE-AVISO-TRATINHOS (Termos 13.11 e I.12): mudar ou desligar o programa não reduz a validade
nem impede o uso do que já foi creditado; o aviso sai no app e por e-mail. Memória."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_avisos_previos import dia, enviar, preparar
from test_cautela_rotas import bloqueada, encerrar, incidente, negociacao, orcamentos
from test_contraproposta import ORCAMENTO
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401
from test_moedas_desconto import _GRANDE

from trato.api.moedas import ConfigMoedas, LancamentoMoeda, MoedasEmMemoria, calcular_uso_moedas
from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Estado

VENCE = AGORA + timedelta(days=90)


def creditar(repo, quantidade=5_000, expira_em=VENCE):
    repo.lancar(
        LancamentoMoeda(
            CLIENTE.id, "bonus_avaliacao", quantidade, "bonus:fim", AGORA, expira_em=expira_em
        )
    )


def test_desligar_e_encurtar_validade_nao_atingem_o_ja_creditado(fluxo):
    preparar(fluxo.amb)
    tetos = ("teto_desconto_cliente_mes_centavos", "teto_diario_desconto_centavos")
    cfg = _GRANDE | dict.fromkeys(tetos, 10_000_000)  # o máximo que o painel aceita
    repo = fluxo.ctx.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True, **cfg))
    creditar(repo)
    atual = fluxo.chamar("GET", "/v1/admin/moedas/config", "t-admin")
    assert atual.status_code == 200, atual.text
    novo = atual.json() | {"ativo": False, "validade_dias": 1, "motivo": "Fim do programa."}
    # 13.11: a piora só vale 30 dias depois do aviso (aqui, emitido 30 dias antes de hoje)
    fluxo.amb.relogio.avancar(days=-30)
    aviso = {
        "tipo": "tratinhos",
        "referencia": "fim",
        "vigencia": dia(fluxo.amb, 30),
        "resumo": "O programa vai ser encerrado.",
        "mudancas": {"ativo": False, "validade_dias": 1},
    }
    assert enviar(fluxo.amb, aviso).status_code == 200
    fluxo.amb.relogio.avancar(days=30)
    novo["aviso_referencia"] = "fim"
    r = fluxo.chamar("PUT", "/v1/admin/moedas/config", "t-admin", novo)
    assert r.status_code == 200 and r.json()["ativo"] is False, r.text

    (credito,) = repo.lancamentos_da_carteira(CLIENTE.id)
    assert credito.expira_em == VENCE
    assert repo.saldo(CLIENTE.id, VENCE - timedelta(seconds=1)) == 5_000

    pid = fluxo.aceitar()
    url = f"/v1/pedidos/{pid}/pagamento?usar_moedas=true"
    previa = fluxo.chamar("GET", url, "t-cliente").json()
    assert previa["desconto_disponivel"] is True and previa["moedas_usadas"] == 5_000, previa
    r = fluxo.chamar(
        "POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix", "usar_moedas": True}
    )
    assert r.status_code == 201, r.text
    cob = r.json()
    assert cob["valor_centavos"] == 95_000
    fluxo.fake.marcar_paga(cob["cobranca_id"])
    for _ in range(2):  # reentrega não debita de novo
        assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob["cobranca_id"]).status_code == 200
    assert repo.saldo(CLIENTE.id, AGORA) == 0


def test_desligado_respeita_o_vencimento():
    repo = MoedasEmMemoria(ConfigMoedas(ativo=False, **_GRANDE))
    creditar(repo)
    args = {"usuario_id": CLIENTE.id, "servico_centavos": 100_000}
    vespera = calcular_uso_moedas(repo, agora=VENCE - timedelta(seconds=1), **args)
    assert (vespera.moedas, vespera.disponivel) == (5_000, True)
    vencido = calcular_uso_moedas(repo, agora=VENCE + timedelta(seconds=1), **args)
    assert (vencido.moedas, vencido.disponivel) == (0, False)


def test_desligado_sem_como_ler_o_saldo_nao_da_desconto_nem_quebra():
    class SemTabela(MoedasEmMemoria):
        def saldo(self, *a, **k):
            raise RuntimeError("tabela ausente")

    uso = calcular_uso_moedas(
        SemTabela(ConfigMoedas(ativo=False)),
        usuario_id=CLIENTE.id,
        servico_centavos=100_000,
        agora=AGORA,
    )
    assert (uso.moedas, uso.disponivel) == (0, False)


def test_aviso_dos_tratinhos_sai_no_app_e_por_email_mesmo_com_tudo_desligado(fluxo):
    amb = fluxo.amb
    email = preparar(amb)
    corpo = {
        "tipo": "tratinhos",
        "referencia": "fim",
        "vigencia": dia(amb, 30),
        "resumo": "O programa deixa de creditar novos.",
    }
    r = enviar(amb, corpo)
    assert r.status_code == 200, r.text
    destinatarios = r.json()["destinatarios"]
    assert r.json()["avisos_novos"] >= destinatarios + 2  # app para todos e e-mail
    assert {CLIENTE.id, PROFISSIONAL.id} <= {m.usuario_id for m in email.enviados}
    assert enviar(amb, corpo).json()["avisos_novos"] == 0


def test_orcamento_novo_e_recusado_com_contato_bloqueado(amb):
    negociacao(amb)  # ped-1 já tem um orçamento; o relato é de outro pedido do mesmo par
    amb.semear_pedido(Estado.ABERTO, id="ped-2", orcamento_id=None, profissional_id=None)
    iid = incidente(amb.contexto, "ped-0", "bloquear_contato")
    antes = orcamentos(amb)

    def orcar():
        url = "/v1/pedidos/ped-2/orcamentos"
        return amb.cliente.post(url, json=ORCAMENTO, headers=cab("t-prof"))

    r = orcar()
    assert bloqueada(r), r.text
    assert orcamentos(amb) == antes
    encerrar(amb.contexto, iid)
    r = orcar()
    assert r.status_code == 201, r.text
