# ruff: noqa
"""QA3 backend (em memoria): fuzz de payload em todas as rotas nao-admin, IDOR de escrita,
corrida em acoes do pedido, estados fora de ordem. Marcas: xfail 'bug conhecido: QA3-n'."""

from __future__ import annotations

import re
import threading

import pytest
from conftest import AGORA, cab
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.pedidos.estados import Acao
from trato.pedidos.estados import Estado as E

CORPOS = [
    None,
    {},
    [],
    "x",
    123,
    {"a": 1},
    {"valor_centavos": -1, "descricao": "<script>alert(1)</script>"},
    {"nota_geral": "; DROP TABLE x;--"},
    {"descricao": "\u202e" * 3000, "titulo": "😀" * 3000},
    {"valor_centavos": 10**30, "parcelas": -3, "meio": None},
]
SUBST = {
    "pedido_id": "ped-1",
    "contrato_id": "ped-1",
    "orcamento_id": "orc-1",
    "acao": "aceitar_orcamento",
}


def _rotas(amb):
    saida = []
    for p, m in sorted(amb.cliente.app.openapi()["paths"].items()):
        if "/admin" in p or "webhook" in p:
            continue
        url = p
        for k, v in SUBST.items():
            url = url.replace("{" + k + "}", v)
        url = re.sub(r"\{[^}]+\}", "x", url)
        for metodo in m:
            if metodo in ("post", "put", "patch", "delete"):
                saida.append((metodo.upper(), url))
    return saida


def test_fuzz_nenhuma_rota_nao_admin_devolve_500_nem_levanta(amb):
    amb.semear_pedido(E.CONCLUIDO)
    amb.semear_dinheiro()
    quebras = []
    rotas = _rotas(amb)
    assert len(rotas) > 40
    for metodo, url in rotas:
        for tok in ("t-cliente", "t-prof"):
            for corpo in CORPOS:
                try:
                    kw = {"json": corpo} if corpo is not None else {}
                    r = amb.cliente.request(metodo, url, headers=cab(tok), **kw)
                except Exception as e:  # noqa: BLE001
                    quebras.append((metodo, url, tok, "EXC", type(e).__name__))
                    continue
                if r.status_code >= 500 and r.status_code != 503:
                    quebras.append((metodo, url, tok, r.status_code))
    assert not quebras, quebras[:10]


def test_fuzz_rotas_sem_token_dao_401_nunca_dado(amb):
    amb.semear_pedido(E.CONCLUIDO)
    publicas = (
        "/v1/cadastro",
        "/v1/catalogo",
        "/v1/cep",
        "/v1/config/publica",
        "/v1/publico",
        "/v1/legal",
        "/v1/saude",
        "/legal",
        "/saude",
    )
    for metodo, url in _rotas(amb):
        if url.startswith(publicas):
            continue
        r = amb.cliente.request(metodo, url, json={})
        assert r.status_code in (401, 403, 404, 405, 422), f"{metodo} {url}: {r.status_code}"


ESCRITAS_ALHEIAS = [
    ("POST", "/v1/pedidos/ped-1/acoes/aceitar_orcamento", None),
    ("POST", "/v1/pedidos/ped-1/acoes/confirmar_conclusao", None),
    ("POST", "/v1/pedidos/ped-1/avaliacao", {"nota_geral": 5}),
    ("POST", "/v1/pedidos/ped-1/mensagens", {"texto": "oi"}),
    ("POST", "/v1/contratos/ped-1/cupom", {"codigo": "X"}),
    ("POST", "/v1/contratos/ped-1/avaliacao", {"nota_geral": 5}),
    ("PATCH", "/v1/pedidos/ped-1", {"descricao": "hack"}),
    ("POST", "/v1/notificacoes/inexistente/lida", None),
    ("POST", "/v1/conversas/inexistente/lida", None),
    ("DELETE", "/v1/me/enderecos/inexistente", None),
]


@pytest.mark.parametrize("metodo,url,corpo", ESCRITAS_ALHEIAS)
@pytest.mark.parametrize("token", ["t-outro-cliente", "t-outro-prof"])
def test_idor_escrita_em_pedido_alheio_da_404(amb, metodo, url, corpo, token):
    amb.semear_pedido(E.EM_CONFIRMACAO)
    antes = amb.contexto.pedidos.obter("ped-1")
    kw = {"json": corpo} if corpo is not None else {}
    r = amb.cliente.request(metodo, url, headers=cab(token), **kw)
    assert r.status_code == 404, f"{r.status_code} {r.text[:100]}"
    assert amb.contexto.pedidos.obter("ped-1") == antes


@pytest.mark.parametrize(
    "estado,acao",
    [
        (E.ORCAMENTO_ACEITO, "informar_pagamento"),
        (E.EM_CONFIRMACAO, "confirmar_conclusao"),
    ],
)
def test_corrida_de_8_threads_na_mesma_acao_so_uma_vence(estado, acao):
    import conftest

    for _ in range(100):
        amb = conftest.amb.__wrapped__()
        amb.semear_pedido(estado)
        res, barreira = [], threading.Barrier(8)

        def f():
            barreira.wait()
            res.append(
                amb.cliente.post(
                    f"/v1/pedidos/ped-1/acoes/{acao}", headers=cab("t-cliente")
                ).status_code
            )

        ts = [threading.Thread(target=f) for _ in range(8)]
        [t.start() for t in ts]
        [t.join() for t in ts]
        assert res.count(200) == 1, sorted(res)
        assert res.count(409) == 7, sorted(res)  # quem perde a corrida leva 409, nunca 200 nem 500


