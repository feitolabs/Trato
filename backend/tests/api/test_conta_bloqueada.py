"""TERMOS-BE-ACESSO (20.5): conta bloqueada recebe 403 `conta_bloqueada` (não 401) e só o
atendimento e as medidas continuam abertos a ela."""

from __future__ import annotations

import re
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from conftest import cab

from trato.api.auth import PapelUsuario
from trato.api.auth_supabase import ProvedorAuthSupabase
from trato.persistencia.usuarios import PerfilUsuario

ABERTAS = ("/v1/sac/", "/v1/me/medidas")
# O aparelho recebe o aviso da medida e o token sai quando a pessoa sai (só estes métodos).


def _aberta(caminho: str) -> bool:
    # /v1/me/acessos: o registro do próprio acesso vale para o bloqueado (14.3 e 16.1).
    exatas = ("/v1/sac/chamados", "/v1/dispositivos", "/v1/me/conta/retorno", "/v1/me/acessos")
    return caminho in exatas or caminho.startswith(ABERTAS)


def _rotas(amb):
    for caminho, metodos in amb.cliente.app.openapi()["paths"].items():
        for metodo in metodos:
            yield metodo.upper(), caminho, re.sub(r"\{[^}]+\}", "x", caminho)


def test_me_responde_403_com_codigo_e_sem_pedir_novo_login(amb):
    amb.contexto.auth.bloqueados.add("t-cliente")
    r = amb.cliente.get("/v1/me", headers=cab("t-cliente"))
    assert r.status_code == 403, r.text
    assert set(r.json()) == {"detail", "codigo"} and r.json()["codigo"] == "conta_bloqueada"
    assert "WWW-Authenticate" not in r.headers


@pytest.mark.parametrize("quem", ["t-cliente", "t-prof", "t-mediador"])
def test_em_todas_as_rotas_so_atendimento_medidas_retorno_e_aparelho_ficam_abertos(amb, quem):
    """Varre a API: toda rota que pede login (401 sem token) recusa o bloqueado com 403."""
    amb.contexto.auth.bloqueados.add(quem)
    fechadas, abertas = [], []
    for metodo, caminho, url in _rotas(amb):
        if amb.cliente.request(metodo, url).status_code != 401:
            continue  # pública (ou com outra autenticação): o token não muda nada aqui
        r = amb.cliente.request(metodo, url, headers=cab(quem))
        corpo = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        codigo = corpo.get("codigo") if isinstance(corpo, dict) else None
        if _aberta(caminho):
            abertas.append(f"{metodo} {caminho}")
            assert r.status_code != 401 and codigo != "conta_bloqueada", (metodo, caminho)
        else:
            fechadas.append(caminho)
            assert (r.status_code, codigo) == (403, "conta_bloqueada"), (metodo, caminho, r.text)
    assert len(fechadas) > 100
    assert sorted(abertas) == [
        "DELETE /v1/dispositivos",
        "GET /v1/me/conta/retorno",
        "GET /v1/me/medidas",
        "GET /v1/sac/chamados",
        "GET /v1/sac/chamados/{chamado_id}",
        "POST /v1/dispositivos",
        "POST /v1/me/acessos",
        "POST /v1/me/conta/retorno",
        "POST /v1/me/medidas/{medida_id}/contestacao",
        "POST /v1/me/medidas/{medida_id}/contestacao/anexos",
        "POST /v1/sac/chamados",
        "POST /v1/sac/chamados/{chamado_id}/mensagens",
    ]


def test_bloqueado_usa_o_atendimento_e_as_medidas(amb):
    amb.contexto.auth.bloqueados.add("t-cliente")
    assert amb.cliente.get("/v1/me/medidas", headers=cab("t-cliente")).status_code == 200
    corpo = {"categoria": "contestacao", "assunto": "Minha conta", "texto": "Quero entender."}
    r = amb.cliente.post("/v1/sac/chamados", json=corpo, headers=cab("t-cliente"))
    assert r.status_code == 201, r.text


