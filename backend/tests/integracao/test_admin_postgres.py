"""API administrativa contra o Postgres LOCAL descartável (pgserver). Nunca toca no Supabase.

Usa um banco próprio (não o `cenario` compartilhado): publicar versões de configuração aqui não
pode mudar o que os outros testes de integração enxergam.
"""

from __future__ import annotations

import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import pytest

pytest.importorskip("pgserver", reason="pgserver não instalado: integração com Postgres pulada")
pytest.importorskip("psycopg")

import jwt  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from pydantic import SecretStr  # noqa: E402

from trato.api import criar_app  # noqa: E402
from trato.api.admin import instalar_admin  # noqa: E402
from trato.api.admin.postgres import criar_admin_postgres  # noqa: E402
from trato.api.fabrica import criar_contexto_postgres  # noqa: E402
from trato.config import Config  # noqa: E402
from trato.persistencia.conexao import Banco  # noqa: E402
from trato.persistencia.erros import ErroPersistencia  # noqa: E402

from .pg_local import BancoLocal  # noqa: E402

BASE = "/v1/admin"
DEFINICOES = (  # (chave, unidade, mínimo, máximo, escopos)
    ("adiantamento_bps", "bps", 0, 10_000, ["global"]),
    ("prazo_resposta_disputa_horas", "horas", 1, 240, ["global"]),
    ("prazo_decisao_disputa_dias_uteis", "dias_uteis", 1, 30, ["global"]),
    ("prazo_congelar_disputa_horas", "horas", 1, 720, ["global"]),
    ("validade_pedido_horas", "horas", 1, 720, ["global", "cidade"]),
)
PARAMETROS = [
    {"chave": "adiantamento_bps", "valor": 3000},
    {"chave": "prazo_resposta_disputa_horas", "valor": 48},
    {"chave": "prazo_decisao_disputa_dias_uteis", "valor": 5},
    {"chave": "prazo_congelar_disputa_horas", "valor": 72},
]
FAIXAS = [
    {"de_centavos": 0, "ate_centavos": 100_000, "taxa_bps": 750},
    {"de_centavos": 100_000, "ate_centavos": None, "taxa_bps": 600},
]  # valores de TESTE
PAPEIS = ("administrador", "financeiro", "cadastro", "dpo", "seguranca", "mediador", "atendente_n1")


class AssinadorFalso:
    def __init__(self) -> None:
        self.chamadas: list[tuple[str, int]] = []

    def assinar(self, caminho: str, segundos: int) -> str:
        self.chamadas.append((caminho, segundos))
        return f"https://storage.exemplo.test/assinada?exp={segundos}"


@dataclass
class Ambiente:
    local: BancoLocal
    banco: Banco
    cliente: TestClient
    ids: dict[str, str]
    segredo: str
    assinador: AssinadorFalso

    def h(self, quem: str) -> dict[str, str]:
        carga = {
            "sub": self.ids[quem],
            "aud": "authenticated",
            "exp": datetime.now(UTC) + timedelta(hours=1),
        }
        return {"Authorization": f"Bearer {jwt.encode(carga, self.segredo, 'HS256')}"}

    def sql(self, comando: str, *params):
        with self.local.admin() as con:
            cur = con.execute(comando, params)
            return cur.fetchall() if cur.description else None


def _novo_usuario(con, ids: dict[str, str], nome: str) -> str:
    ids[nome] = str(uuid.uuid4())
    con.execute("insert into auth.users (id) values (%s)", (ids[nome],))
    con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (ids[nome], nome))
    return ids[nome]


