# ruff: noqa: F811
"""TERMOS-BE-209 (20.9): encerramento grave + impedimento HMAC, bloqueio de cadastro e retorno."""

from __future__ import annotations

import pytest
from admin_ambiente import adm, cab, token_de  # noqa: F401
from conftest import CLIENTE

from trato.api.admin.repositorios import FiltroAuditoria
from trato.persistencia.retorno_conta import RetornoContaEmMemoria

CPF_BLOQ = "52998224725"
EMAIL_BLOQ = "grave@trato.test"
TEL_BLOQ = "11988887777"


def _encerrar(adm, *, grave: bool, impedir: bool, extra_ids: dict | None = None):
    adm.contexto.usuarios.garantir(CLIENTE.id)
    corpo = {
        "usuario_id": CLIENTE.id,
        "tipo": "encerramento",
        "motivo": "Encerramento de conta aplicado após análise formal.",
        "clausulas": ["20.9"],
        "infracao_grave": grave,
        "impedir_nova_conta": impedir,
    }
    if extra_ids is not None:
        corpo["identificadores_impedimento"] = extra_ids
    return adm.cliente.post("/v1/admin/medidas", json=corpo, headers=cab(token_de("mediador")))


def test_encerramento_grave_cria_impedimento_hmac_bloqueia_cadastro_e_permite_revogar(adm):
    # Validações: impedir_nova_conta exige infracao_grave; infracao_grave exige encerramento
    assert (
        adm.cliente.post(
            "/v1/admin/medidas",
            json={
                "usuario_id": CLIENTE.id,
                "tipo": "encerramento",
                "motivo": "Tentativa inválida de impedimento sem infração grave.",
                "clausulas": ["20.9"],
                "infracao_grave": False,
                "impedir_nova_conta": True,
            },
            headers=cab(token_de("mediador")),
        ).status_code
        == 422
    )
    assert (
        adm.cliente.post(
            "/v1/admin/medidas",
            json={
                "usuario_id": CLIENTE.id,
                "tipo": "suspensao",
                "dias": 5,
                "motivo": "Suspensão não pode marcar infração grave.",
                "clausulas": ["20.9"],
                "infracao_grave": True,
            },
            headers=cab(token_de("mediador")),
        ).status_code
        == 422
    )

    r_med = _encerrar(
        adm,
        grave=True,
        impedir=True,
        extra_ids={"cpf": CPF_BLOQ, "email": EMAIL_BLOQ, "telefone": TEL_BLOQ},
    )
    assert r_med.status_code == 201, r_med.text
    med = r_med.json()
    assert med["infracao_grave"] is True and med["impedir_nova_conta"] is True

    # Impedimentos salvos só como HMAC (64 hex), sem dado pessoal em claro
    lista = adm.cliente.get(
        "/v1/admin/conta/impedimentos",
        params={"medida_id": med["id"], "apenas_ativos": True},
        headers=cab(token_de("mediador")),
    )
    assert lista.status_code == 200 and lista.json()["total"] == 3
    assert CPF_BLOQ not in lista.text and EMAIL_BLOQ not in lista.text

    # Cadastro recusado com 403 para CPF, e-mail e telefone impedidos
    assert adm.cliente.post("/v1/cadastro/cpf", json={"cpf": CPF_BLOQ}).status_code == 403
    assert (
        adm.cliente.post(
            "/v1/cadastro/vincular",
            json={"usuario_id": "novo-1", "email": EMAIL_BLOQ, "nome": "Outro"},
        ).status_code
        == 403
    )
    assert (
        adm.cliente.post(
            "/v1/me/cpf",
            json={"cpf": CPF_BLOQ, "telefone": TEL_BLOQ},
            headers=cab("t-prof"),
        ).status_code
        == 403
    )

    # Mediador não pode revogar impedimento (403); líder de suporte revoga (200)
    imp_cpf = next(i for i in lista.json()["itens"] if i["tipo_identificador"] == "cpf")
    assert (
        adm.cliente.post(
            f"/v1/admin/conta/impedimentos/{imp_cpf['id']}/revogar",
            json={"motivo": "Tentativa sem papel de aprovação."},
            headers=cab(token_de("mediador")),
        ).status_code
        == 403
    )
    r_rev = adm.cliente.post(
        f"/v1/admin/conta/impedimentos/{imp_cpf['id']}/revogar",
        json={"motivo": "Erro comprovado na identificação do CPF."},
        headers=cab(token_de("lider_suporte")),
    )
    assert r_rev.status_code == 200 and r_rev.json()["revogado_em"] is not None

    # Após revogar o CPF, consulta de CPF volta a ser permitida (200)
    assert adm.cliente.post("/v1/cadastro/cpf", json={"cpf": CPF_BLOQ}).status_code == 200

    # Conta encerrada por infração grave não pode pedir retorno (403)
    adm.relogio.avancar(days=100)
    assert (
        adm.cliente.post(
            "/v1/me/conta/retorno",
            json={"justificativa": "Gostaria de retornar à plataforma após o encerramento."},
            headers=cab("t-cliente"),
        ).status_code
        == 403
    )


