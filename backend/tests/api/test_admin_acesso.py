"""Autorização por PAPEL da equipe: papel errado = 403, papel revogado/inativo = 403."""

from dataclasses import replace

import pytest
from admin_ambiente import adm, cab, token_de  # noqa: F401

from trato.api.admin.papeis import MATRIZ, PapelEquipe, Permissao

# (método, caminho, corpo, permissão exigida)
ROTAS = [
    ("GET", "/v1/admin/verificacoes", None, Permissao.VERIFICACOES_VER),
    ("GET", "/v1/admin/verificacoes/ver-1", None, Permissao.VERIFICACOES_VER),
    (
        "POST",
        "/v1/admin/verificacoes/ver-1/documentos/doc-1/url",
        {"motivo": "Conferir documento"},
        Permissao.DOCUMENTOS_REVELAR,
    ),
    (
        "POST",
        "/v1/admin/verificacoes/ver-1/decisao",
        {"aprovar": True, "motivo": "Documentos conferem"},
        Permissao.VERIFICACOES_DECIDIR,
    ),
    ("GET", "/v1/admin/disputas", None, Permissao.DISPUTAS_VER),
    ("GET", "/v1/admin/disputas/ped-1", None, Permissao.DISPUTAS_VER),
    (
        "POST",
        "/v1/admin/disputas/ped-1/decisao",
        {"resultado": "liberar_tudo", "justificativa": "Serviço entregue"},
        Permissao.DISPUTAS_DECIDIR,
    ),
    (
        "POST",
        "/v1/admin/disputas/ped-1/aprovacao",
        {"justificativa": "De acordo com a decisão"},
        Permissao.DISPUTAS_SEGUNDA_PESSOA,
    ),
    ("GET", "/v1/admin/pagamentos", None, Permissao.PAGAMENTOS_VER),
    ("GET", "/v1/admin/pagamentos/resumo", None, Permissao.PAGAMENTOS_VER),
    ("GET", "/v1/admin/webhooks/eventos", None, Permissao.PAGAMENTOS_VER),
    ("GET", "/v1/admin/lancamentos", None, Permissao.PAGAMENTOS_VER),
    ("GET", "/v1/admin/contratos/ped-1/extrato", None, Permissao.PAGAMENTOS_VER),
    ("GET", "/v1/admin/usuarios", None, Permissao.USUARIOS_BUSCAR),
    ("GET", "/v1/admin/usuarios/cli-1", None, Permissao.USUARIOS_BUSCAR),
    (
        "POST",
        "/v1/admin/usuarios/cli-1/dados-pessoais",
        {"motivo": "Atender pedido do titular"},
        Permissao.DADOS_PESSOAIS_REVELAR,
    ),
    ("GET", "/v1/admin/pedidos", None, Permissao.PEDIDOS_BUSCAR),
    ("GET", "/v1/admin/pedidos/ped-1", None, Permissao.PEDIDOS_BUSCAR),
    ("GET", "/v1/admin/config/definicoes", None, Permissao.CONFIG_VER),
    ("GET", "/v1/admin/config/vigente", None, Permissao.CONFIG_VER),
    ("GET", "/v1/admin/config/versoes", None, Permissao.CONFIG_VER),
    (
        "POST",
        "/v1/admin/config/versoes",
        {"motivo": "Ajustar prazo", "parametros": []},
        Permissao.CONFIG_PROPOR,
    ),
    (
        "POST",
        "/v1/admin/config/versoes/cfg-1/aprovar",
        {"motivo": "Conferi a proposta"},
        Permissao.CONFIG_APROVAR,
    ),
    ("GET", "/v1/admin/auditoria", None, Permissao.AUDITORIA_VER),
    ("POST", "/v1/admin/auditoria/verificar-cadeia", None, Permissao.AUDITORIA_VERIFICAR_CADEIA),
]
IDS = [f"{m} {c}" for m, c, _, _ in ROTAS]


def chamar(adm, metodo, caminho, corpo, token):
    return adm.cliente.request(metodo, caminho, json=corpo, headers=cab(token))


@pytest.mark.parametrize(("metodo", "caminho", "corpo", "permissao"), ROTAS, ids=IDS)
def test_papel_sem_a_permissao_recebe_403(adm, metodo, caminho, corpo, permissao):
    for papel in PapelEquipe:
        if permissao in MATRIZ[papel]:
            continue
        r = chamar(adm, metodo, caminho, corpo, token_de(papel.value))
        assert r.status_code == 403, f"{papel} em {metodo} {caminho}: {r.status_code}"


@pytest.mark.parametrize(("metodo", "caminho", "corpo", "permissao"), ROTAS, ids=IDS)
def test_papel_com_a_permissao_passa_da_autorizacao(adm, metodo, caminho, corpo, permissao):
    adm.semear_disputa()
    for papel in PapelEquipe:
        if permissao not in MATRIZ[papel]:
            continue
        r = chamar(adm, metodo, caminho, corpo, token_de(papel.value))
        assert r.status_code not in (401, 403), f"{papel} em {metodo} {caminho}: {r.text}"


@pytest.mark.parametrize(("metodo", "caminho", "corpo", "permissao"), ROTAS, ids=IDS)
@pytest.mark.parametrize("token", ["t-cliente", "t-prof", "t-revogado", "t-inativo", "t-sem-linha"])
def test_quem_nao_esta_vigente_na_equipe_recebe_403(adm, metodo, caminho, corpo, permissao, token):
    assert chamar(adm, metodo, caminho, corpo, token).status_code == 403


@pytest.mark.parametrize(("metodo", "caminho", "corpo", "permissao"), ROTAS[:3], ids=IDS[:3])
def test_sem_token_ou_token_invalido_recebe_401(adm, metodo, caminho, corpo, permissao):
    assert adm.cliente.request(metodo, caminho, json=corpo).status_code == 401
    assert chamar(adm, metodo, caminho, corpo, "t-qualquer").status_code == 401


def test_papel_revogado_na_hora_perde_o_acesso(adm):
    assert adm.cliente.get("/v1/admin/auditoria", headers=cab("t-administrador")).status_code == 200
    membro = adm.admin.equipe.obter("eq-administrador")
    adm.admin.equipe.salvar(replace(membro, revogado_em=adm.relogio()))
    assert adm.cliente.get("/v1/admin/auditoria", headers=cab("t-administrador")).status_code == 403


def test_so_o_papel_cadastro_abre_documento(adm):
    caminho = "/v1/admin/verificacoes/ver-1/documentos/doc-1/url"
    corpo = {"motivo": "Conferir documento"}
    for papel in ("administrador", "seguranca", "financeiro", "mediador"):
        r = adm.cliente.post(caminho, json=corpo, headers=cab(token_de(papel)))
        assert r.status_code == 403
    assert adm.cliente.post(caminho, json=corpo, headers=cab("t-cadastro")).status_code == 200