@pytest.fixture(scope="module")
def amb(tmp_path_factory) -> Ambiente:
    try:
        local = BancoLocal(tmp_path_factory.mktemp("pg_admin"))
    except Exception as erro:  # noqa: BLE001
        pytest.skip(f"Postgres local indisponível: {erro}")
    ids: dict[str, str] = {}
    with local.admin() as con:
        for papel in PAPEIS:
            _novo_usuario(con, ids, papel)
            con.execute(
                "insert into public.equipe (usuario_id, papel, alcada_centavos) values (%s, %s, %s)",
                (ids[papel], papel, 200_000 if papel == "mediador" else None),
            )
        _novo_usuario(con, ids, "administrador2")
        con.execute(
            "insert into public.equipe (usuario_id, papel) values (%s, 'administrador')",
            (ids["administrador2"],),
        )
        _novo_usuario(con, ids, "revogavel")
        con.execute(
            "insert into public.equipe (usuario_id, papel) values (%s, 'administrador')",
            (ids["revogavel"],),
        )
        _novo_usuario(con, ids, "bloqueado")
        con.execute("update public.usuarios set status = 'bloqueado' where nome = 'bloqueado'")
        con.execute(
            "insert into public.equipe (usuario_id, papel) values (%s, 'administrador')",
            (ids["bloqueado"],),
        )
        for nome in ("Maria Cliente", "50% Desconto", "pro1", "pro2"):
            _novo_usuario(con, ids, nome)
        for pro in ("pro1", "pro2"):
            con.execute(
                "insert into public.perfis_profissional (usuario_id) values (%s)", (ids[pro],)
            )
        con.execute(
            "insert into public.usuarios_privados (usuario_id, cpf, telefone) values "
            "(%s, '123.456.789-09', '+5531999990000'), (%s, '987.654.321-00', null)",
            (ids["Maria Cliente"], ids["pro1"]),
        )
        for v, pro in (("v1", "pro1"), ("v2", "pro2")):
            ids[v] = str(
                con.execute(
                    "insert into public.verificacoes (profissional_id, nivel_solicitado, "
                    "consentimento_lgpd_em) values (%s, 'verificado', now()) returning id",
                    (ids[pro],),
                ).fetchone()[0]
            )
        ids["doc"] = str(
            con.execute(
                "insert into public.verificacao_documentos (verificacao_id, tipo, storage_path) "
                "values (%s, 'documento_frente', 'privado/pro1/frente.jpg') returning id",
                (ids["v1"],),
            ).fetchone()[0]
        )
        for chave, unidade, minimo, maximo, escopos in DEFINICOES:
            con.execute(
                "insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, "
                "escopos_permitidos) values (%s, %s, %s, %s, %s, %s)",
                (chave, chave, unidade, minimo, maximo, escopos),
            )
        cidade = con.execute(
            "insert into public.cidades (nome, uf, ativa) values ('Cidade Teste', 'MG', true) "
            "returning id"
        ).fetchone()[0]
        categoria = con.execute(
            "insert into public.categorias (nome, slug) values ('Pintura', 'pintura') returning id"
        ).fetchone()[0]
        for titulo, cliente in (
            ("Pintar a sala", "Maria Cliente"),
            ("Troca de torneira", "50% Desconto"),
        ):
            con.execute(
                "insert into public.pedidos (cliente_id, categoria_id, cidade_id, titulo, descricao) "
                "values (%s, %s, %s, %s, 'descrição')",
                (ids[cliente], categoria, cidade, titulo),
            )

    segredo = secrets.token_hex(32)
    config = Config(
        _env_file=None,
        trato_codigo_segredo=SecretStr(secrets.token_hex(16)),
        supabase_jwt_secret=SecretStr(segredo),
    )
    banco = Banco(local.uri, papel="service_role")
    contexto = criar_contexto_postgres(banco, config)
    assinador = AssinadorFalso()
    app = criar_app(contexto)
    instalar_admin(app, criar_admin_postgres(banco, assinador))
    yield Ambiente(local, banco, TestClient(app), ids, segredo, assinador)
    banco.fechar()
    local.fechar()


# --- Papel vem do banco ----------------------------------------------------------------------------


def test_papel_errado_e_403_com_jwt_real(amb):
    rotas = [
        ("get", "/verificacoes", "financeiro"),
        ("get", "/disputas", "cadastro"),
        ("get", "/pagamentos", "cadastro"),
        ("get", "/config/vigente", "cadastro"),
        ("get", "/auditoria", "financeiro"),
        ("get", "/usuarios", "financeiro"),
    ]
    for metodo, caminho, quem in rotas:
        r = getattr(amb.cliente, metodo)(BASE + caminho, headers=amb.h(quem))
        assert r.status_code == 403, (caminho, quem, r.status_code)
    assert amb.cliente.get(BASE + "/usuarios", headers=amb.h("cadastro")).status_code == 200


