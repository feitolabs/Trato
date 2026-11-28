"""BE-148-GUARDAS no Postgres local: abrir, encerrar e consultar a retenção pelo painel."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import threading
import uuid

import pytest

from trato.persistencia.pedido_guardas import PedidoGuardasPostgres

from .test_ausencia_reembolso_postgres import pago_e_agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)

pytestmark = pytest.mark.integracao

MOTIVO = "Processo judicial em andamento sobre este pedido."


@pytest.fixture
def amb(pg, equipe, monkeypatch):
    def limpar():
        with pg.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute("delete from public.pedido_guardas")

    limpar()
    monkeypatch.setattr(pg.pagto[1], "pedido_guardas", PedidoGuardasPostgres(pg.banco))
    for papel in ("dpo", "juridico", "seguranca", "financeiro"):
        if papel in pg.ids:
            continue
        pg.ids[papel] = str(uuid.uuid4())
        with pg.local.admin() as con:
            con.execute("insert into auth.users (id) values (%s)", (pg.ids[papel],))
            con.execute(
                "insert into public.usuarios (id, nome) values (%s, %s)", (pg.ids[papel], papel)
            )
            con.execute(
                "insert into public.equipe (usuario_id, papel) values (%s, %s)",
                (pg.ids[papel], papel),
            )
    yield pg
    limpar()


def url(pid, resto="guardas"):
    return f"/v1/admin/pedidos/{pid}/{resto}"


def post(c, quem, caminho, corpo):
    return c.pagto[0].post(caminho, json=corpo, headers=c.token(quem))


def get(c, quem, caminho):
    return c.pagto[0].get(caminho, headers=c.token(quem))


def auditorias(c, acao) -> int:
    return linhas(c, "select count(*) from public.auditoria where acao = %s", (acao,))[0][0]


def registros(c, pid):
    return linhas(
        c,
        "select (select count(*) from public.pedidos where id = %s), "
        "(select count(*) from public.contratos where pedido_id = %s)",
        (pid, pid),
    )


@pytest.mark.parametrize("quem", ["dpo", "juridico", "seguranca", "adm_a"])
def test_abrir_repetir_consultar_e_encerrar(amb, quem):
    c = amb
    pid, _, _ = pago_e_agendado(c)
    antes = registros(c, pid)
    abertas, encerradas = (
        auditorias(c, f"retencao.guarda_pedido_{x}") for x in ("aberta", "encerrada")
    )
    corpo = {"tipo": "processo", "motivo": MOTIVO}
    r = post(c, quem, url(pid), corpo)
    assert r.status_code == 201, r.text
    guarda = r.json()
    assert guarda["aberta"] is True and guarda["encerrada_em"] is None
    r = post(c, quem, url(pid), corpo)
    assert r.status_code == 200 and r.json()["id"] == guarda["id"], r.text
    assert [g["id"] for g in get(c, quem, url(pid)).json()] == [guarda["id"]]
    situacao = get(c, quem, url(pid, "retencao")).json()
    assert situacao["situacao"] == "sem_marco" and "guarda_pedido" in situacao["bloqueios"]
    assert situacao["prazo_anos"] >= 5

    fechar = url(pid, f"guardas/{guarda['id']}/encerrar")
    r = post(c, quem, fechar, {"motivo": "Processo arquivado definitivamente."})
    assert r.status_code == 200 and r.json()["aberta"] is False, r.text
    de_novo = post(c, quem, fechar, {"motivo": "Processo arquivado definitivamente."})
    assert de_novo.status_code == 200 and de_novo.json() == r.json()
    assert "guarda_pedido" not in get(c, quem, url(pid, "retencao")).json()["bloqueios"]
    assert auditorias(c, "retencao.guarda_pedido_aberta") == abertas + 1
    assert auditorias(c, "retencao.guarda_pedido_encerrada") == encerradas + 1
    assert registros(c, pid) == antes  # nada apagado


def test_duas_aberturas_ao_mesmo_tempo_criam_uma_so(amb):
    c = amb
    pid, _, _ = pago_e_agendado(c)
    codigos, barreira = [], threading.Barrier(4)

    def abrir():
        barreira.wait()
        r = post(c, "dpo", url(pid), {"tipo": "investigacao", "motivo": MOTIVO})
        codigos.append(r.status_code)

    fios = [threading.Thread(target=abrir) for _ in range(4)]
    [f.start() for f in fios]
    [f.join(60) for f in fios]
    assert sorted(codigos) == [200, 200, 200, 201]
    assert len(get(c, "dpo", url(pid)).json()) == 1


def test_sem_permissao_entrada_invalida_e_pedido_errado(amb):
    c = amb
    pid, _, _ = pago_e_agendado(c)
    outro, _, _ = pago_e_agendado(c)
    corpo = {"tipo": "processo", "motivo": MOTIVO}
    for quem in ("med_a", "financeiro", "cliente"):
        assert post(c, quem, url(pid), corpo).status_code in (401, 403)
        assert get(c, quem, url(pid)).status_code in (401, 403)
        assert get(c, quem, url(pid, "retencao")).status_code in (401, 403)
    for ruim in ({"tipo": "processo", "motivo": "   curto  "}, {"tipo": "x", "motivo": MOTIVO}, {}):
        assert post(c, "dpo", url(pid), ruim).status_code == 422
    assert get(c, "dpo", url(pid)).json() == []
    assert post(c, "dpo", url(str(uuid.uuid4())), corpo).status_code == 404
    guarda = post(c, "dpo", url(pid), corpo).json()
    fechar = {"motivo": "Encerramento conferido pela equipe."}
    r = post(c, "dpo", url(outro, f"guardas/{guarda['id']}/encerrar"), fechar)
    assert r.status_code == 404, r.text
    assert get(c, "dpo", url(pid)).json()[0]["aberta"] is True
