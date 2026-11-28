"""TERMOS-BE-86 sem as tabelas (memoria): painel responde 503 e o resto segue; permissoes."""

from __future__ import annotations

from dataclasses import replace

import pytest
from conftest import AGORA, PROFISSIONAL, cab
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401 - `fluxo` é fixture

from trato.persistencia.compensacoes import Divida, Registro

URL = "/v1/admin/compensacoes"
CORPO = {"pedido_id": "ped-1", "valor_centavos": 100, "motivo": "Reembolso decidido depois."}


@pytest.mark.parametrize("quem", ["t-financeiro", "t-n1", "t-cliente", "t-prof"])
def test_sem_permissao_nao_registra_nem_cancela(amb, quem):
    assert amb.cliente.post(URL, json=CORPO, headers=cab(quem)).status_code == 403
    assert amb.cliente.get(URL, headers=cab(quem)).status_code == 403
    r = amb.cliente.post(f"{URL}/x/cancelar", json={"motivo": "m" * 12}, headers=cab(quem))
    assert r.status_code == 403


def test_sem_as_tabelas_503_com_codigo_e_lista_do_profissional_vazia(amb):
    for r in (
        amb.cliente.post(URL, json=CORPO, headers=cab("t-mediador")),
        amb.cliente.get(URL, headers=cab("t-mediador")),
    ):
        assert r.status_code == 503 and r.json()["codigo"] == "indisponivel", r.text
    assert amb.cliente.get("/v1/me/compensacoes", headers=cab("t-prof")).json() == []
    assert amb.cliente.get("/v1/me/compensacoes", headers=cab("t-cliente")).status_code == 403


@pytest.mark.parametrize("ruim", [{"valor_centavos": 0}, {"valor_centavos": 1.5}, {"motivo": "x"}])
def test_valor_e_motivo_sao_conferidos(amb, ruim):
    r = amb.cliente.post(URL, json=CORPO | ruim, headers=cab("t-mediador"))
    assert r.status_code == 422


class DividasDeMemoria:
    """Imita o banco no que importa aqui: uma dívida por origem e teto que ignora canceladas.
    As regras de verdade estão no SQL e são testadas no Postgres local."""

    def __init__(self) -> None:
        self.itens: list[Divida] = []

    def disponivel(self) -> bool:
        return True

    def registrar_disputa(self, pedido_id, contestacao_id, valor, motivo, operador_id):
        origem = contestacao_id or "disputa"
        for d in self.itens:
            if d.contrato_id == origem:
                return Registro("ja_registrada", d.id)
        nova = Divida(
            f"div-{len(self.itens)}", origem, pedido_id, PROFISSIONAL.id,
            "disputa_contestacao", valor, 0, motivo, "aberta", AGORA, avisado_em=AGORA,
        )  # fmt: skip
        self.itens.append(nova)
        return Registro("ok", nova.id)

    def cancelar(self, divida_id):
        self.itens = [
            replace(d, status="cancelada") if d.id == divida_id else d for d in self.itens
        ]

    def obter(self, divida_id):
        return next((d for d in self.itens if d.id == divida_id), None)

    def listar(self, profissional_id=None, pedido_id=None, status=None, limite=50, desloc=0):
        achadas = [d for d in self.itens if status in (None, d.status)]
        return achadas, len(achadas)


def test_valor_reduzido_depois_de_cancelar_nao_estorna_de_novo(fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)["id"]
    dividas = DividasDeMemoria()
    fluxo.ctx.compensacoes = dividas
    fluxo.http.app.state.servico_pagamento = fluxo.servico

    def registrar(valor, contestacao):
        corpo = CORPO | {"pedido_id": pid, "valor_centavos": valor, "contestacao_id": contestacao}
        return fluxo.chamar("POST", URL, "t-mediador", corpo)

    primeira = registrar(4_000, "c1")
    assert primeira.status_code == 200, primeira.text
    dividas.cancelar(primeira.json()["compensacao"]["id"])
    r = registrar(1_000, "c2")
    assert r.status_code == 409 and r.json()["codigo"] == "estorno_ja_ordenado", r.text
    assert registrar(4_000, "c1").json()["resultado"] == "ja_registrada"
    assert [e.valor_centavos for e in fluxo.fake.estornos_da_cobranca(cobranca)] == [4_000]
    assert [o.valor_centavos for o in fluxo.servico.ordens.do_pedido(pid)] == [4_000]