def test_cliente_e_conta_bloqueada_ou_sem_token_nao_entram(amb):
    assert amb.cliente.get(BASE + "/usuarios", headers=amb.h("Maria Cliente")).status_code == 403
    assert amb.cliente.get(BASE + "/usuarios", headers=amb.h("bloqueado")).status_code == 401
    assert amb.cliente.get(BASE + "/usuarios").status_code == 401


def test_papel_revogado_perde_o_acesso_na_hora(amb):
    assert amb.cliente.get(BASE + "/auditoria", headers=amb.h("revogavel")).status_code == 200
    amb.sql(
        "update public.equipe set revogado_em = now() where usuario_id = %s", amb.ids["revogavel"]
    )
    try:
        assert amb.cliente.get(BASE + "/auditoria", headers=amb.h("revogavel")).status_code == 403
    finally:
        amb.sql(
            "update public.equipe set revogado_em = null where usuario_id = %s",
            amb.ids["revogavel"],
        )
    amb.sql("update public.equipe set ativo = false where usuario_id = %s", amb.ids["revogavel"])
    try:
        assert amb.cliente.get(BASE + "/auditoria", headers=amb.h("revogavel")).status_code == 403
    finally:
        amb.sql("update public.equipe set ativo = true where usuario_id = %s", amb.ids["revogavel"])
    assert amb.cliente.get(BASE + "/auditoria", headers=amb.h("revogavel")).status_code == 200


def test_o_papel_do_token_nao_vale_so_o_do_banco(amb):
    carga = {
        "sub": amb.ids["Maria Cliente"], "aud": "authenticated", "role": "administrador",
        "app_metadata": {"papel": "administrador"},
        "exp": datetime.now(UTC) + timedelta(hours=1),
    }  # fmt: skip
    h = {"Authorization": f"Bearer {jwt.encode(carga, amb.segredo, 'HS256')}"}
    assert amb.cliente.get(BASE + "/auditoria", headers=h).status_code == 403


# --- Verificação -----------------------------------------------------------------------------------


def test_fila_detalhe_url_assinada_e_decisao(amb):
    cad = amb.h("cadastro")
    fila = amb.cliente.get(BASE + "/verificacoes", headers=cad).json()
    assert fila["total"] == 2 and {v["profissional_nome"] for v in fila["itens"]} == {
        "pro1",
        "pro2",
    }
    det = amb.cliente.get(f"{BASE}/verificacoes/{amb.ids['v1']}", headers=cad)
    assert det.json()["cpf_mascarado"] == "***.***.***-00"
    assert "privado/pro1" not in det.text and "987.654" not in det.text
    assert amb.cliente.get(f"{BASE}/verificacoes/nao-uuid", headers=cad).status_code == 404

    url = f"{BASE}/verificacoes/{amb.ids['v1']}/documentos/{amb.ids['doc']}/url"
    assert amb.cliente.post(url, json={}, headers=cad).status_code == 422
    assert (
        amb.cliente.post(
            url, json={"motivo": "Conferir"}, headers=amb.h("administrador")
        ).status_code
        == 403
    )
    r = amb.cliente.post(url, json={"motivo": "Conferir frente do RG"}, headers=cad)
    assert r.status_code == 200 and r.json()["expira_em_segundos"] == 60
    assert amb.assinador.chamadas[-1] == ("privado/pro1/frente.jpg", 60)
    linha = amb.sql(
        "select ator_tipo, motivo, depois::text from public.auditoria where acao = 'dado_pessoal.documento_revelado'"
    )
    assert linha[0][0] == "equipe" and linha[0][1] == "Conferir frente do RG"
    assert "privado/pro1" not in linha[0][2]


