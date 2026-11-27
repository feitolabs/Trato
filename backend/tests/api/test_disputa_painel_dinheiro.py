"""FIX-DISPUTA-PAINEL: a decisão do painel pede o estorno ao provedor pelo mesmo caminho da rota
do pedido (Termos 6.10, 6.11 e 8.6). Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import threading

import pytest
from admin_ambiente import AGORA, PEDIDO, adm, cab  # noqa: F401

from trato.financeiro.contestacoes import Contestacao, StatusContestacao
from trato.financeiro.ledger import CUSTODIA
from trato.pagamentos.provedor import ErroProvedor
from trato.pedidos.estados import Estado

URL = f"/v1/admin/disputas/{PEDIDO}"
VALOR = 100_000


def decidir(adm, resultado, quem="t-mediador", **extra):
    corpo = {"resultado": resultado, "justificativa": "Fotos conferidas.", **extra}
    return adm.cliente.post(f"{URL}/decisao", json=corpo, headers=cab(quem))


def aprovar(adm, quem="t-administrador"):
    return adm.cliente.post(
        f"{URL}/aprovacao", json={"justificativa": "Concordo com a decisão."}, headers=cab(quem)
    )


def ordens(adm) -> list[tuple[int, str]]:
    return [(o.valor_centavos, o.estado) for o in adm.pagamento.ordens.do_pedido(PEDIDO)]


def no_provedor(adm) -> int:
    servico = adm.pagamento
    return sum(
        e.valor_centavos
        for c in servico.cobrancas.do_pedido(PEDIDO)
        for e in servico.provedor.estornos_da_cobranca(c.id)
    )


def chamadas_de_estorno(adm) -> int:
    return sum(1 for nome, _ in adm.pagamento.provedor.chamadas if nome == "estornar")


@pytest.mark.parametrize(
    "resultado,extra,devolvido",
    [
        ("reembolso_total", {}, VALOR),
        ("reembolso_parcial", {"valor_cliente_centavos": 30_000}, 30_000),
    ],
)
def test_painel_pede_o_estorno_ao_provedor_uma_vez(adm, resultado, extra, devolvido):
    adm.semear_disputa()
    assert decidir(adm, resultado, **extra).status_code == 200
    assert ordens(adm) == [(devolvido, "enviada")] and no_provedor(adm) == devolvido
    assert adm.contexto.ledger.saldo_da_conta(CUSTODIA, PEDIDO) == 0
    repasses = list(adm.contexto.repasses.do_pedido(PEDIDO))
    assert sum(r.valor_liquido_centavos for r in repasses) == VALOR - devolvido
    for outra in (decidir(adm, resultado, **extra), aprovar(adm)):
        assert outra.status_code == 409, outra.text
    assert ordens(adm) == [(devolvido, "enviada")] and chamadas_de_estorno(adm) == 1


@pytest.mark.parametrize("resultado", ["liberar_tudo", "nova_visita"])
def test_sem_reembolso_nao_ha_ordem(adm, resultado):
    adm.semear_disputa()
    assert decidir(adm, resultado).status_code == 200
    assert ordens(adm) == [] and chamadas_de_estorno(adm) == 0


def test_nada_vai_ao_provedor_antes_da_aprovacao_e_a_aprovacao_dupla_nao_duplica(adm):
    adm.semear_disputa()
    assert decidir(adm, "reembolso_total", quem="t-mediador_sem_alcada").status_code == 200
    assert ordens(adm) == [] and chamadas_de_estorno(adm) == 0
    assert len(adm.lancamentos()) == 1
    assert aprovar(adm).status_code == 200
    assert aprovar(adm).status_code == 409
    assert aprovar(adm, "t-administrador2").status_code == 409
    assert ordens(adm) == [(VALOR, "enviada")] and chamadas_de_estorno(adm) == 1


def _juntos(*chamadas) -> list[int]:
    barreira, codigos = threading.Barrier(len(chamadas)), []

    def rodar(chamada) -> None:
        barreira.wait()
        codigos.append(chamada().status_code)

    fios = [threading.Thread(target=rodar, args=(c,)) for c in chamadas]
    [f.start() for f in fios]
    [f.join(30) for f in fios]
    return sorted(codigos)


def test_decisoes_ao_mesmo_tempo_so_uma_vale(adm):
    adm.semear_disputa()
    parcial = {"valor_cliente_centavos": 30_000}
    codigos = _juntos(
        *[lambda: decidir(adm, "reembolso_parcial", **parcial) for _ in range(3)],
        *[lambda: decidir(adm, "reembolso_total") for _ in range(3)],
    )
    assert codigos == [200] + [409] * 5
    (ordem,) = ordens(adm)
    assert no_provedor(adm) == ordem[0] and chamadas_de_estorno(adm) == 1


def test_aprovacoes_ao_mesmo_tempo_so_uma_vale(adm):
    adm.semear_disputa()
    decidir(adm, "reembolso_total", quem="t-mediador_sem_alcada")
    codigos = _juntos(
        lambda: aprovar(adm), lambda: aprovar(adm, "t-administrador2"), lambda: aprovar(adm)
    )
    assert codigos == [200, 409, 409] and ordens(adm) == [(VALOR, "enviada")]
    assert chamadas_de_estorno(adm) == 1


def test_provedor_fora_deixa_a_ordem_pendente_e_a_rotina_reenvia_uma_vez(adm, monkeypatch):
    adm.semear_disputa()
    servico = adm.pagamento

    def fora(*args):
        raise ErroProvedor("fora do ar")

    with monkeypatch.context() as m:
        m.setattr(servico.provedor, "estornar", fora)
        assert decidir(adm, "reembolso_total").status_code == 200
    assert ordens(adm) == [(VALOR, "pendente")] and adm.pedido().estado is Estado.CANCELADO
    assert servico.reenviar_estornos() == 1 and servico.reenviar_estornos() == 0
    assert ordens(adm) == [(VALOR, "enviada")] and no_provedor(adm) == VALOR


def _perder_na_emissora(adm, valor: int) -> None:
    (cobranca,) = adm.pagamento.cobrancas.do_pedido(PEDIDO)
    corpo, cabecalhos = adm.pagamento.provedor.evento_assinado(
        __import__("trato.pagamentos.provedor", fromlist=["TipoEvento"]).TipoEvento.CONTESTACAO,
        cobranca.id,
        valor_centavos=valor,
        status_contestacao="lost",
        instante=int(AGORA.timestamp()),
    )
    r = adm.cliente.post("/v1/webhooks/stripe", content=corpo, headers=cabecalhos)
    assert r.status_code == 200, r.text


@pytest.mark.parametrize(
    "resultado,parte,a_devolver",
    [
        ("reembolso_total", None, 70_000),
        ("reembolso_parcial", 20_000, 0),  # a emissora já devolveu mais que a parte dele
        ("reembolso_parcial", 50_000, 20_000),
    ],
)
def test_o_que_a_emissora_devolveu_conta_na_parte_do_cliente(adm, resultado, parte, a_devolver):
    adm.semear_disputa()
    adm.contexto.contestacoes.salvar(
        Contestacao("dp_1", 30_000, StatusContestacao.PERDIDA, AGORA, AGORA, None, PEDIDO,
                    encerrada_em=AGORA)
    )  # fmt: skip
    # a contestação já lançada no ledger e na cobrança, como o webhook faz
    from trato.financeiro.ledger import Livro, estornar_pedido

    livro = Livro()
    livro.lancar_varios(adm.lancamentos())
    antes = len(livro.lancamentos)
    estornar_pedido(livro, PEDIDO, 30_000, "contest/dp_1", AGORA)
    adm.contexto.ledger.lancar_varios(livro.lancamentos[antes:])
    servico = adm.pagamento
    (cobranca,) = servico.cobrancas.do_pedido(PEDIDO)
    from dataclasses import replace

    servico.cobrancas.salvar(replace(cobranca, estornado_centavos=30_000))

    extra = {} if parte is None else {"valor_cliente_centavos": parte}
    r = decidir(adm, resultado, **extra)

    assert r.status_code == 200, r.text
    assert sum(v for v, _ in ordens(adm)) == a_devolver == no_provedor(adm)
    assert adm.contexto.ledger.saldo_da_conta(CUSTODIA, PEDIDO) == 0


def test_sem_servico_de_pagamento_nada_se_move(adm):
    adm.semear_disputa()
    adm.cliente.app.state.servico_pagamento = None
    assert decidir(adm, "reembolso_total").status_code == 503
    assert adm.pedido().estado is Estado.EM_DISPUTA and len(adm.lancamentos()) == 1


def test_sem_cobranca_confirmada_a_decisao_e_recusada_sem_gravar(adm):
    from dataclasses import replace

    from trato.pagamentos.modelos import EstadoCobranca

    adm.semear_disputa()
    (cobranca,) = adm.pagamento.cobrancas.do_pedido(PEDIDO)
    adm.pagamento.cobrancas.salvar(replace(cobranca, status=EstadoCobranca.FALHOU))
    with pytest.raises(Exception, match="pagamento confirmado"):
        r = decidir(adm, "reembolso_total")
        assert r.status_code == 409, r.text
        raise AssertionError(r.json()["detail"])
    assert adm.pedido().estado is Estado.EM_DISPUTA and len(adm.lancamentos()) == 1
