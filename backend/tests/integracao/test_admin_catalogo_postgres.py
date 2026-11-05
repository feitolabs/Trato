"""Categorias, cidades e status de usuário no painel: Postgres LOCAL descartável (pgserver).

Essas rotas falam direto com o banco (não têm versão em memória), então só aqui dá para provar
que funcionam. Nunca toca no Supabase.
"""

from __future__ import annotations

import pytest

pytest.importorskip("pgserver", reason="pgserver não instalado: integração com Postgres pulada")
pytest.importorskip("psycopg")

from .test_admin_postgres import BASE, amb  # noqa: E402,F401  (a fixture é reutilizada)


def _auditoria(ambiente, prefixo: str) -> dict[str, str]:
    linhas = ambiente.sql(
        "select acao, motivo from public.auditoria where acao like %s order by ocorrida_em",
        prefixo + "%",
    )
    return {acao: motivo for acao, motivo in linhas}


# --- Categorias ----------------------------------------------------------------------------------


def test_categoria_ciclo_completo_criar_editar_desativar_excluir(amb):  # noqa: F811
    adm = amb.h("administrador")
    r = amb.cliente.post(
        f"{BASE}/categorias",
        json={"nome": "Limpeza residencial", "motivo": "Categoria do piloto"},
        headers=adm,
    )
    assert r.status_code == 201, r.text
    cat = r.json()
    assert cat["slug"] == "limpeza-residencial" and cat["ativa"] is True
    cid = cat["id"]

    lista = amb.cliente.get(f"{BASE}/categorias", headers=adm).json()
    assert cid in {c["id"] for c in lista}

    r = amb.cliente.put(
        f"{BASE}/categorias/{cid}",
        json={"nome": "Limpeza geral", "garantia_retrabalho_dias": 30, "motivo": "Renomear"},
        headers=adm,
    )
    assert r.status_code == 200 and r.json()["nome"] == "Limpeza geral"
    assert amb.sql(
        "select nome, garantia_retrabalho_dias from public.categorias where id = %s", cid
    ) == [("Limpeza geral", 30)]

    r = amb.cliente.patch(
        f"{BASE}/categorias/{cid}", json={"ativa": False, "motivo": "Pausa"}, headers=adm
    )
    assert r.status_code == 200 and r.json()["ativa"] is False
    assert amb.sql("select ativa from public.categorias where id = %s", cid) == [(False,)]

    r = amb.cliente.delete(
        f"{BASE}/categorias/{cid}", params={"motivo": "Limpeza do teste"}, headers=adm
    )
    assert r.status_code == 204, r.text
    assert amb.sql("select count(*) from public.categorias where id = %s", cid) == [(0,)]

    trilha = _auditoria(amb, "categoria.")
    assert trilha["categoria.criada"] == "Categoria do piloto"
    assert trilha["categoria.editada"] == "Renomear"
    assert trilha["categoria.desativada"] == "Pausa"
    assert trilha["categoria.excluida"] == "Limpeza do teste"


def test_categoria_duplicada_motivo_obrigatorio_e_id_ruim(amb):  # noqa: F811
    adm = amb.h("administrador")
    ok = amb.cliente.post(
        f"{BASE}/categorias", json={"nome": "Montagem de móveis", "motivo": "Piloto"}, headers=adm
    )
    assert ok.status_code == 201
    repetida = amb.cliente.post(
        f"{BASE}/categorias", json={"nome": "Montagem de móveis", "motivo": "Piloto"}, headers=adm
    )
    assert repetida.status_code == 409
    sem_motivo = amb.cliente.post(f"{BASE}/categorias", json={"nome": "Sem motivo"}, headers=adm)
    assert sem_motivo.status_code == 422
    curto = amb.cliente.post(
        f"{BASE}/categorias", json={"nome": "Motivo curto", "motivo": "x"}, headers=adm
    )
    assert curto.status_code == 422
    assert (
        amb.cliente.patch(
            f"{BASE}/categorias/nao-e-uuid", json={"ativa": False, "motivo": "teste"}, headers=adm
        ).status_code
        == 404
    )


def test_categoria_com_pedido_nao_pode_ser_excluida(amb):  # noqa: F811
    adm = amb.h("administrador")
    (pintura,) = amb.sql("select id from public.categorias where slug = 'pintura'")[0]
    r = amb.cliente.delete(
        f"{BASE}/categorias/{pintura}", params={"motivo": "Tentativa indevida"}, headers=adm
    )
    assert r.status_code == 409 and "desativ" in r.json()["detail"].lower()
    assert amb.sql("select count(*) from public.categorias where slug = 'pintura'") == [(1,)]