def test_decisao_atualiza_verificacao_perfil_e_auditoria_juntos(amb):
    cad = amb.h("cadastro")
    decisao = f"{BASE}/verificacoes/{amb.ids['v1']}/decisao"
    assert amb.cliente.post(decisao, json={"aprovar": True}, headers=cad).status_code == 422

    r = amb.cliente.post(
        decisao, json={"aprovar": True, "motivo": "Documentos conferem"}, headers=cad
    )

    assert r.status_code == 200 and r.json()["status"] == "aprovada"
    perfil = amb.sql(
        "select status, nivel_verificacao from public.perfis_profissional where usuario_id = %s",
        amb.ids["pro1"],
    )
    assert perfil == [("aprovado", "verificado")]
    ver = amb.sql(
        "select status, analista_id::text, decidida_em is not null from public.verificacoes where id = %s",
        amb.ids["v1"],
    )
    assert ver == [("aprovada", amb.ids["cadastro"], True)]
    aud = amb.sql(
        "select acao, motivo, entidade_id::text from public.auditoria where acao = 'verificacao.aprovada'"
    )
    assert aud == [("verificacao.aprovada", "Documentos conferem", amb.ids["v1"])]
    assert (
        amb.cliente.post(
            decisao, json={"aprovar": False, "motivo": "Mudei de ideia"}, headers=cad
        ).status_code
        == 409
    )

    recusa = f"{BASE}/verificacoes/{amb.ids['v2']}/decisao"
    r = amb.cliente.post(recusa, json={"aprovar": False, "motivo": "Selfie ilegível"}, headers=cad)
    assert r.json()["status"] == "recusada"
    assert amb.sql(
        "select status from public.perfis_profissional where usuario_id = %s", amb.ids["pro2"]
    ) == [("recusado",)]
    fila = amb.cliente.get(BASE + "/verificacoes", headers=cad).json()
    assert fila["total"] == 0


# --- Usuários e pedidos ----------------------------------------------------------------------------


def test_busca_de_usuarios_trata_curinga_como_texto(amb):
    n1 = amb.h("atendente_n1")
    r = amb.cliente.get(BASE + "/usuarios?q=maria", headers=n1).json()
    assert [u["nome"] for u in r["itens"]] == ["Maria Cliente"] and r["itens"][0][
        "tipo"
    ] == "cliente"
    assert (
        amb.cliente.get(BASE + "/usuarios?q=%25%25", headers=n1).json()["total"] == 0
    )  # "%%" literal
    assert amb.cliente.get(BASE + "/usuarios?q=50%25", headers=n1).json()["total"] == 1
    por_id = amb.cliente.get(f"{BASE}/usuarios?q={amb.ids['administrador']}", headers=n1).json()
    assert por_id["itens"][0]["tipo"] == "equipe"
    pro = amb.cliente.get(f"{BASE}/usuarios/{amb.ids['pro1']}", headers=n1).json()
    assert pro["tipo"] == "profissional" and pro["nivel_verificacao"] == "verificado"
    assert amb.cliente.get(f"{BASE}/usuarios/nao-uuid", headers=n1).status_code == 404
    assert "123.456" not in amb.cliente.get(f"{BASE}/usuarios?q=maria", headers=n1).text


def test_dados_pessoais_so_com_motivo_e_ficam_na_auditoria(amb):
    url = f"{BASE}/usuarios/{amb.ids['Maria Cliente']}/dados-pessoais"
    assert amb.cliente.post(url, json={}, headers=amb.h("dpo")).status_code == 422
    assert (
        amb.cliente.post(
            url, json={"motivo": "Pedido do titular"}, headers=amb.h("atendente_n1")
        ).status_code
        == 403
    )
    antes = amb.sql("select count(*) from public.auditoria where acao = 'dado_pessoal.revelado'")[
        0
    ][0]
    assert antes == 0  # as tentativas recusadas não deixaram rastro falso

    r = amb.cliente.post(url, json={"motivo": "Pedido do titular nº 42"}, headers=amb.h("dpo"))

    assert r.status_code == 200 and r.json()["cpf"] == "123.456.789-09"
    linha = amb.sql(
        "select ator_id::text, motivo, depois::text from public.auditoria where acao = 'dado_pessoal.revelado'"
    )
    assert linha[0][0] == amb.ids["dpo"] and linha[0][1] == "Pedido do titular nº 42"
    assert "123.456" not in linha[0][2]
    inexistente = f"{BASE}/usuarios/{uuid.uuid4()}/dados-pessoais"
    assert (
        amb.cliente.post(
            inexistente, json={"motivo": "Teste de 404"}, headers=amb.h("dpo")
        ).status_code
        == 404
    )
    assert (
        amb.cliente.post(
            f"{BASE}/usuarios/xx/dados-pessoais",
            json={"motivo": "Teste de 404"},
            headers=amb.h("dpo"),
        ).status_code
        == 404
    )


