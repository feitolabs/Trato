"""Migrations 20261126231800 (PDF no bucket `pedido-midias`) e 20261126231900 (atendente_n2 sem
a mídia de nota contestada, Termos 6.9).

São regras de armazenamento e de leitura direta (RLS): o backend usa `service_role` e não passa
por elas, por isso não entram no `pg_local.py`. Aqui a cadeia INTEIRA de migrations roda num
Postgres local descartável, como em `supabase/testes/banco_local.py`.
"""

from __future__ import annotations

import json
import uuid

import psycopg
import pytest

from .pg_local import RAIZ, _reaproveitar_do_banco_local

pytestmark = pytest.mark.integracao

PDF = "20261126231800_pedido_midias_aceita_pdf"
N2 = "20261126231900_n2_sem_midia_nota_contestada"
# nome -> (finalidade, é prova ou foto de nota contestada)
MIDIAS = {
    "foto_da_nota_contestada": ("nota_material", True),
    "foto_de_outra_nota": ("nota_material", False),
    "prova_em_disputa": ("disputa", True),
    "prova_comum": ("depois", True),
    "disputa_sem_contestacao": ("disputa", False),
}


def _sql(nome: str, pasta: str = "migrations") -> str:
    sufixo = "_rollback" if pasta == "rollback" else ""
    return (RAIZ / "supabase" / pasta / f"{nome}{sufixo}.sql").read_text(encoding="utf-8")


def _tipos(con) -> dict[str, tuple]:
    linhas = con.execute(
        "select id, allowed_mime_types, file_size_limit from storage.buckets"
    ).fetchall()
    return {x[0]: (list(x[1]), x[2]) for x in linhas}


def _semear(con) -> tuple[dict[str, str], dict[str, str]]:
    """Linhas mínimas, sem as chaves estrangeiras (os CHECKs continuam valendo)."""
    pessoas = {p: str(uuid.uuid4()) for p in ("autor", "atendente_n2", "mediador")}
    midias = {nome: str(uuid.uuid4()) for nome in MIDIAS}
    con.execute("set session_replication_role = replica")
    for nome, uid in pessoas.items():
        con.execute("insert into auth.users (id) values (%s)", (uid,))
        con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, nome))
    for papel in ("atendente_n2", "mediador"):
        con.execute(
            "insert into public.equipe (usuario_id, papel) values (%s, %s)", (pessoas[papel], papel)
        )
    pedido = str(uuid.uuid4())
    for nome, (finalidade, _) in MIDIAS.items():
        con.execute(
            "insert into public.midias (id, pedido_id, enviada_por, finalidade, storage_path) "
            "values (%s, %s, %s, %s, %s)",
            (midias[nome], pedido, pessoas["autor"], finalidade, f"{pedido}/{nome}.jpg"),
        )
        con.execute(
            "insert into storage.objects (bucket_id, name) values ('pedido-midias', %s)",
            (f"{pedido}/{nome}.jpg",),
        )
    notas = {}
    for nome in ("foto_da_nota_contestada", "foto_de_outra_nota"):
        notas[nome] = con.execute(
            "insert into public.notas_material (contrato_id, enviada_por, midia_id, "
            "total_centavos) values (%s, %s, %s, 100) returning id",
            (str(uuid.uuid4()), pessoas["autor"], midias[nome]),
        ).fetchone()[0]
    # um anexo vai sem hífens e o outro com: a regra aceita os dois
    anexos = [midias["prova_em_disputa"].replace("-", ""), midias["prova_comum"]]
    con.execute(
        "insert into public.nota_material_contestacoes (protocolo, nota_id, cliente_id, motivo, "
        "descricao, anexos, valor_contestado_centavos, responder_ate) values "
        "('CNM-2026-000001', %s, %s, 'nao_comprovado', 'Sem comprovante.', %s::jsonb, 100, "
        "now() + interval '5 days')",
        (notas["foto_da_nota_contestada"], pessoas["autor"], json.dumps(anexos)),
    )
    con.execute("set session_replication_role = origin")
    return pessoas, midias


