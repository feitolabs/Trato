"""Testes de regressão das correções de QA (backend + App/Admin contratos)."""

from __future__ import annotations

from datetime import date, timedelta
from types import SimpleNamespace

from admin_ambiente import adm  # noqa: F401
from admin_ambiente import cab as cab_admin
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_contestacao_repasse import _painel
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.auth import PapelUsuario
from trato.api.repositorios import Orcamento
from trato.api.repositorios_app import DocumentoVerificacao, NotaMaterial, PerfilDetalhe
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.pedidos import estados
from trato.pedidos.estados import Ator, Estado, Papel
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


def test_maioridade_18_anos_no_cadastro_e_dados_pessoais(amb):
    hoje = date.today()
    menor = date(hoje.year - 17, hoje.month, hoje.day).isoformat()
    r_menor = amb.cliente.post(
        "/v1/cadastro/vincular",
        json={
            "usuario_id": "cli-1",
            "email": "menor@email.com",
            "nome": "Menor Idade",
            "cpf": "123.456.789-09",
            "data_nascimento": menor,
        },
    )
    assert r_menor.status_code == 422
    r_patch_menor = amb.cliente.patch(
        "/v1/me/dados-pessoais",
        json={"data_nascimento": menor},
        headers=cab("t-cliente"),
    )
    assert r_patch_menor.status_code == 422
    adulto = "1995-05-10"
    assert (
        amb.cliente.patch(
            "/v1/me/dados-pessoais",
            json={"data_nascimento": adulto},
            headers=cab("t-cliente"),
        ).status_code
        == 200
    )
    r_remover = amb.cliente.patch(
        "/v1/me/dados-pessoais",
        json={"remover_data_nascimento": True},
        headers=cab("t-cliente"),
    )
    assert r_remover.status_code == 422


def test_isolamento_cliente_profissional_na_busca_orcamentos_pedidos_e_chat(amb):
    mod = modulo_em_memoria(amb.cliente.app)
    mod.catalogo.categorias["cat-1"] = "eletrica"
    mod.catalogo.nomes["cat-1"] = "Elétrica"
    mod.catalogo.cidades.add("bh")
    mod.repo.salvar(
        PerfilProfissional(
            PROFISSIONAL.id,
            "aprovado",
            "Eletricista",
            ("cat-1",),
            (Regiao("bh"),),
            (),
            (),
            AGORA,
        )
    )
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(
            PROFISSIONAL.id, "Carlos Pro", PapelUsuario.PROFISSIONAL, "ativo", "verificado"
        )
    )
    # Outro usuário enxerga na busca; o próprio usuário NÃO se vê na busca.
    outros = amb.cliente.get("/v1/profissionais", headers=cab("t-cliente")).json()["itens"]
    proprios = amb.cliente.get("/v1/profissionais", headers=cab("t-prof")).json()["itens"]
    assert any(i["id"] == PROFISSIONAL.id for i in outros)
    assert all(i["id"] != PROFISSIONAL.id for i in proprios)

    # Pedido criado pelo próprio usuário (mesmo id como cliente e profissional) não aparece para ele como profissional.
    amb.contexto.pedidos.salvar(
        estados.abrir_pedido("ped-auto", Ator(Papel.CLIENTE, PROFISSIONAL.id), AGORA)
    )
    amb.contexto.orcamentos.adicionar(Orcamento("orc-auto", "ped-auto", PROFISSIONAL.id, 10000))
    assert amb.cliente.get("/v1/profissional/orcamentos", headers=cab("t-prof")).json() == []
    assert amb.cliente.get("/v1/pedidos?como=profissional", headers=cab("t-prof")).json() == []

    # Cliente tentando abrir conversa com o próprio id recebe 403.
    amb.semear_pedido(Estado.ABERTO)
    r_chat = amb.cliente.post(
        f"/v1/pedidos/ped-1/mensagens?profissional_id={CLIENTE.id}",
        json={"texto": "Oi"},
        headers=cab("t-cliente"),
    )
    assert r_chat.status_code == 403


def test_trava_categorias_apos_verificacao_e_aprovacao(amb):
    mod = modulo_em_memoria(amb.cliente.app)
    mod.catalogo.categorias.update({"cat-1": "eletrica", "cat-2": "encanador"})
    mod.catalogo.nomes.update({"cat-1": "Elétrica", "cat-2": "Encanador"})
    mod.catalogo.cidades.add("bh")

    assert (
        amb.cliente.post(
            "/v1/profissional/cadastro",
            json={"categorias": ["cat-1"], "regioes": [{"cidade_id": "bh"}]},
            headers=cab("t-prof"),
        ).status_code
        == 201
    )
    # Ainda em análise e sem verificação: pode editar categorias.
    ok_antes = amb.cliente.patch(
        "/v1/profissional/perfil",
        json={"categorias": ["cat-2"]},
        headers=cab("t-prof"),
    )
    assert ok_antes.status_code == 200 and ok_antes.json()["categorias"] == ["cat-2"]

    # Enviou documentos para verificação: não pode mais trocar categorias, mas pode atualizar bio.
    amb.contexto.verificacoes.enviar(
        PROFISSIONAL.id,
        "verificado",
        (DocumentoVerificacao("documento_frente", f"verificacao/{PROFISSIONAL.id}/doc.jpg"),),
        AGORA,
    )
    bloqueado = amb.cliente.patch(
        "/v1/profissional/perfil",
        json={"categorias": ["cat-1"]},
        headers=cab("t-prof"),
    )
    assert bloqueado.status_code == 409
    assert (
        amb.cliente.patch(
            "/v1/profissional/perfil",
            json={"bio": "Bio atualizada"},
            headers=cab("t-prof"),
        ).status_code
        == 200
    )