def test_pedido_retorno_prazo_idempotencia_aprovacao_recusa_e_auditoria(adm):
    r_med = _encerrar(adm, grave=False, impedir=False)
    assert r_med.status_code == 201

    # Antes do prazo de 90 dias -> 409
    assert (
        adm.cliente.post(
            "/v1/me/conta/retorno",
            json={"justificativa": "Quero voltar antes de completar o prazo mínimo."},
            headers=cab("t-cliente"),
        ).status_code
        == 409
    )

    # Após 90 dias -> 201 e repetição idempotente -> 200
    adm.relogio.avancar(days=91)
    r1 = adm.cliente.post(
        "/v1/me/conta/retorno",
        json={"justificativa": "Cumpri o prazo de 90 dias e peço análise para retorno."},
        headers=cab("t-cliente"),
    )
    assert r1.status_code == 201, r1.text
    ret = r1.json()
    assert ret["status"] == "aberto" and ret["protocolo"].startswith("RET-")
    assert "analista_id" not in ret

    r2 = adm.cliente.post(
        "/v1/me/conta/retorno",
        json={"justificativa": "Repetição enquanto aberto."},
        headers=cab("t-cliente"),
    )
    assert r2.status_code == 200 and r2.json()["id"] == ret["id"]

    # Usuário consulta próprio pedido sem analista_id
    meus = adm.cliente.get("/v1/me/conta/retorno", headers=cab("t-cliente"))
    assert meus.status_code == 200 and meus.json()["total"] == 1
    assert "analista_id" not in meus.json()["itens"][0]

    # Mediador passa para em_analise (200), mas não pode aprovar (403)
    assert (
        adm.cliente.post(
            f"/v1/admin/conta/retornos/{ret['id']}/analisar",
            headers=cab(token_de("mediador")),
        ).status_code
        == 200
    )
    assert (
        adm.cliente.post(
            f"/v1/admin/conta/retornos/{ret['id']}/aprovar",
            json={"motivo": "Tentativa de aprovação por mediador.", "risco_identificado": False},
            headers=cab(token_de("mediador")),
        ).status_code
        == 403
    )

    # Líder de suporte não pode aprovar com risco_identificado=True (422)
    assert (
        adm.cliente.post(
            f"/v1/admin/conta/retornos/{ret['id']}/aprovar",
            json={"motivo": "Risco ainda presente.", "risco_identificado": True},
            headers=cab(token_de("lider_suporte")),
        ).status_code
        == 422
    )

    # Líder de suporte aprova com risco_identificado=False -> 200
    r_apr = adm.cliente.post(
        f"/v1/admin/conta/retornos/{ret['id']}/aprovar",
        json={
            "motivo": "Sem risco identificado após análise do histórico.",
            "risco_identificado": False,
        },
        headers=cab(token_de("lider_suporte")),
    )
    assert r_apr.status_code == 200 and r_apr.json()["status"] == "aprovado"

    # Auditoria registrada
    eventos, _ = adm.admin.auditoria.listar(FiltroAuditoria(), 50, 0)
    acoes = [e.acao for e in eventos]
    assert "conta.retorno_em_analise" in acoes and "conta.retorno_aprovado" in acoes


