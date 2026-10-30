"""M11: o primeiro login cria `public.usuarios` (idempotente) e o fluxo cadastro -> pedido funciona.

Postgres local descartável (pgserver); nunca toca no Supabase real.
"""

from __future__ import annotations

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta

import jwt
import pytest

from trato.persistencia.erros import Duplicado

from .test_fluxo_postgres import corpo_pedido

pytestmark = pytest.mark.integracao


def _novo_no_auth(c) -> str:
    """Quem acabou de se cadastrar no Supabase Auth: existe em auth.users, ainda sem linha própria."""
    uid = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (uid,))
    return uid


def _cabecalho(c, sub: str, **extra) -> dict[str, str]:
    carga = {
        "sub": sub,
        "aud": "authenticated",
        "exp": datetime.now(UTC) + timedelta(hours=1),
        **extra,
    }
    return {"Authorization": f"Bearer {jwt.encode(carga, c.segredo_jwt, 'HS256')}"}


def _linhas(c, uid: str) -> list[tuple]:
    with c.local.admin() as con:
        return con.execute(
            "select nome, status from public.usuarios where id = %s", (uid,)
        ).fetchall()


def test_cadastro_ate_o_pedido_cria_a_linha_no_primeiro_login(cenario):
    c = cenario
    uid = _novo_no_auth(c)
    assert _linhas(c, uid) == []
    # O cliente controla user_metadata: nome entra, "papel" e "role" NÃO valem nada.
    h = _cabecalho(
        c,
        uid,
        user_metadata={"full_name": "  Maria   Nova ", "papel": "equipe", "role": "administrador"},
        app_metadata={"role": "service_role"},
    )

    r = c.cliente.get("/v1/me", headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["papel"] == "cliente" and r.json()["nome"] == "Maria Nova"
    assert _linhas(c, uid) == [("Maria Nova", "ativo")]

    # cadastro -> pedido: abre o pedido já na primeira sessão
    r = c.cliente.post("/v1/pedidos", json=corpo_pedido(c), headers=h)
    assert r.status_code == 201, r.text
    assert r.json()["cliente_id"] == uid
    assert c.cliente.get(f"/v1/pedidos/{r.json()['id']}", headers=h).status_code == 200

    # o papel de equipe continua exigindo a linha em `equipe`: o claim não abre o painel
    assert c.cliente.get("/v1/admin/verificacoes", headers=h).status_code == 403


def test_repetir_o_login_nao_duplica_nem_muda_nada(cenario):
    c = cenario
    uid = _novo_no_auth(c)
    h = _cabecalho(c, uid, user_metadata={"full_name": "Primeiro Nome"})
    assert c.cliente.get("/v1/me", headers=h).status_code == 200
    h2 = _cabecalho(c, uid, user_metadata={"full_name": "Outro Nome"})
    assert c.cliente.get("/v1/me", headers=h2).status_code == 200
    assert _linhas(c, uid) == [("Primeiro Nome", "ativo")]


def test_logins_simultaneos_do_mesmo_usuario_dao_uma_linha_so(cenario):
    c = cenario
    uid = _novo_no_auth(c)
    h = _cabecalho(c, uid)

    with ThreadPoolExecutor(8) as pool:
        codigos = list(pool.map(lambda _: c.cliente.get("/v1/me", headers=h).status_code, range(8)))

    assert set(codigos) == {200}
    assert _linhas(c, uid) == [("Novo usuário", "ativo")]


def test_token_de_quem_nao_esta_no_auth_nao_cria_nada(cenario):
    c = cenario
    fantasma = str(uuid.uuid4())  # nunca existiu em auth.users
    assert c.cliente.get("/v1/me", headers=_cabecalho(c, fantasma)).status_code == 401
    assert _linhas(c, fantasma) == []
    assert c.cliente.get("/v1/me", headers=_cabecalho(c, "nao-e-uuid")).status_code == 401


def test_login_anonimo_nao_cria_usuario(cenario):
    c = cenario
    uid = _novo_no_auth(c)
    assert c.cliente.get("/v1/me", headers=_cabecalho(c, uid, is_anonymous=True)).status_code == 401
    assert _linhas(c, uid) == []


def test_conta_bloqueada_continua_barrada_e_nao_e_recriada(cenario):
    c = cenario
    uid = _novo_no_auth(c)
    h = _cabecalho(c, uid)
    assert c.cliente.get("/v1/me", headers=h).status_code == 200
    with c.local.admin() as con:
        con.execute("update public.usuarios set status = 'bloqueado' where id = %s", (uid,))
    assert c.cliente.get("/v1/me", headers=h).status_code == 401
    assert _linhas(c, uid) == [("Novo usuário", "bloqueado")]


def test_dados_privados_so_uma_vez_e_cpf_de_outro_e_recusado(cenario):
    c = cenario
    a, b = _novo_no_auth(c), _novo_no_auth(c)
    for uid in (a, b):
        c.contexto.usuarios.garantir(uid)
    cpf = f"9{uuid.uuid4().int % 10**10:010d}"
    assert c.contexto.usuarios.registrar_dados_privados(a, cpf, None) is True
    assert c.contexto.usuarios.registrar_dados_privados(a, cpf, None) is False  # idempotente
    with pytest.raises(Duplicado):
        c.contexto.usuarios.registrar_dados_privados(b, cpf, None)
