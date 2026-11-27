"""TERMOS-BE-ACORDO (8.2): o cliente aceita a devolução proposta pelo profissional. Memória."""

from __future__ import annotations

import threading

import pytest
from test_fluxo_pagamento_e2e import DISPUTA, VALOR, Fluxo, fluxo  # noqa: F401
from test_liberacao_automatica import agendador_de, liberado_de

from trato.api.acordo_disputa import texto_da_proposta
from trato.financeiro.contestacoes import Contestacao, StatusContestacao

PARTE = 25_000
ACEITE = {"solucao": "reembolso_parcial", "reembolso_centavos": PARTE}
DECISAO = {"resultado": "reembolso_total", "justificativa": "Não foi entregue."}


def respondida(fluxo: Fluxo, solucao="reembolso_parcial", valor=PARTE) -> str:  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    url = f"/v1/pedidos/{pid}/disputa"
    assert fluxo.chamar("POST", url, "t-cliente", DISPUTA).status_code == 201
    corpo = {"mensagem": "Proponho resolver assim.", "solucao": solucao}
    if valor is not None:
        corpo["reembolso_parcial_centavos"] = valor
    r = fluxo.chamar("POST", f"{url}/resposta", "t-prof", corpo)
    assert r.status_code == 200, r.text
    return pid


def aceitar(fluxo, pid, corpo=ACEITE, quem="t-cliente"):  # noqa: F811
    return fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/aceitar-proposta", quem, corpo)


def ver(fluxo, pid, quem="t-cliente"):  # noqa: F811
    return fluxo.chamar("GET", f"/v1/pedidos/{pid}/disputa", quem).json()


def foto_do_dinheiro(fluxo, pid):  # noqa: F811
    return (
        [i.chave for i in fluxo.ctx.ledger.lancamentos(pid)],
        [(o.chave, o.valor_centavos, o.estado) for o in fluxo.servico.ordens.do_pedido(pid)],
    )


def estornado(fluxo, pid) -> int:  # noqa: F811
    return sum(o.valor_centavos for o in fluxo.servico.ordens.do_pedido(pid))