def test_busca_de_pedidos(amb):
    n1 = amb.h("atendente_n1")
    todos = amb.cliente.get(BASE + "/pedidos", headers=n1).json()
    assert todos["total"] == 2
    sala = amb.cliente.get(BASE + "/pedidos?q=sala", headers=n1).json()
    assert [p["titulo"] for p in sala["itens"]] == ["Pintar a sala"]
    assert (
        sala["itens"][0]["cliente_nome"] == "Maria Cliente"
        and sala["itens"][0]["estado"] == "aberto"
    )
    por_cliente = amb.cliente.get(
        f"{BASE}/pedidos?cliente_id={amb.ids['Maria Cliente']}", headers=n1
    ).json()
    assert por_cliente["total"] == 1
    assert amb.cliente.get(BASE + "/pedidos?estado=concluido", headers=n1).json()["total"] == 0
    assert amb.cliente.get(BASE + "/pedidos?cliente_id=xx", headers=n1).json()["total"] == 0
    detalhe = amb.cliente.get(f"{BASE}/pedidos/{sala['itens'][0]['id']}", headers=n1)
    assert detalhe.status_code == 200 and detalhe.json()["cliente"]["nome"] == "Maria Cliente"


# --- Configuração ------------------------------------------------------------------------------------


def passo(amb, versao_id, acao, quem, corpo=None):
    corpo = corpo or {"motivo": "Conferi a proposta e os números"}
    return amb.cliente.post(
        f"{BASE}/config/versoes/{versao_id}/{acao}", json=corpo, headers=amb.h(quem)
    )


def criar(amb, quem="financeiro", **corpo):
    base = {
        "motivo": "Versão inicial",
        "parametros": PARAMETROS,
        "faixas": FAIXAS,
        "partir_da_vigente": False,
    }
    return amb.cliente.post(f"{BASE}/config/versoes", json=base | corpo, headers=amb.h(quem))


