"""BE-TERMOS-96-52 (9.6) no Postgres local: o telefone já enviado some da conversa e da lista
com o contato bloqueado e volta quando o incidente encerra."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

from trato.persistencia.incidentes import Incidente

from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_incidentes_postgres import publicado  # noqa: F401 - fixtures
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

TELEFONE = "98765-4321"


def test_contato_ja_enviado_some_e_volta(publicado):
    c = publicado
    http, contexto, _ = c.pagto
    pid, _ = agendado(c)
    conversa = contexto.conversas.abrir(pid, c.ids["profissional"])
    contexto.conversas.enviar(conversa, c.ids["cliente"], f"Meu numero e (11) {TELEFONE}")

    def visto() -> tuple[str, str]:
        mensagens = " ".join(m.texto for m in contexto.conversas.listar(conversa))
        r = http.get("/v1/conversas", headers=c.token("profissional"))
        assert r.status_code == 200, r.text
        previa = [x["ultima_mensagem"] or "" for x in r.json() if x["pedido_id"] == pid]
        return mensagens, " ".join(previa)

    assert all(TELEFONE in texto for texto in visto())
    agora = contexto.agora()
    item, _ = contexto.incidentes.abrir(
        Incidente(
            tipo="agressao_ameaca_assedio",
            descricao="Relato para o bloqueio de contato.",
            canal="app",
            contato="app",
            pedido_id=pid,
            aberto_em=agora,
            cautela_ate=agora + timedelta(hours=24),
        )
    )
    operador = c.ids["equipe1"]
    assert (
        contexto.incidentes.registrar_medida(
            item.id, "bloquear_contato", "Cautela.", operador, contexto.agora()
        )
        == "ok"
    )
    assert not any(TELEFONE in texto for texto in visto())
    fim = contexto.agora() + timedelta(seconds=1)
    assert contexto.incidentes.encerrar(item.id, "Apurado e resolvido.", operador, fim) == "ok"
    assert all(TELEFONE in texto for texto in visto())
