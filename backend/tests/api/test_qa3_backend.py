# ruff: noqa
"""QA3 backend (em memoria): fuzz de payload em todas as rotas nao-admin, IDOR de escrita,
corrida em acoes do pedido, estados fora de ordem. Marcas: xfail 'bug conhecido: QA3-n'."""

from __future__ import annotations

import re
import threading

import pytest
from conftest import AGORA, cab

from trato.pedidos.estados import Acao
from trato.pedidos.estados import Estado as E

CORPOS = [
    None, {}, [], "x", 123, {"a": 1},
    {"valor_centavos": -1, "descricao": "<script>alert(1)</script>"},
    {"nota_geral": "; DROP TABLE x;--"},
    {"descricao": "\u202e" * 3000, "titulo": "😀" * 3000},
    {"valor_centavos": 10**30, "parcelas": -3, "meio": None},
]
SUBST = {"pedido_id": "ped-1", "contrato_id": "ped-1", "orcamento_id": "orc-1", "acao": "aceitar_orcamento"}


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
    publicas = ("/v1/cadastro", "/v1/catalogo", "/v1/cep", "/v1/config/publica", "/v1/publico", "/v1/legal", "/v1/saude", "/legal", "/saude")
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


@pytest.mark.parametrize("estado,acao", [
    (E.ORCAMENTO_ACEITO, "informar_pagamento"),
    (E.EM_CONFIRMACAO, "confirmar_conclusao"),
])
@pytest.mark.xfail(strict=False, reason="bug conhecido: QA3-2 corrida: em ~1 de 40 rodadas de 8 threads a mesma acao (informar_pagamento) retorna 200 mais de uma vez no repositorio em memoria (check-then-save sem trava); confirmar o guard no Postgres")
def test_corrida_de_8_threads_na_mesma_acao_so_uma_vence(estado, acao):
    import conftest

    for _ in range(40):
        amb = conftest.amb.__wrapped__()
        amb.semear_pedido(estado)
        res, barreira = [], threading.Barrier(8)

        def f():
            barreira.wait()
            res.append(amb.cliente.post(f"/v1/pedidos/ped-1/acoes/{acao}", headers=cab("t-cliente")).status_code)

        ts = [threading.Thread(target=f) for _ in range(8)]
        [t.start() for t in ts]
        [t.join() for t in ts]
        assert res.count(200) == 1, sorted(res)

@pytest.mark.parametrize("estado", [E.CANCELADO, E.CONCLUIDO, E.PAGO_E_RETIDO, E.EM_DISPUTA])
def test_informar_pagamento_fora_de_ordem_da_409(amb, estado):
    amb.semear_pedido(estado)
    r = amb.cliente.post("/v1/pedidos/ped-1/acoes/informar_pagamento", headers=cab("t-cliente"))
    assert r.status_code == 409
    assert amb.contexto.pedidos.obter("ped-1").estado is estado


def test_pedido_cancelado_nao_aceita_acao_alguma_do_cliente(amb):
    amb.semear_pedido(E.CANCELADO)
    for ac in Acao:
        r = amb.cliente.post(f"/v1/pedidos/ped-1/acoes/{ac.value}", headers=cab("t-cliente"), json={})
        assert r.status_code != 200, ac
    assert amb.contexto.pedidos.obter("ped-1").estado is E.CANCELADO


@pytest.mark.xfail(strict=True, reason="bug conhecido: QA3-1 acao decidir_disputa chamada por cliente devolve 501 (deveria ser 403/404; so o mediador decide)")
def test_cliente_nao_dispara_decidir_disputa_com_501(amb):
    amb.semear_pedido(E.EM_DISPUTA)
    r = amb.cliente.post("/v1/pedidos/ped-1/acoes/decidir_disputa", headers=cab("t-cliente"), json={})
    assert r.status_code in (403, 404, 409, 422)


def test_id_do_pedido_estranho_nao_gera_500(amb):
    for pid in ("%00", "%27%20OR%201%3D1", "..%2f..%2f", "%F0%9F%92%A9", "a" * 4000, "%E2%80%AE"):
        for u in (f"/v1/pedidos/{pid}", f"/v1/pedidos/{pid}/extrato", f"/v1/contratos/{pid}/pagamento"):
            r = amb.cliente.get(u, headers=cab("t-cliente"))
            assert r.status_code in (400, 404, 414, 422), f"{u[:40]}: {r.status_code}"


def test_resposta_de_erro_nao_vaza_traceback_nem_caminho(amb):
    amb.semear_pedido(E.CONCLUIDO)
    r = amb.cliente.post("/v1/pedidos", json={"categoria_id": {"x": 1}, "cidade_id": [1]}, headers=cab("t-cliente"))
    assert r.status_code == 422
    for proibido in ("Traceback", "C:\\", "/src/", "site-packages", "sqlalchemy", "psycopg"):
        assert proibido not in r.text

