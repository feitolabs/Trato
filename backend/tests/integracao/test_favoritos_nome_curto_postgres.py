"""BUG-C03 no Postgres: os favoritos do cliente saem com o nome curto do profissional."""

from __future__ import annotations

import uuid

import pytest

from .test_rotas_app_postgres import get

pytestmark = pytest.mark.integracao


def test_favoritos_no_postgres_nunca_trazem_o_sobrenome_completo(cenario):
    c = cenario
    pro = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (pro,))
        con.execute(
            "insert into public.usuarios (id, nome) values (%s, %s)",
            (pro, "Tester SuperQA Profissional"),
        )
        con.execute("insert into public.perfis_profissional (usuario_id) values (%s)", (pro,))
        con.execute(
            "update public.perfis_profissional set status = 'aprovado', "
            "nivel_verificacao = 'verificado' where usuario_id = %s",
            (pro,),
        )
    r = c.cliente.put(f"/v1/me/favoritos/{pro}", headers=c.token("cliente2"))
    assert r.status_code == 204, r.text
    resposta = get(c, "/v1/me/favoritos", "cliente2")
    assert resposta.status_code == 200
    (favorito,) = [f for f in resposta.json() if f["profissional_id"] == pro]
    assert favorito["nome"] == "Tester P."
    assert "SuperQA" not in resposta.text and "Profissional" not in resposta.text