@pytest.mark.parametrize("quem", ["t-cliente", "t-prof"])
def test_bloqueado_registra_e_remove_o_aparelho(amb, quem):
    amb.contexto.auth.bloqueados.add(quem)
    token = {"token": f"aparelho-de-teste-{quem}-0123456789"}
    r = amb.cliente.post(
        "/v1/dispositivos", json=token | {"plataforma": "android"}, headers=cab(quem)
    )
    assert r.status_code == 204, r.text
    r = amb.cliente.request("DELETE", "/v1/dispositivos", json=token, headers=cab(quem))
    assert r.status_code == 204, r.text


def test_equipe_continua_sem_registrar_aparelho(amb):
    corpo = {"token": "aparelho-de-teste-da-equipe-0123456789", "plataforma": "android"}
    r = amb.cliente.post("/v1/dispositivos", json=corpo, headers=cab("t-mediador"))
    assert r.status_code == 403, r.text


@pytest.mark.parametrize("url", ["/v1/me", "/v1/sac/chamados", "/v1/me/medidas"])
@pytest.mark.parametrize("cabecalho", [{}, cab("token-que-nao-existe")])
def test_o_resto_do_401_nao_muda(amb, url, cabecalho):
    amb.contexto.auth.bloqueados.add("token-que-nao-existe")  # sem conta: não é "bloqueada"
    r = amb.cliente.get(url, headers=cabecalho)
    assert r.status_code == 401 and r.headers["WWW-Authenticate"] == "Bearer"
    assert r.json().get("codigo") != "conta_bloqueada"


# --- provedor real (JWT) -------------------------------------------------------------------------

SEGREDO = "segredo-de-teste-com-mais-de-32-bytes!!"
SUB = "7f0c1e9a-1111-4222-8333-444455556666"


class Usuarios:
    def __init__(self, status: str | None) -> None:
        self.status = status

    def perfil(self, usuario_id):
        if self.status is None:
            return None
        return PerfilUsuario(usuario_id, "Pessoa", self.status, PapelUsuario.CLIENTE)

    def garantir(self, usuario_id, nome=None):
        return self.perfil(usuario_id)


def _token(segredo=SEGREDO, vence=timedelta(hours=1), **extra) -> str:
    carga = {"sub": SUB, "aud": "authenticated", "exp": datetime.now(UTC) + vence} | extra
    return jwt.encode(carga, segredo, "HS256")


def _provedor(status: str | None) -> ProvedorAuthSupabase:
    return ProvedorAuthSupabase(Usuarios(status), segredo_hs256=lambda: SEGREDO)


@pytest.mark.parametrize(
    "status,entra,bloqueada,suporte",
    [
        ("ativo", True, False, True),
        ("restrito", True, False, True),
        ("bloqueado", False, True, True),
        ("anonimizado", False, False, False),
        (None, False, False, False),
    ],
)
def test_provedor_por_status(status, entra, bloqueada, suporte):
    provedor, token = _provedor(status), _token()
    assert (provedor.autenticar(token) is not None) is entra
    assert provedor.conta_bloqueada(token) is bloqueada
    assert (provedor.autenticar_para_suporte(token) is not None) is suporte


@pytest.mark.parametrize(
    "token",
    [
        _token(vence=timedelta(hours=-1)),
        _token(segredo="outro-segredo-com-mais-de-32-bytes!!!"),
        _token(aud="outra"),
        "nao-e-um-token",
    ],
)
def test_token_vencido_ou_falso_de_bloqueado_continua_401(token):
    provedor = _provedor("bloqueado")
    assert provedor.conta_bloqueada(token) is False
    assert provedor.autenticar(token) is None and provedor.autenticar_para_suporte(token) is None


def test_pela_api_com_o_provedor_real(amb):
    amb.contexto.auth = _provedor("bloqueado")
    r = amb.cliente.get("/v1/me", headers=cab(_token()))
    assert r.status_code == 403 and r.json()["codigo"] == "conta_bloqueada", r.text
    assert (
        amb.cliente.get("/v1/me", headers=cab(_token(vence=timedelta(hours=-1)))).status_code == 401
    )
