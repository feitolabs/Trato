"""Postgres LOCAL e descartável (pgserver) com as migrations do Trato. Nunca toca no Supabase.

Os stubs do que o Supabase já traz (schema auth, roles, storage) vêm de
`supabase/testes/banco_local.py`: lemos só as constantes dele (sem importar o psycopg2 dele).
"""

from __future__ import annotations

import ast
from pathlib import Path
from typing import Any

import psycopg

RAIZ = Path(__file__).resolve().parents[3]
# Migrations que a persistência usa (F3.5 e F3.6 ainda não valem; F3.8 é de RLS/app).
MIGRATIONS = ("f32_identidade", "revogar_execute", "f33_pedidos", "f34_execucao", "f37_chat")


def _reaproveitar_do_banco_local() -> dict[str, Any]:
    fonte = (RAIZ / "supabase" / "testes" / "banco_local.py").read_text(encoding="utf-8")
    nomes = {"STUBS", "PADROES", "sem_btree_gist"}
    pedaco = []
    for no in ast.parse(fonte).body:
        if isinstance(no, ast.Assign) and any(
            isinstance(a, ast.Name) and a.id in nomes for a in no.targets
        ):
            pedaco.append(no)
        elif isinstance(no, ast.FunctionDef) and no.name in nomes:
            pedaco.append(no)
    espaco: dict[str, Any] = {}
    exec(compile(ast.Module(pedaco, []), "banco_local", "exec"), espaco)  # noqa: S102
    return espaco


class BancoLocal:
    """Sobe o Postgres embutido, cria os stubs e aplica as migrations (como superusuário)."""

    def __init__(self, pasta: Path, nome: str = "pgdata") -> None:
        import pgserver  # importado aqui: sem ele os testes de integração são pulados

        ref = _reaproveitar_do_banco_local()
        self.servidor = pgserver.get_server(pasta / nome, cleanup_mode="delete")
        self.uri: str = self.servidor.get_uri()
        with self.admin() as con:
            con.execute(ref["STUBS"])
            con.execute(ref["PADROES"]["real"])
            for arquivo in sorted((RAIZ / "supabase" / "migrations").glob("*.sql")):
                if not any(chave in arquivo.name for chave in MIGRATIONS):
                    continue
                sql = arquivo.read_text(encoding="utf-8")
                if "f32_identidade" in arquivo.name:
                    sql = ref["sem_btree_gist"](sql)  # o pgserver não traz btree_gist
                con.execute(sql)
                if "revogar_execute" in arquivo.name:
                    con.execute(
                        "alter default privileges in schema public "
                        "revoke execute on functions from public"
                    )
            self._grants_do_service_role_da_f32(con)

    def _grants_do_service_role_da_f32(self, con: psycopg.Connection[Any]) -> None:
        """Os privilégios do `service_role` nas tabelas da F3.2 vêm da F3.8b, que depende das
        tabelas de dinheiro (F3.5/F3.6) e não roda aqui. Aplicamos só esse trecho dela."""
        sql = (RAIZ / "supabase" / "migrations").glob("*f38b_policies_rls.sql")
        texto = next(sql).read_text(encoding="utf-8")
        inicio = texto.index("revoke all on table public.usuarios,")
        fim = texto.index("revoke all on all sequences in schema public")
        con.execute(texto[inicio:fim])

    def admin(self) -> psycopg.Connection[Any]:
        """Conexão de superusuário, com commit automático (só para montar o cenário)."""
        return psycopg.connect(self.uri, autocommit=True)

    def fechar(self) -> None:
        self.servidor.cleanup()
