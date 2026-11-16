"""Testes de regressão das correções de QA (backend + App/Admin contratos)."""

from __future__ import annotations

from datetime import timedelta
from types import SimpleNamespace

from admin_ambiente import adm  # noqa: F401
from admin_ambiente import cab as cab_admin
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_contestacao_repasse import _painel
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import NotaMaterial, PerfilDetalhe
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.pedidos.estados import Estado
from trato.profissional.repositorio import (
    JanelaSemanal,
    PerfilProfissional,
    Regiao,
    dia_semana_hoje,
)


def test_auditoria_financeira_tem_motivo_em_consulta_e_conciliacao(fluxo: Fluxo):  # noqa: F811
    admin = _painel(fluxo)
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    fluxo.fake.marcar_paga(cobranca["id"])

    r_cons = fluxo.chamar(
        "POST", f"/v1/admin/financeiro/cobrancas/{cobranca['id']}/consultar", "t-financeiro"
    )
    assert r_cons.status_code == 200, r_cons.text

    dia = (fluxo.amb.relogio() - timedelta(hours=3)).date().isoformat()
    r_conc = fluxo.chamar("GET", f"/v1/admin/financeiro/conciliacao?dia={dia}", "t-financeiro")
    assert r_conc.status_code == 200, r_conc.text

    linhas, _ = admin.auditoria.listar(FiltroAuditoria(), 20, 0)
    acoes_com_motivo = {r.acao: r.motivo for r in linhas}
    assert acoes_com_motivo.get("pagamento.consultado_no_provedor")
    assert acoes_com_motivo.get("pagamento.conciliacao_executada")


def test_nota_material_inclui_foto_url_assinada(amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO)
    amb.contexto.notas_material.registrar(
        NotaMaterial(
            "n-1",
            "ped-1",
            PROFISSIONAL.id,
            "pedidos/ped-1/nota.jpg",
            (("Fio 2.5mm", "2", 1500, 3000),),
            3000,
            AGORA,
        )
    )
    amb.cliente.app.state.servico_uploads = SimpleNamespace(
        armazenamento=SimpleNamespace(
            url_leitura=lambda bucket, path, exp: f"https://cdn.teste/{bucket}/{path}?e={exp}"
        )
    )
    r = amb.cliente.get("/v1/contratos/ped-1/notas-material", headers=cab("t-cliente"))
    assert r.status_code == 200
    assert r.json()[0]["foto_url"] == "https://cdn.teste/pedido-midias/pedidos/ped-1/nota.jpg?e=300"


def test_cadastro_vincular_e_dados_pessoais_aceitam_data_nascimento(amb):
    r1 = amb.cliente.post(
        "/v1/cadastro/vincular",
        json={
            "usuario_id": "cli-1",
            "email": "mariana@email.com",
            "nome": "Mariana",
            "cpf": "123.456.789-09",
            "telefone": "+5531987654417",
            "data_nascimento": "1992-03-15",
        },
    )
    assert r1.status_code == 204
    r2 = amb.cliente.post(
        "/v1/me/dados-pessoais",
        json={"cpf": "52998224725", "data_nascimento": "1990-01-20"},
        headers=cab("t-outro-cliente"),
    )
    assert r2.status_code == 204


def test_busca_profissionais_filtra_por_nota_minima_e_atende_hoje(amb):
    mod = modulo_em_memoria(amb.cliente.app)
    mod.catalogo.categorias["cat-1"] = "eletrica"
    mod.catalogo.nomes["cat-1"] = "Elétrica"
    hoje = dia_semana_hoje()
    outro_dia = (hoje + 1) % 7
    mod.repo.salvar(
        PerfilProfissional(
            "p-bom",
            "aprovado",
            "Bio",
            ("cat-1",),
            (Regiao("bh"),),
            (JanelaSemanal(hoje, "08:00", "12:00"),),
            (),
            AGORA,
        )
    )
    mod.repo.salvar(
        PerfilProfissional(
            "p-outro",
            "aprovado",
            "Bio",
            ("cat-1",),
            (Regiao("bh"),),
            (JanelaSemanal(outro_dia, "08:00", "12:00"),),
            (),
            AGORA,
        )
    )
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe("p-bom", "Bom Pro", PapelUsuario.PROFISSIONAL, "ativo", "verificado", 4.9, 10)
    )
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(
            "p-outro", "Outro Pro", PapelUsuario.PROFISSIONAL, "ativo", "verificado", 4.3, 10
        )
    )
    r_nota = amb.cliente.get("/v1/profissionais?nota_minima=4.8", headers=cab("t-cliente"))
    assert [i["id"] for i in r_nota.json()["itens"]] == ["p-bom"]
    r_hoje = amb.cliente.get("/v1/profissionais?atende_hoje=true", headers=cab("t-cliente"))
    assert [i["id"] for i in r_hoje.json()["itens"]] == ["p-bom"]


def test_config_descartar_aceita_motivo_por_query_e_respeita_limite(adm):  # noqa: F811
    fin = cab_admin("t-financeiro")
    criada = adm.cliente.post(
        "/v1/admin/config/versoes",
        json={"motivo": "Rascunho de teste", "partir_da_vigente": True},
        headers=fin,
    ).json()
    assert adm.cliente.get("/v1/admin/config/versoes?limite=1", headers=fin).json()
    d = adm.cliente.delete(
        f"/v1/admin/config/versoes/{criada['id']}",
        params={"motivo": "Descartar via query param"},
        headers=fin,
    )
    assert d.status_code == 204


def test_pedido_out_inclui_profissional_nome_abreviado_para_o_cliente(amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO)
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(PROFISSIONAL.id, "Carlos Eduardo Silva", PapelUsuario.PROFISSIONAL)
    )
    amb.contexto.usuarios.adicionar(PerfilDetalhe(CLIENTE.id, "Maria Alves", PapelUsuario.CLIENTE))
    r = amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-cliente"))
    assert r.status_code == 200
    assert r.json()["profissional_nome"] == "Carlos S."