@pytest.mark.parametrize("estado", [E.CANCELADO, E.CONCLUIDO, E.PAGO_E_RETIDO, E.EM_DISPUTA])
def test_informar_pagamento_fora_de_ordem_da_409(amb, estado):
    amb.semear_pedido(estado)
    r = amb.cliente.post("/v1/pedidos/ped-1/acoes/informar_pagamento", headers=cab("t-cliente"))
    assert r.status_code == 409
    assert amb.contexto.pedidos.obter("ped-1").estado is estado


def test_pedido_cancelado_nao_aceita_acao_alguma_do_cliente(amb):
    amb.semear_pedido(E.CANCELADO)
    for ac in Acao:
        r = amb.cliente.post(
            f"/v1/pedidos/ped-1/acoes/{ac.value}", headers=cab("t-cliente"), json={}
        )
        assert r.status_code != 200, ac
    assert amb.contexto.pedidos.obter("ped-1").estado is E.CANCELADO


def test_cliente_nao_dispara_decidir_disputa_com_501(amb):
    amb.semear_pedido(E.EM_DISPUTA)
    for token in ("t-cliente", "t-prof"):  # só o mediador decide: nunca 501 para as partes
        r = amb.cliente.post("/v1/pedidos/ped-1/acoes/decidir_disputa", headers=cab(token), json={})
        assert r.status_code == 403, (token, r.status_code)


def test_id_do_pedido_estranho_nao_gera_500(amb):
    for pid in ("%00", "%27%20OR%201%3D1", "..%2f..%2f", "%F0%9F%92%A9", "a" * 4000, "%E2%80%AE"):
        for u in (
            f"/v1/pedidos/{pid}",
            f"/v1/pedidos/{pid}/extrato",
            f"/v1/contratos/{pid}/pagamento",
        ):
            r = amb.cliente.get(u, headers=cab("t-cliente"))
            assert r.status_code in (400, 404, 414, 422), f"{u[:40]}: {r.status_code}"


def test_resposta_de_erro_nao_vaza_traceback_nem_caminho(amb):
    amb.semear_pedido(E.CONCLUIDO)
    r = amb.cliente.post(
        "/v1/pedidos", json={"categoria_id": {"x": 1}, "cidade_id": [1]}, headers=cab("t-cliente")
    )
    assert r.status_code == 422
    for proibido in ("Traceback", "C:\\", "/src/", "site-packages", "sqlalchemy", "psycopg"):
        assert proibido not in r.text


CORPO_RECUSA = {"motivo": "Não atendo essa região"}


def test_recusar_pedido_de_outro_cliente_da_404_e_papel_errado_do_dono_da_403(amb):
    amb.semear_pedido(E.ABERTO)
    url = "/v1/pedidos/ped-1/recusar"
    estranho = amb.cliente.post(url, headers=cab("t-outro-cliente"), json=CORPO_RECUSA)
    inexistente = amb.cliente.post(
        "/v1/pedidos/nao-existe/recusar", headers=cab("t-outro-cliente"), json=CORPO_RECUSA
    )
    assert estranho.status_code == 404 and inexistente.status_code == 404
    assert estranho.json() == inexistente.json() == {"detail": "Pedido não encontrado."}
    # O dono do pedido é cliente: papel errado continua 403.
    assert amb.cliente.post(url, headers=cab("t-cliente"), json=CORPO_RECUSA).status_code == 403


def test_pagamento_traz_desconto_do_cupom_separado_do_das_moedas(fluxo: Fluxo):
    import test_moedas_desconto as md

    fluxo.ctx.extras["cupons"] = {
        "TRATO10": {
            "codigo": "TRATO10",
            "tipo": "percentual",
            "valor": 10,
            "valor_minimo_centavos": 0,
            "limite_usos": 5,
            "limite_por_usuario": 1,
            "usos_atuais": 0,
            "ativo": True,
        }
    }
    md._ligar(fluxo, 5_000)
    pid = fluxo.aceitar()
    base = fluxo.chamar("GET", f"/v1/pedidos/{pid}/pagamento", "t-cliente").json()
    assert base["desconto_cupom_centavos"] == 0 and base["desconto_centavos"] == 0

    so_cupom = fluxo.chamar("GET", f"/v1/pedidos/{pid}/pagamento?cupom=trato10", "t-cliente").json()
    assert so_cupom["desconto_cupom_centavos"] == 10_000 == so_cupom["desconto_centavos"]
    assert so_cupom["moedas_desconto_centavos"] == 0

    r = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?cupom=trato10&usar_moedas=true", "t-cliente"
    ).json()
    assert r["desconto_cupom_centavos"] == 10_000
    assert r["moedas_desconto_centavos"] > 0
    assert r["desconto_centavos"] == r["desconto_cupom_centavos"] + r["moedas_desconto_centavos"]
    assert r["total_a_pagar_centavos"] == r["valor_centavos"] - r["desconto_centavos"]