def test_config_ciclo_completo_e_regras_do_banco(amb):
    fin = amb.h("financeiro")
    assert amb.cliente.get(BASE + "/config/vigente", headers=fin).status_code == 404
    assert len(amb.cliente.get(BASE + "/config/definicoes", headers=fin).json()) == 5

    # Valores fora dos limites do catálogo e faixas sobrepostas são recusados, sem deixar lixo.
    assert (
        criar(
            amb, parametros=[{"chave": "prazo_resposta_disputa_horas", "valor": 9999}]
        ).status_code
        == 422
    )
    sobrepostas = [
        {"de_centavos": 0, "ate_centavos": 200, "taxa_bps": 750},
        {"de_centavos": 100, "ate_centavos": None, "taxa_bps": 600},
    ]
    assert criar(amb, faixas=sobrepostas).status_code == 422
    assert amb.sql("select count(*) from public.config_versoes")[0][0] == 0

    v1 = criar(amb).json()
    assert v1["status"] == "rascunho" and len(v1["parametros"]) == 4 and len(v1["faixas"]) == 2
    assert passo(amb, v1["id"], "aprovar", "administrador").status_code == 409  # ainda é rascunho
    assert passo(amb, v1["id"], "enviar", "financeiro").json()["status"] == "aguardando_aprovacao"
    assert passo(amb, v1["id"], "aprovar", "financeiro").status_code == 403  # sem o papel
    assert (
        passo(amb, v1["id"], "publicar", "administrador").status_code == 409
    )  # ainda não aprovada
    aprovada = passo(amb, v1["id"], "aprovar", "administrador").json()
    assert aprovada["status"] == "aprovada" and aprovada["vigente_desde"] is not None
    assert passo(amb, v1["id"], "publicar", "administrador").json()["status"] == "vigente"
    assert amb.cliente.get(BASE + "/config/vigente", headers=fin).json()["id"] == v1["id"]

    # A versão publicada é imutável, inclusive para o service_role no banco.
    with pytest.raises(ErroPersistencia):
        with amb.banco.transacao() as con:
            con.execute(
                "update public.config_parametros set valor = 1 where versao_id = %s", (v1["id"],)
            )
    with pytest.raises(ErroPersistencia):
        with amb.banco.transacao() as con:
            con.execute(
                "update public.config_versoes set motivo = 'reescrito' where id = %s", (v1["id"],)
            )
    descartar = amb.cliente.request(
        "DELETE",
        f"{BASE}/config/versoes/{v1['id']}",
        json={"motivo": "Apagar a vigente"},
        headers=fin,
    )
    assert descartar.status_code == 409

    # Nova versão a partir da vigente: quem propõe não aprova (nem o administrador).
    v2 = criar(amb, quem="administrador", partir_da_vigente=True, motivo="Resposta mais rápida", faixas=[],
               parametros=[{"chave": "prazo_resposta_disputa_horas", "valor": 24}]).json()  # fmt: skip
    assert len(v2["parametros"]) == 4 and len(v2["faixas"]) == 2
    passo(amb, v2["id"], "enviar", "administrador")
    assert passo(amb, v2["id"], "aprovar", "administrador").status_code == 403
    assert passo(amb, v2["id"], "aprovar", "administrador2").status_code == 200
    assert passo(amb, v2["id"], "publicar", "administrador2").status_code == 200
    historico = {
        v["numero"]: v["status"]
        for v in amb.cliente.get(BASE + "/config/versoes", headers=fin).json()
    }
    assert historico == {1: "substituida", 2: "vigente"}
    assert amb.sql("select count(*) from public.config_versoes where status = 'vigente'")[0][0] == 1

    # Reverter = nova versão (3) copiando a 1; precisa de aprovação e publicação como as outras.
    v3 = passo(amb, v1["id"], "reverter", "financeiro", {"motivo": "Prazo menor gerou reclamações"})
    assert v3.status_code == 201 and v3.json()["revertida_de"] == v1["id"]
    assert v3.json()["status"] == "aguardando_aprovacao"
    assert passo(amb, v3.json()["id"], "aprovar", "administrador").status_code == 200
    assert passo(amb, v3.json()["id"], "publicar", "administrador").status_code == 200
    historico = {
        v["numero"]: v["status"]
        for v in amb.cliente.get(BASE + "/config/versoes", headers=fin).json()
    }
    assert historico == {1: "substituida", 2: "revertida", 3: "vigente"}
    vigente = amb.cliente.get(BASE + "/config/vigente", headers=fin).json()
    assert {p["chave"]: p["valor"] for p in vigente["parametros"]}[
        "prazo_resposta_disputa_horas"
    ] == 48
    assert [f["taxa_bps"] for f in vigente["faixas"]] == [750, 600]
    assert amb.cliente.get(f"{BASE}/config/versoes/nao-uuid", headers=fin).status_code == 404

    acoes = [
        a
        for (a,) in amb.sql(
            "select acao from public.auditoria where acao like 'config.%%' order by id"
        )
    ]
    assert acoes.count("config.publicada") == 3 and acoes.count("config.aprovada") == 3
    assert "config.reversao_proposta" in acoes


def test_config_incompleta_e_agendada_nao_publica(amb):
    fin = amb.h("financeiro")
    sem_chave = [p for p in PARAMETROS if p["chave"] != "prazo_congelar_disputa_horas"]
    incompleta = criar(amb, parametros=sem_chave).json()
    r = passo(amb, incompleta["id"], "enviar", "financeiro")
    assert r.status_code == 422 and "prazo_congelar_disputa_horas" in r.text
    buraco = [
        {"de_centavos": 0, "ate_centavos": 100, "taxa_bps": 750},
        {"de_centavos": 200, "ate_centavos": None, "taxa_bps": 600},
    ]
    com_buraco = criar(amb, faixas=buraco).json()
    assert passo(amb, com_buraco["id"], "enviar", "financeiro").status_code == 422

    futuro = (datetime.now(UTC) + timedelta(days=2)).isoformat()
    agendada = criar(amb, vigente_desde=futuro, motivo="Mudança agendada").json()
    passo(amb, agendada["id"], "enviar", "financeiro")
    passo(amb, agendada["id"], "aprovar", "administrador")
    assert passo(amb, agendada["id"], "publicar", "administrador").status_code == 409

    for sobra in (incompleta, com_buraco, agendada):
        corpo = {"motivo": "Limpando as sobras"}
        r = amb.cliente.request(
            "DELETE", f"{BASE}/config/versoes/{sobra['id']}", json=corpo, headers=fin
        )
        # a agendada já foi aprovada (imutável): não descarta; as outras são rascunho
        assert r.status_code == (409 if sobra is agendada else 204)
    assert (
        amb.sql(
            "select count(*) from public.config_parametros where versao_id = %s", incompleta["id"]
        )[0][0]
        == 0
    )


