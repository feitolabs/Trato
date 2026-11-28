"""BE-ACESSOS (Termos 14.3 e 16.1) na API: o que é registrado e o que nunca derruba."""

from __future__ import annotations

import pytest
from conftest import CLIENTE, cab

from trato.agendador.__main__ import rotina_de_expurgo
from trato.agendador.config import ConfigAgendador


class Acessos:
    def __init__(self, falha: bool = False) -> None:
        self.itens: list[tuple] = []
        self.falha = falha

    def registrar(self, acesso, janela):
        if self.falha:
            raise RuntimeError("banco fora")
        self.itens.append((acesso, janela))
        return "registrado"


def test_requisicao_autenticada_grava_uma_vez_por_janela_sem_ip_forjado(amb):
    repo = amb.contexto.extras["acessos"] = Acessos()
    cabecalhos = cab("t-cliente") | {
        "X-Forwarded-For": "203.0.113.9",
        "X-Dispositivo-Id": "ap-1",
        "X-Aparelho-Tipo": "Android",
        "X-Sistema-Operacional": "Android 16",
        "X-App-Versao": "1.4.0",
    }
    for _ in range(3):
        assert amb.cliente.get("/v1/me", headers=cabecalhos).status_code == 200
    ((acesso, janela),) = repo.itens
    assert (acesso.usuario_id, acesso.evento, janela) == (CLIENTE.id, "acesso", 60)
    assert acesso.ip == "testclient"  # o X-Forwarded-For de quem chama não vale
    assert (acesso.aparelho_tipo, acesso.app_versao) == ("android", "1.4.0")


def test_aparelho_desconhecido_nao_vai_ao_banco_como_veio(amb):
    repo = amb.contexto.extras["acessos"] = Acessos()
    cabecalhos = cab("t-cliente") | {"X-Aparelho-Tipo": "geladeira"}
    assert amb.cliente.get("/v1/me", headers=cabecalhos).status_code == 200
    assert repo.itens[0][0].aparelho_tipo is None


def test_falha_no_registro_nao_derruba(amb):
    amb.contexto.extras["acessos"] = Acessos(falha=True)
    assert amb.cliente.get("/v1/me", headers=cab("t-cliente")).status_code == 200
    r = amb.cliente.post("/v1/me/acessos", json={"evento": "logout"}, headers=cab("t-cliente"))
    assert r.status_code == 200 and r.json() == {"registrado": False}


def test_sem_login_nao_registra(amb):
    repo = amb.contexto.extras["acessos"] = Acessos()
    assert amb.cliente.get("/v1/me").status_code == 401
    assert amb.cliente.post("/v1/me/acessos", json={"evento": "login"}).status_code == 401
    assert repo.itens == []


def test_app_avisa_login_e_logout(amb):
    repo = amb.contexto.extras["acessos"] = Acessos()
    for evento in ("login", "logout"):
        r = amb.cliente.post("/v1/me/acessos", json={"evento": evento}, headers=cab("t-cliente"))
        assert r.json() == {"registrado": True}, r.text
    eventos = [(a.evento, j) for a, j in repo.itens if a.evento != "acesso"]
    assert eventos == [("login", 0), ("logout", 0)]
    ruim = amb.cliente.post("/v1/me/acessos", json={"evento": "acesso"}, headers=cab("t-cliente"))
    assert ruim.status_code == 422


def test_expurgo_vem_desligado():
    assert ConfigAgendador(_env_file=None).expurgo_acessos_ligado is False
    assert rotina_de_expurgo(None, ConfigAgendador(_env_file=None)) is None


@pytest.mark.parametrize("quem", ["t-cliente", "t-prof"])
def test_bloqueado_so_grava_o_proprio_acesso(amb, quem):
    repo = amb.contexto.extras["acessos"] = Acessos()
    amb.contexto.auth.bloqueados.add(quem)
    proprio = amb.contexto.auth.autenticar_para_suporte(quem).id
    corpo = {"evento": "logout"}
    r = amb.cliente.post("/v1/me/acessos", json=corpo, headers=cab(quem))
    assert r.status_code == 200 and r.json() == {"registrado": True}, r.text
    assert {a.usuario_id for a, _ in repo.itens} == {proprio}
    assert {a.evento for a, _ in repo.itens} == {"acesso", "logout"}
    # Não dá para registrar em nome de outra pessoa, e o resto continua fechado.
    outro = corpo | {"usuario_id": "outra-pessoa"}
    assert amb.cliente.post("/v1/me/acessos", json=outro, headers=cab(quem)).status_code == 422
    assert amb.cliente.get("/v1/me", headers=cab(quem)).json()["codigo"] == "conta_bloqueada"


@pytest.mark.parametrize("bloqueada", [False, True])
def test_equipe_recebe_403_e_nada_e_gravado(amb, bloqueada):
    repo = amb.contexto.extras["acessos"] = Acessos()
    if bloqueada:
        amb.contexto.auth.bloqueados.add("t-mediador")
    r = amb.cliente.post("/v1/me/acessos", json={"evento": "login"}, headers=cab("t-mediador"))
    assert r.status_code == 403 and repo.itens == [], r.text
