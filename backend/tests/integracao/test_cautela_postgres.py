"""BE-96-FIM no Postgres local: as consultas de cautela (9.6) e o pedido cancelado por pessoa
diferente visto pelo cliente bloqueado."""

from __future__ import annotations

from datetime import timedelta

from trato.api.cautela import contato_bloqueado, registros_preservados
from trato.persistencia.incidentes import Incidente

from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_incidentes_postgres import publicado  # noqa: F401 - fixtures
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401
from .test_pessoa_diferente_postgres import relatar

MUDAR = "update public.usuarios set status = %s where id = %s"


def test_medidas_valem_ate_encerrar_e_bloqueado_ve_o_cancelado(publicado):  # noqa: F811
    c = publicado
    contexto = c.pagto[1]
    cliente, profissional = c.ids["cliente"], c.ids["profissional"]
    pid, _ = agendado(c)
    assert relatar(c, pid).json()["cancelado"] is True
    incidentes = contexto.incidentes
    (item,), _ = incidentes.listar(None, pid, 10, 0)
    assert isinstance(item, Incidente)
    assert not contato_bloqueado(contexto, cliente, profissional)
    operador = c.ids["equipe1"]
    for tipo in ("bloquear_contato", "preservar_registros"):
        agora = contexto.agora()
        assert incidentes.registrar_medida(item.id, tipo, "Cautela.", operador, agora) == "ok"
    assert contato_bloqueado(contexto, profissional, cliente)
    assert registros_preservados(contexto, cliente)
    assert not registros_preservados(contexto, c.ids["cliente2"])
    assert isinstance(incidentes.equipe_de_seguranca(), list)
    with c.local.admin() as con:
        con.execute(MUDAR, ("bloqueado", cliente))
    try:
        visto = c.pagto[0].get(f"/v1/pedidos/{pid}", headers=c.token("cliente"))
        assert visto.status_code == 200, visto.text
        lista = c.pagto[0].get("/v1/pedidos", headers=c.token("cliente"))
        assert pid in [p["id"] for p in lista.json()], lista.text
    finally:
        with c.local.admin() as con:
            con.execute(MUDAR, ("ativo", cliente))
    fim = contexto.agora() + timedelta(seconds=1)
    assert incidentes.encerrar(item.id, "Apurado e resolvido.", operador, fim) == "ok"
    assert not contato_bloqueado(contexto, cliente, profissional)
    assert not registros_preservados(contexto, cliente)