# --- Auditoria ---------------------------------------------------------------------------------------


def test_auditoria_filtros_e_cadeia_no_banco(amb):
    seg = amb.h("seguranca")
    tudo = amb.cliente.get(BASE + "/auditoria?limite=100", headers=seg).json()
    assert tudo["total"] > 5
    assert [i["id"] for i in tudo["itens"]] == sorted(
        (i["id"] for i in tudo["itens"]), reverse=True
    )
    config = amb.cliente.get(BASE + "/auditoria?acao=config.&limite=100", headers=seg).json()
    assert config["total"] > 0 and all(i["acao"].startswith("config.") for i in config["itens"])
    ator = amb.cliente.get(
        f"{BASE}/auditoria?ator_id={amb.ids['cadastro']}&limite=100", headers=seg
    ).json()
    assert ator["total"] > 0 and {i["ator_id"] for i in ator["itens"]} == {amb.ids["cadastro"]}
    assert amb.cliente.get(BASE + "/auditoria?ator_id=xx", headers=seg).json()["total"] == 0
    por_entidade = amb.cliente.get(
        f"{BASE}/auditoria?entidade=verificacoes&entidade_id={amb.ids['v1']}", headers=seg
    )
    assert por_entidade.json()["total"] == 2  # url do documento + aprovação
    futuro = (datetime.now(UTC) + timedelta(days=1)).isoformat().replace("+00:00", "Z")
    assert (
        amb.cliente.get(BASE + "/auditoria", params={"desde": futuro}, headers=seg).json()["total"]
        == 0
    )
    assert (
        amb.cliente.get(BASE + "/auditoria?acao=%25", headers=seg).json()["total"] == 0
    )  # "%%" literal

    ok = amb.cliente.post(BASE + "/auditoria/verificar-cadeia", headers=seg).json()
    assert ok["integra"] is True and ok["primeira_falha_id"] is None

    # Adultera uma linha DENTRO de uma transação que é desfeita: a verificação do banco acusa.
    with amb.local.admin() as con:
        con.autocommit = False
        con.execute("alter table public.auditoria disable trigger auditoria_imutavel")
        alvo = con.execute("select id from public.auditoria order by id limit 1").fetchone()[0]
        con.execute("update public.auditoria set motivo = 'reescrito' where id = %s", (alvo,))
        falha = con.execute("select public.verificar_cadeia_auditoria()").fetchone()[0]
        con.rollback()
    assert falha == alvo
    assert (
        amb.cliente.post(BASE + "/auditoria/verificar-cadeia", headers=seg).json()["integra"]
        is True
    )


def test_motivo_obrigatorio_tambem_no_banco_para_acao_sensivel(amb):
    # O banco recusa `dado_pessoal.*` sem motivo, mesmo que alguém esqueça de validar na API.
    from trato.api.admin.postgres import AuditoriaAdminPostgres
    from trato.persistencia.erros import RegraDoBanco

    with pytest.raises(RegraDoBanco):
        AuditoriaAdminPostgres(amb.banco).registrar(
            ator_id=amb.ids["dpo"], acao="dado_pessoal.revelado"
        )


def test_perfis_de_equipe_so_veem_o_que_o_papel_permite_nos_pagamentos_em_modo_postgres(amb):
    # Disputas, ledger e webhooks ainda são memória em modo postgres: as rotas respondem vazio, não 500.
    fin = amb.h("financeiro")
    assert amb.cliente.get(BASE + "/pagamentos", headers=fin).json()["total"] == 0
    assert (
        amb.cliente.get(BASE + "/pagamentos/resumo", headers=fin).json()["confirmado_centavos"] == 0
    )
    assert amb.cliente.get(BASE + "/disputas", headers=amb.h("mediador")).json()["total"] == 0
    assert amb.cliente.get(BASE + "/webhooks/eventos", headers=fin).json()["total"] == 0
