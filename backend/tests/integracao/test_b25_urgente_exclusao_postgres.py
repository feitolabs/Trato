"""B25: no caminho Postgres, `urgente` (lista, detalhe, /dados, pedidos abertos) e
`exclusao_agendada_em` (GET /v1/me) vêm do que foi gravado. Banco local descartável."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from trato.api import criar_app

from .test_fluxo_postgres import corpo_pedido

pytestmark = pytest.mark.integracao


def _abrir(c, **extra) -> dict:
    r = c.cliente.post("/v1/pedidos", json=corpo_pedido(c, **extra), headers=c.token("cliente"))
    assert r.status_code == 201, r.text
    return r.json()


def test_urgente_gravado_e_lido_em_todas_as_rotas_do_cliente(cenario):
    c = cenario
    urgente = _abrir(c, urgente=True, titulo="Urgente B25")
    normal = _abrir(c, urgente=False, titulo="Normal B25")
    assert urgente["urgente"] is True and normal["urgente"] is False

    with c.local.admin() as con:  # a coluna, não um default
        gravado = {
            str(i): u
            for i, u in con.execute(
                "select id, urgente from public.pedidos where id in (%s, %s)",
                (urgente["id"], normal["id"]),
            ).fetchall()
        }
    assert gravado[urgente["id"]] is True and gravado[normal["id"]] is False

    lista = c.cliente.get("/v1/pedidos?como=cliente", headers=c.token("cliente")).json()
    por_id = {p["id"]: p for p in lista}
    assert por_id[urgente["id"]]["urgente"] is True
    assert por_id[normal["id"]]["urgente"] is False
    for pedido in (urgente, normal):
        det = c.cliente.get(f"/v1/pedidos/{pedido['id']}", headers=c.token("cliente")).json()
        assert det["urgente"] is pedido["urgente"]
        dados = c.cliente.get(f"/v1/pedidos/{pedido['id']}/dados", headers=c.token("cliente"))
        assert dados.json()["urgente"] is pedido["urgente"]


def test_urgente_aparece_nos_pedidos_abertos_do_profissional(cenario):
    c = cenario
    with c.local.admin() as con:
        con.execute(
            "insert into public.profissional_categorias (profissional_id, categoria_id) "
            "values (%s, %s) on conflict do nothing",
            (c.ids["profissional"], c.categoria_id),
        )
        if not con.execute(
            "select 1 from public.profissional_regioes where profissional_id = %s",
            (c.ids["profissional"],),
        ).fetchone():
            con.execute(
                "insert into public.profissional_regioes (profissional_id, cidade_id) "
                "values (%s, %s)",
                (c.ids["profissional"], c.cidade_id),
            )
    pid = _abrir(c, urgente=True, titulo="Urgente aberto B25")["id"]
    abertos = c.cliente.get("/v1/profissional/pedidos-abertos", headers=c.token("profissional"))
    assert abertos.status_code == 200, abertos.text
    achado = {p["id"]: p for p in abertos.json()}[pid]
    assert achado["urgente"] is True
    det = c.cliente.get(f"/v1/profissional/pedidos-abertos/{pid}", headers=c.token("profissional"))
    assert det.status_code == 200, det.text
    assert det.json()["urgente"] is True


def test_me_devolve_exclusao_agendada_em_no_postgres(cenario):
    """Mesmo app de produção (`seguranca.registrar_rotas` liga o LGPD) sobre o contexto Postgres."""
    from trato.seguranca import registrar_rotas

    c = cenario
    app = registrar_rotas(criar_app(c.contexto))
    with TestClient(app) as http:
        h = c.token("cliente2")
        assert http.get("/v1/me", headers=h).json()["exclusao_agendada_em"] is None
        pedir = http.post("/v1/me/exclusao", headers=h, json={})
        assert pedir.status_code == 200, pedir.text
        # só pedido (aguardando confirmação) ainda não é "agendada"
        assert http.get("/v1/me", headers=h).json()["exclusao_agendada_em"] is None
        conf = http.post(
            "/v1/me/exclusao",
            headers=h,
            json={"token_confirmacao": pedir.json()["token_confirmacao"]},
        )
        assert conf.status_code == 200, conf.text
        agendada = http.get("/v1/me", headers=h).json()["exclusao_agendada_em"]
        assert agendada is not None
        assert http.delete("/v1/me/exclusao", headers=h).status_code == 204
        assert http.get("/v1/me", headers=h).json()["exclusao_agendada_em"] is None