@pytest.fixture(scope="module")
def banco(tmp_path_factory):
    pgserver = pytest.importorskip("pgserver")
    ref = _reaproveitar_do_banco_local()
    servidor = pgserver.get_server(tmp_path_factory.mktemp("pg_midia"), cleanup_mode="delete")
    con = psycopg.connect(servidor.get_uri(), autocommit=True)
    try:
        con.execute(ref["STUBS"])
        # O auth.users do Supabase tem estas colunas; o stub só tem id (como no pg_local).
        con.execute("alter table auth.users add column if not exists email text")
        con.execute("alter table auth.users add column if not exists last_sign_in_at timestamptz")
        con.execute("alter table auth.users add column if not exists raw_user_meta_data jsonb")
        con.execute(ref["PADROES"]["real"])
        antes: dict = {}
        for arquivo in sorted((RAIZ / "supabase" / "migrations").glob("*.sql")):
            if arquivo.stem == PDF:  # retrato de como estava antes das duas
                antes["buckets"] = _tipos(con)
                antes["pessoas"], antes["midias"] = _semear(con)
                antes["visao"] = _visao(con, antes["pessoas"]["atendente_n2"], antes["midias"])
            sql = arquivo.read_text(encoding="utf-8")
            if "f32_identidade" in arquivo.name:
                sql = ref["sem_btree_gist"](sql)
            con.execute(sql)
            if "revogar_execute" in arquivo.name:
                con.execute(
                    "alter default privileges in schema public "
                    "revoke execute on functions from public"
                )
        yield con, antes
    finally:
        con.close()
        servidor.cleanup()


def _visao(con, usuario: str, midias: dict[str, str]) -> dict[str, tuple[bool, bool]]:
    """(vê a linha em `midias`, vê o arquivo no armazenamento) como `authenticated`."""
    with con.transaction():
        con.execute("select set_config('request.jwt.claim.sub', %s, true)", (usuario,))
        con.execute("set local role authenticated")
        linhas = {str(x[0]) for x in con.execute("select id from public.midias").fetchall()}
        arquivos = {x[0] for x in con.execute("select name from storage.objects").fetchall()}
    return {
        nome: (mid in linhas, any(a.endswith(f"/{nome}.jpg") for a in arquivos))
        for nome, mid in midias.items()
    }


def test_pdf_entra_so_no_bucket_do_pedido_e_pode_ser_desfeito(banco):
    con, antes = banco
    original = antes["buckets"]
    tipos, limite = original["pedido-midias"]
    assert "application/pdf" not in tipos
    esperado = original | {"pedido-midias": ([*tipos, "application/pdf"], limite)}
    assert _tipos(con) == esperado
    con.execute(_sql(PDF))  # repetir não duplica
    assert _tipos(con) == esperado
    con.execute(_sql(PDF, "rollback"))
    assert _tipos(con) == original
    con.execute(_sql(PDF))
    assert _tipos(con) == esperado


def test_atendente_n2_deixa_de_ver_a_midia_da_contestacao(banco):
    con, antes = banco
    pessoas, midias = antes["pessoas"], antes["midias"]
    tudo = {nome: (True, True) for nome in MIDIAS}
    restrita = {nome: (not contestada,) * 2 for nome, (_, contestada) in MIDIAS.items()}
    assert antes["visao"] == tudo  # o que a migration muda
    for _ in range(2):  # aplicada pela cadeia e repetida
        assert _visao(con, pessoas["atendente_n2"], midias) == restrita
        assert _visao(con, pessoas["mediador"], midias) == tudo
        assert _visao(con, pessoas["autor"], midias) == tudo
        con.execute(_sql(N2))
    con.execute(_sql(N2, "rollback"))
    assert _visao(con, pessoas["atendente_n2"], midias) == tudo
    con.execute(_sql(N2))
    assert _visao(con, pessoas["atendente_n2"], midias) == restrita
