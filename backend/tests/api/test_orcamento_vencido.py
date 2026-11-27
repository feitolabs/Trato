"""BE-52 (Termos 5.2, 5.3 e 6.3): orçamento vencido não é aceito, renegociado nem cobrado;
pagamento confirmado depois da validade volta inteiro. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from decimal import Decimal

import pytest
from conftest import PROFISSIONAL
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401

from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.provedor.base import TipoEvento
from trato.pedidos.estados import Estado
from trato.persistencia.orcamentos import ItemOrcamento

H = timedelta(hours=1)
SEG = timedelta(seconds=1)


def orcamento(f, validade) -> tuple[str, str]:
    r = f.chamar("POST", "/v1/pedidos", "t-cliente")
    assert r.status_code == 201, r.text
    pid = r.json()["id"]
    oid = f.ctx.orcamentos.enviar(
        pedido_id=pid,
        profissional_id=PROFISSIONAL.id,
        itens=[ItemOrcamento("outro", "Pintura", Decimal(1), VALOR)],
        agora=f.ctx.agora(),
        prazo_execucao_dias=3,
        validade_ate=validade,
    )
    return pid, oid


def aceitar(f, pid, oid):
    return f.acao(pid, "aceitar_orcamento", "t-cliente", {"orcamento_id": oid})


def aceito(f, validade_em=H) -> str:
    pid, oid = orcamento(f, f.ctx.agora() + validade_em)
    assert aceitar(f, pid, oid).status_code == 200
    return pid


def vencido(r) -> bool:
    return r.status_code == 409 and r.json().get("codigo") == "orcamento_vencido"


def estornos(f, cobranca_id):
    return [e.valor_centavos for e in f.fake.estornos_da_cobranca(cobranca_id)]


def pagar_em(f, cobranca_id, **kw):
    f.fake.marcar_paga(cobranca_id)
    return f.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca_id, **kw)


@pytest.mark.parametrize("passou", [timedelta(), SEG])
def test_vencido_no_instante_ou_depois_nao_e_aceito(fluxo, passou):
    pid, oid = orcamento(fluxo, fluxo.ctx.agora() + H)
    fluxo.amb.relogio.avancar(seconds=(H + passou).total_seconds())
    assert vencido(aceitar(fluxo, pid, oid))
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.ABERTO
    assert fluxo.ctx.contratos.obter_do_pedido(pid) is None


@pytest.mark.parametrize("validade", [None, SEG])
def test_no_prazo_ou_sem_validade_aceita(fluxo, validade):
    pid, oid = orcamento(fluxo, None if validade is None else fluxo.ctx.agora() + validade)
    r = aceitar(fluxo, pid, oid)
    assert r.status_code == 200, r.text


def test_contraproposta_aceite_e_proposta_recusam_vencido_sem_nova_versao(fluxo):
    pid, oid = orcamento(fluxo, fluxo.ctx.agora() + H)
    fluxo.amb.relogio.avancar(hours=2)
    base = f"/v1/pedidos/{pid}/orcamentos/{oid}"
    novo = {"valor_centavos": VALOR - 100}
    for caminho, quem in (
        ("contraproposta", "t-cliente"),
        ("contraproposta/aceitar", "t-prof"),
        ("propor", "t-prof"),
    ):
        r = fluxo.chamar("POST", f"{base}/{caminho}", quem, novo)
        assert vencido(r), (caminho, r.text)
    assert [o.id for o in fluxo.ctx.orcamentos.do_pedido(pid)] == [oid]


def test_orcamento_novo_nao_nasce_vencido(fluxo):
    pid = fluxo.chamar("POST", "/v1/pedidos", "t-cliente").json()["id"]
    corpo = {
        "itens": [
            {
                "tipo": "outro",
                "descricao": "Pintura",
                "quantidade": 1,
                "valor_unitario_centavos": VALOR,
            }
        ],
        "validade_ate": fluxo.ctx.agora().isoformat(),
    }
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/orcamentos", "t-prof", corpo)
    assert r.status_code == 422 and "futura" in r.text, r.text
    assert not fluxo.ctx.orcamentos.do_pedido(pid)


def test_vencido_nao_gera_cobranca_nem_reaproveita_a_pendente(fluxo):
    pid = aceito(fluxo)
    pendente = fluxo.cobrar(pid)
    fluxo.amb.relogio.avancar(hours=1)
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", {"meio": "pix"})
    assert vencido(r), r.text
    assert [c.id for c in fluxo.servico.cobrancas.do_pedido(pid)] == [pendente["id"]]


def test_pago_depois_da_validade_volta_inteiro_uma_vez(fluxo):
    pid = aceito(fluxo)
    cobranca = fluxo.cobrar(pid)
    fluxo.amb.relogio.avancar(hours=1)
    assert pagar_em(fluxo, cobranca["id"]).status_code == 200
    assert pagar_em(fluxo, cobranca["id"]).status_code == 200  # mesmo evento
    assert pagar_em(fluxo, cobranca["id"], evento_id="evt_outro").status_code == 200
    assert estornos(fluxo, cobranca["id"]) == [cobranca["valor_centavos"]]
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.ORCAMENTO_ACEITO
    assert fluxo.tipos(pid) == []
    assert fluxo.servico.cobrancas.obter(cobranca["id"]).status is EstadoCobranca.DEVOLVIDA


def test_avisos_ao_mesmo_tempo_estornam_uma_vez(fluxo):
    pid = aceito(fluxo)
    cobranca = fluxo.cobrar(pid)
    fluxo.amb.relogio.avancar(hours=2)
    fluxo.fake.marcar_paga(cobranca["id"])
    with ThreadPoolExecutor(4) as grupo:
        respostas = list(
            grupo.map(
                lambda n: fluxo.webhook(
                    TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"], evento_id=f"evt_{n}"
                ),
                range(4),
            )
        )
    assert {r.status_code for r in respostas} == {200}
    assert estornos(fluxo, cobranca["id"]) == [cobranca["valor_centavos"]]
    assert fluxo.tipos(pid) == []


def test_pago_no_prazo_com_aviso_atrasado_contrata(fluxo):
    pid = aceito(fluxo)
    cobranca = fluxo.cobrar(pid)
    pago_em = int(fluxo.ctx.agora().timestamp())
    fluxo.amb.relogio.avancar(hours=1, seconds=1)  # o aviso chega depois da validade
    fluxo.fake.marcar_paga(cobranca["id"])
    # `created` é o da confirmação; a assinatura é a do envio (agora).
    corpo, _ = fluxo.fake.evento_assinado(
        TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"], instante=pago_em
    )
    assinatura = fluxo.fake.assinar(corpo, int(fluxo.ctx.agora().timestamp()), None)
    r = fluxo.http.post(
        "/v1/webhooks/stripe", content=corpo, headers={"Stripe-Signature": assinatura}
    )
    assert r.status_code == 200, r.text
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.PAGO_E_RETIDO
    assert estornos(fluxo, cobranca["id"]) == []