def test_so_quem_tem_permissao_mexe_em_categoria_e_cidade(amb):  # noqa: F811
    corpo = {"nome": "Intrusa", "motivo": "Teste de permissão"}
    for papel in ("atendente_n1", "financeiro", "cadastro", "mediador", "seguranca", "dpo"):
        r = amb.cliente.post(f"{BASE}/categorias", json=corpo, headers=amb.h(papel))
        assert r.status_code == 403, papel
        r = amb.cliente.post(
            f"{BASE}/cidades",
            json={"nome": "Intrusa", "uf": "MG", "motivo": "Teste de permissão"},
            headers=amb.h(papel),
        )
        assert r.status_code == 403, papel
    sem_login = amb.cliente.post(f"{BASE}/categorias", json=corpo)
    assert sem_login.status_code in (401, 403)
    assert amb.sql("select count(*) from public.categorias where nome = 'Intrusa'") == [(0,)]


# --- Cidades -------------------------------------------------------------------------------------


def test_cidade_criar_duplicada_e_desativar(amb):  # noqa: F811
    adm = amb.h("administrador")
    r = amb.cliente.post(
        f"{BASE}/cidades",
        json={"nome": "Belo Horizonte", "uf": "mg", "motivo": "Cidade do piloto"},
        headers=adm,
    )
    assert r.status_code == 201, r.text
    cidade = r.json()
    assert cidade["uf"] == "MG" and cidade["ativa"] is True

    repetida = amb.cliente.post(
        f"{BASE}/cidades",
        json={"nome": "belo horizonte", "uf": "MG", "motivo": "Cidade do piloto"},
        headers=adm,
    )
    assert repetida.status_code == 409

    r = amb.cliente.patch(
        f"{BASE}/cidades/{cidade['id']}",
        json={"ativa": False, "motivo": "Piloto fechado"},
        headers=adm,
    )
    assert r.status_code == 200 and r.json()["ativa"] is False
    assert amb.sql("select ativa from public.cidades where id = %s", cidade["id"]) == [(False,)]
    assert (
        amb.cliente.patch(
            f"{BASE}/cidades/nao-e-uuid", json={"ativa": True, "motivo": "teste"}, headers=adm
        ).status_code
        == 404
    )
    trilha = _auditoria(amb, "cidade.")
    assert trilha["cidade.criada"] == "Cidade do piloto"


# --- Status de usuário ---------------------------------------------------------------------------


def test_administrador_bloqueia_e_reativa_usuario(amb):  # noqa: F811
    adm = amb.h("administrador")
    uid = amb.ids["Maria Cliente"]
    r = amb.cliente.post(
        f"{BASE}/usuarios/{uid}/status",
        json={"status": "bloqueado", "motivo": "Fraude suspeita"},
        headers=adm,
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "bloqueado"
    assert amb.sql("select status from public.usuarios where id = %s", uid) == [("bloqueado",)]
    assert (
        _auditoria(amb, "usuario.status_alterado")["usuario.status_alterado"] == "Fraude suspeita"
    )

    r = amb.cliente.post(
        f"{BASE}/usuarios/{uid}/status",
        json={"status": "ativo", "motivo": "Revisão concluída"},
        headers=adm,
    )
    assert r.status_code == 200 and r.json()["status"] == "ativo"
    assert amb.sql("select status from public.usuarios where id = %s", uid) == [("ativo",)]


def test_status_de_usuario_valida_entrada_e_existencia(amb):  # noqa: F811
    adm = amb.h("administrador")
    uid = amb.ids["Maria Cliente"]
    url = f"{BASE}/usuarios/{uid}/status"
    assert (
        amb.cliente.post(
            url, json={"status": "banido", "motivo": "Motivo valido"}, headers=adm
        ).status_code
        == 422
    )
    assert amb.cliente.post(url, json={"status": "bloqueado"}, headers=adm).status_code == 422
    assert (
        amb.cliente.post(url, json={"status": "bloqueado", "motivo": "x"}, headers=adm).status_code
        == 422
    )
    inexistente = f"{BASE}/usuarios/00000000-0000-0000-0000-000000000000/status"
    assert (
        amb.cliente.post(
            inexistente, json={"status": "bloqueado", "motivo": "Motivo valido"}, headers=adm
        ).status_code
        == 404
    )
    assert amb.sql("select status from public.usuarios where id = %s", uid) == [("ativo",)]


def test_so_administrador_altera_status_de_usuario(amb):  # noqa: F811
    uid = amb.ids["Maria Cliente"]
    for papel in ("atendente_n1", "financeiro", "cadastro", "mediador", "seguranca", "dpo"):
        r = amb.cliente.post(
            f"{BASE}/usuarios/{uid}/status",
            json={"status": "bloqueado", "motivo": "Tentativa sem permissão"},
            headers=amb.h(papel),
        )
        assert r.status_code == 403, papel
    assert amb.sql("select status from public.usuarios where id = %s", uid) == [("ativo",)]
