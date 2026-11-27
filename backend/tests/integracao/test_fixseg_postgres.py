"""TERMOS-BE-FIXSEG no Postgres local: conta da equipe protegida nas rotas de risco (M5) e
conversas só das partes do vínculo (M6)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from trato.api.denuncias import marcador

from .test_ausencia_cliente_postgres import _post
from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_medidas_postgres import limpar, status
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)


def _seguranca(c) -> None:
    if "seg" in c.ids:
        return
    c.ids["seg"] = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (c.ids["seg"],))
        con.execute("insert into public.usuarios (id, nome) values (%s, 'seg')", (c.ids["seg"],))
        con.execute(
            "insert into public.equipe (usuario_id, papel) values (%s, 'seguranca')",
            (c.ids["seg"],),
        )


def test_risco_contra_a_equipe_so_com_administrador(pg, equipe):  # noqa: F811
    limpar(pg)
    _seguranca(pg)
    corpo = {"usuario_id": pg.ids["med_b"], "motivo": "Análise de segurança da conta."}
    try:
        for rota in ("bloqueio-preventivo", "desbloqueio"):
            r = _post(pg, "seg", f"/v1/admin/risco/{rota}", corpo)
            assert r.status_code == 403 and "equipe" in r.text, (rota, r.text)
        assert status(pg, "med_b") == "ativo"
        comum = corpo | {"usuario_id": pg.ids["profissional"]}
        r = _post(pg, "seg", "/v1/admin/risco/bloqueio-preventivo", comum)
        assert r.status_code == 200, r.text
        r = _post(pg, "adm_a", "/v1/admin/risco/bloqueio-preventivo", corpo)
        assert r.status_code == 200, r.text
        assert status(pg, "med_b") == "bloqueado"
        r = _post(pg, "seg", "/v1/admin/risco/desbloqueio", corpo)
        assert r.status_code in (401, 403) and status(pg, "med_b") == "bloqueado"
        assert _post(pg, "adm_a", "/v1/admin/risco/desbloqueio", corpo).status_code == 200
        assert status(pg, "med_b") == "ativo"
    finally:
        limpar(pg)
        with pg.local.admin() as con:
            con.execute(
                "update public.usuarios set status = 'ativo' where id = %s", (pg.ids["med_b"],)
            )


def test_conversas_so_das_partes_do_vinculo(pg, equipe):  # noqa: F811
    pid, _ = agendado(pg)
    contexto = pg.pagto[1]
    contratado, outro = pg.ids["profissional"], pg.ids["profissional2"]
    cliente = pg.ids["cliente"]
    for prof in (contratado, outro):
        conversa = contexto.conversas.abrir(pid, prof)
        contexto.conversas.enviar(conversa, cliente, f"mensagem para {prof[:8]}")
    url = f"/v1/admin/pedidos/{pid}/conversas/leitura"

    def ler(quem, base, **extra):
        corpo = {"motivo": "Pedido de análise do caso.", "base": base} | extra
        return _post(pg, quem, url, corpo)

    def profissionais(r) -> set[str]:
        assert r.status_code == 200, r.text
        return {c["profissional_id"].replace("-", "") for c in r.json()["conversas"]}

    so_contratado = {contratado.replace("-", "")}
    assert ler("med_a", "ordem_judicial", referencia="0001234-55").status_code == 403
    assert profissionais(ler("adm_a", "ordem_judicial", referencia="0001234-55")) == so_contratado
    contexto.denuncias.registrar(
        cliente,
        pid,
        "denuncia_chat",
        "media",
        f"Denúncia de chat (ofensa){marcador(outro, cliente)} texto",
        datetime.now(UTC),
    )
    assert profissionais(ler("med_a", "denuncia")) == so_contratado | {outro.replace("-", "")}
    assert ler("med_a", "incidente").status_code == 409
    ((total,),) = linhas(
        pg,
        "select count(*) from public.auditoria where acao = 'dado_pessoal.conversa_lida' "
        "and entidade_id = %s",
        (pid,),
    )
    assert total == 2