def juntos(*funcoes):
    respostas = [None] * len(funcoes)

    def rodar(n, funcao):
        respostas[n] = funcao()

    threads = [threading.Thread(target=rodar, args=item) for item in enumerate(funcoes)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return respostas


@pytest.mark.parametrize("centavos", [1, 5, 100, 123_456_789])
def test_texto_da_proposta_guarda_os_centavos(centavos):
    reais = f"{centavos / 100:.2f}".replace(".", ",")
    assert texto_da_proposta(centavos) == f"Propõe reembolso parcial de R$ {reais}."


def test_aceite_devolve_a_parte_e_o_resto_segue_a_liberacao_uma_vez(fluxo):  # noqa: F811
    pid = respondida(fluxo)
    antes = ver(fluxo, pid)
    assert antes["acordo"] is None and antes["proposta"]["respondida_em"]
    assert {k: antes["proposta"][k] for k in ACEITE} == ACEITE
    r = aceitar(fluxo, pid)
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "acordo"
    esperado = ACEITE | {"liberado_centavos": VALOR - PARTE}
    assert r.json()["acordo"] == esperado and r.json() == ver(fluxo, pid)
    assert fluxo.pedido(pid)["estado"] == "concluido"
    assert fluxo.saldo(pid)["a_liberar_centavos"] == VALOR - PARTE
    assert estornado(fluxo, pid) == PARTE
    dinheiro = foto_do_dinheiro(fluxo, pid)
    repetido = aceitar(fluxo, pid)
    assert repetido.status_code == 200 and repetido.json() == r.json()
    assert foto_do_dinheiro(fluxo, pid) == dinheiro
    agendador = agendador_de(fluxo)
    for _ in range(2):
        agendador.rodar_uma_vez()
        assert liberado_de(fluxo, pid) == VALOR - PARTE


def test_chargeback_segura_o_restante(fluxo):  # noqa: F811
    pid = respondida(fluxo)
    assert aceitar(fluxo, pid).status_code == 200
    agora = fluxo.amb.relogio.agora
    fluxo.ctx.contestacoes.salvar(
        Contestacao("dp_a", 100, StatusContestacao.ABERTA, agora, agora, pedido_id=pid)
    )
    fluxo.amb.relogio.avancar(days=30)
    agendador_de(fluxo).rodar_uma_vez()
    assert liberado_de(fluxo, pid) == 0


@pytest.mark.parametrize(
    "corpo",
    [
        ACEITE | {"reembolso_centavos": PARTE + 1},
        ACEITE | {"solucao": "reembolso_total", "reembolso_centavos": VALOR},
        ACEITE | {"solucao": "retrabalho", "reembolso_centavos": 0},
    ],
)
def test_aceite_diferente_da_proposta_nao_move_nada(fluxo, corpo):  # noqa: F811
    pid = respondida(fluxo)
    antes = foto_do_dinheiro(fluxo, pid)
    assert aceitar(fluxo, pid, corpo).status_code == 409
    assert foto_do_dinheiro(fluxo, pid) == antes and ver(fluxo, pid)["estado"] == "em_analise"


@pytest.mark.parametrize("solucao", ["retrabalho", "discordar"])
def test_sem_proposta_de_devolucao_e_409(fluxo, solucao):  # noqa: F811
    pid = respondida(fluxo, solucao, None)
    assert ver(fluxo, pid)["proposta"] is None
    assert aceitar(fluxo, pid).status_code == 409


def test_so_o_cliente_do_pedido_aceita(fluxo):  # noqa: F811
    pid = respondida(fluxo)
    antes = foto_do_dinheiro(fluxo, pid)
    assert aceitar(fluxo, pid, quem="t-prof").status_code == 403
    assert aceitar(fluxo, pid, quem="t-outro-cliente").status_code == 404
    assert aceitar(fluxo, pid, quem="t-mediador").status_code == 403
    assert foto_do_dinheiro(fluxo, pid) == antes


def test_acordo_antigo_continua_liberando_tudo(fluxo):  # noqa: F811
    pid = respondida(fluxo)
    assert fluxo.acao(pid, "encerrar_disputa_por_acordo", "t-cliente").status_code == 200
    assert ver(fluxo, pid)["acordo"] == {
        "solucao": "liberar_tudo",
        "reembolso_centavos": 0,
        "liberado_centavos": VALOR,
    }
    assert aceitar(fluxo, pid).status_code == 409 and estornado(fluxo, pid) == 0


def test_aceites_simultaneos_movem_uma_vez(fluxo):  # noqa: F811
    pid = respondida(fluxo)
    respostas = juntos(*[lambda: aceitar(fluxo, pid)] * 8)
    assert [r.status_code for r in respostas] == [200] * 8
    assert estornado(fluxo, pid) == PARTE
    assert fluxo.saldo(pid)["a_liberar_centavos"] == VALOR - PARTE


@pytest.mark.parametrize("rodada", range(4))
def test_aceite_junto_com_a_decisao_so_um_move_o_dinheiro(fluxo, rodada):  # noqa: F811
    pid = respondida(fluxo)
    url = f"/v1/pedidos/{pid}/disputa/decisao"
    pares = [
        lambda: aceitar(fluxo, pid),
        lambda: fluxo.chamar("POST", url, "t-mediador", DECISAO),
    ]
    if rodada % 2:
        pares.reverse()
    codigos = sorted(r.status_code for r in juntos(*pares))
    assert codigos == [200, 409]
    estado = ver(fluxo, pid)["estado"]
    assert estornado(fluxo, pid) == (PARTE if estado == "acordo" else VALOR)


def test_decisao_antes_do_aceite_vence(fluxo):  # noqa: F811
    pid = respondida(fluxo)
    url = f"/v1/pedidos/{pid}/disputa/decisao"
    assert fluxo.chamar("POST", url, "t-mediador", DECISAO).status_code == 200
    assert aceitar(fluxo, pid).status_code == 409 and estornado(fluxo, pid) == VALOR


def test_provedor_fora_deixa_a_devolucao_pendente(fluxo, monkeypatch):  # noqa: F811
    pid = respondida(fluxo)

    def fora(*_args, **_kwargs):
        raise RuntimeError("provedor fora")

    monkeypatch.setattr(fluxo.fake, "estornar", fora)
    assert aceitar(fluxo, pid).status_code == 200
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert (ordem.valor_centavos, ordem.estado) == (PARTE, "pendente")