_JUSTIFICATIVA = {"justificativa": "Cumpri o prazo e peço análise para voltar."}


def test_conta_encerrada_e_bloqueada_pede_e_consulta_o_retorno(adm):
    assert _encerrar(adm, grave=False, impedir=False).status_code == 201
    adm.contexto.auth.bloqueados.add("t-cliente")  # como no encerramento real
    url = "/v1/me/conta/retorno"
    h = cab("t-cliente")

    # As outras rotas continuam recusando a conta bloqueada
    outra = adm.cliente.get("/v1/me/lgpd/pedidos", headers=h)
    assert outra.status_code == 403 and outra.json()["codigo"] == "conta_bloqueada"

    assert (
        adm.cliente.post(url, json=_JUSTIFICATIVA, headers=h).status_code == 409
    )  # antes do prazo
    assert adm.cliente.get(url, headers=h).json() == {"itens": [], "total": 0}

    adm.relogio.avancar(days=91)
    r = adm.cliente.post(url, json=_JUSTIFICATIVA, headers=h)
    assert r.status_code == 201, r.text
    assert adm.cliente.post(url, json=_JUSTIFICATIVA, headers=h).status_code == 200
    meus = adm.cliente.get(url, headers=h)
    assert meus.status_code == 200 and [i["id"] for i in meus.json()["itens"]] == [r.json()["id"]]
    assert "analista_id" not in meus.json()["itens"][0]

    # Cada um só vê os próprios pedidos
    assert adm.cliente.get(url, headers=cab("t-prof")).json()["total"] == 0


def test_conta_bloqueada_por_infracao_grave_segue_recusada(adm):
    assert _encerrar(adm, grave=True, impedir=False).status_code == 201
    adm.contexto.auth.bloqueados.add("t-cliente")
    adm.relogio.avancar(days=100)
    r = adm.cliente.post("/v1/me/conta/retorno", json=_JUSTIFICATIVA, headers=cab("t-cliente"))
    assert r.status_code == 403 and "infração grave" in r.text


def test_conta_bloqueada_sem_encerramento_recebe_409(adm):
    adm.contexto.auth.bloqueados.add("t-cliente")
    r = adm.cliente.post("/v1/me/conta/retorno", json=_JUSTIFICATIVA, headers=cab("t-cliente"))
    assert r.status_code == 409


@pytest.mark.parametrize("metodo", ["GET", "POST"])
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer token-invalido"}])
def test_retorno_sem_login_valido_responde_401(adm, metodo, headers):
    corpo = _JUSTIFICATIVA if metodo == "POST" else None
    r = adm.cliente.request(metodo, "/v1/me/conta/retorno", json=corpo, headers=headers)
    assert r.status_code == 401


@pytest.mark.parametrize(
    ("metodo", "caminho", "corpo", "token"),
    [
        ("GET", "/v1/me/conta/retorno", None, "t-cliente"),
        (
            "POST",
            "/v1/me/conta/retorno",
            {"justificativa": "Solicitação sem tabela no banco."},
            "t-cliente",
        ),
        ("GET", "/v1/admin/conta/impedimentos", None, token_de("mediador")),
        ("GET", "/v1/admin/conta/retornos", None, token_de("mediador")),
    ],
)
def test_tabelas_ausentes_respondem_503_limpo(adm, metodo, caminho, corpo, token):
    adm.contexto.retorno_conta = RetornoContaEmMemoria(disponivel=False)
    r = adm.cliente.request(metodo, caminho, json=corpo, headers=cab(token))
    assert r.status_code == 503
