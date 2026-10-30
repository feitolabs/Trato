"""Banco LOCAL descartável para testar as migrations do Trato (nunca toca no Supabase).

Precisa de: pip install pgserver psycopg2-binary (num venv FORA do projeto) e rodar com `python -I`.

O que este módulo faz:
  * sobe um Postgres embutido (pgserver) numa pasta temporária;
  * cria stubs do que o Supabase já traz: schema auth (users, uid), roles anon/authenticated/service_role,
    privilégios padrão do schema public (como no Supabase: tudo para anon/authenticated/service_role),
    schema storage (buckets, objects com RLS) e a função public.rls_auto_enable() da plataforma;
  * aplica as migrations em ordem e os rollbacks em ordem inversa;
  * deixa rodar SQL "como" um usuário (role authenticated + JWT com sub) ou como anon/service_role.

Limite conhecido: o Postgres embutido não traz btree_gist; só o EXCLUDE de faixas da F3.2 fica de fora.
"""
import json
import pathlib
from contextlib import contextmanager

import psycopg2
import pgserver

STUBS = """
create schema if not exists auth;
create schema if not exists extensions;
create schema if not exists storage;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create table auth.users (id uuid primary key default gen_random_uuid());
create function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(current_setting('request.jwt.claim.sub', true),
                         (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')), '')::uuid
$$;
grant usage on schema public, auth, extensions to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
-- Função da plataforma (a migration 20261029025741 revoga o EXECUTE dela).
create function public.rls_auto_enable() returns void language sql as 'select 1';
grant execute on function public.rls_auto_enable() to public, anon, authenticated, service_role;
-- Storage (versão mínima do Supabase).
create table storage.buckets (
  id text primary key, name text not null unique, public boolean not null default false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now());
create table storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets (id),
  name text, owner uuid, created_at timestamptz default now());
alter table storage.objects enable row level security;
alter table storage.buckets enable row level security;
grant usage on schema storage to anon, authenticated, service_role;
grant all on storage.objects, storage.buckets to anon, authenticated, service_role;
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select string_to_array(name, '/') $$;
alter database postgres set search_path = "$user", public, extensions;
"""


# Privilégios padrão do schema public para objetos criados pelo dono (postgres).
#  real        = o que foi OBSERVADO (só leitura) no projeto Trato em 29/10/2026: tabelas novas nascem com
#                TRUNCATE, REFERENCES e TRIGGER (e MAINTAIN, só no PG17) para anon, authenticated e service_role;
#                sequências só do dono; funções sem EXECUTE para PUBLIC depois da F3.2.
#  permissivo  = o padrão antigo do Supabase (tudo para anon/authenticated/service_role). As migrations
#                precisam funcionar nos dois; o teste de rollback só vale no modo "real".
PADROES = {
    "real": "alter default privileges in schema public grant truncate, references, trigger on tables "
            "to anon, authenticated, service_role;",
    "permissivo": """
        alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
        alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
        alter default privileges in schema public grant all on functions to anon, authenticated, service_role;""",
}


def sem_btree_gist(sql: str) -> str:
    """Tira só a extensão btree_gist e o EXCLUDE de faixas da F3.2 (o Postgres embutido não a traz)."""
    sql = sql.replace("create extension if not exists btree_gist with schema extensions;", "")
    i = sql.index("  -- Faixas da mesma versão e escopo")
    j = sql.index(chr(10) + ");" + chr(10) + "alter table public.config_faixas_taxa")
    return sql[:i].rstrip().rstrip(",") + sql[j:]


class Banco:
    def __init__(self, raiz, pasta_temp, nome="pgdata_trato", modo="real"):
        self.modo = modo
        self.raiz = pathlib.Path(raiz)
        self.srv = pgserver.get_server(pathlib.Path(pasta_temp) / nome, cleanup_mode="delete")
        self.uri = self.srv.get_uri()
        con = psycopg2.connect(self.uri)
        con.autocommit = True
        con.cursor().execute(STUBS)
        con.cursor().execute(PADROES[modo])
        con.close()
        self.admin = psycopg2.connect(self.uri)  # superusuário (dono das tabelas), autocommit
        self.admin.autocommit = True
        self.cur = self.admin.cursor()
        self.tx = psycopg2.connect(self.uri)  # conexão com transações explícitas
        self.migrations = sorted((self.raiz / "supabase/migrations").glob("*.sql"))

    # --- migrations -----------------------------------------------------------------------------
    def ler_migration(self, arquivo):
        sql = pathlib.Path(arquivo).read_text(encoding="utf-8")
        if "f32_identidade" in pathlib.Path(arquivo).name:
            sql = sem_btree_gist(sql)
        return sql

    def aplicar(self, arquivo):
        self.cur.execute(self.ler_migration(arquivo))
        if self.modo == "real" and "revogar_execute" in pathlib.Path(arquivo).name:
            # No projeto real, o padrão de funções (sem EXECUTE para PUBLIC) apareceu depois da F3.2.
            self.cur.execute("alter default privileges in schema public revoke execute on functions from public")

    def aplicar_todas(self, ate=None):
        for m in self.migrations:
            self.aplicar(m)
            if ate and ate in m.name:
                break

    def rollback(self, nome):
        self.cur.execute((self.raiz / "supabase/rollback" / nome).read_text(encoding="utf-8"))

    # --- execução como usuário ------------------------------------------------------------------
    @contextmanager
    def como(self, uid=None, papel="authenticated"):
        """Abre uma transação com o papel e o JWT dados; sempre desfaz no fim."""
        cur = self.tx.cursor()
        try:
            if uid is not None:
                cur.execute("select set_config('request.jwt.claims', %s, true)",
                            (json.dumps({"sub": str(uid), "role": papel}),))
            cur.execute(f"set local role {papel}")
            yield cur
        finally:
            self.tx.rollback()

    def ve(self, uid, sql, params=None, papel="authenticated"):
        """Linhas que o usuário enxerga; levanta exceção se o banco recusar."""
        with self.como(uid, papel) as cur:
            cur.execute(sql, params)
            return cur.fetchall() if cur.description else []

    def tenta(self, uid, sql, params=None, papel="authenticated"):
        """('ok', linhas) ou ('erro', mensagem)."""
        try:
            return ("ok", self.ve(uid, sql, params, papel))
        except psycopg2.Error as e:
            return ("erro", (e.pgerror or str(e)).splitlines()[0])

    def exec(self, sql, params=None):
        self.cur.execute(sql, params)
        return self.cur.fetchall() if self.cur.description else []

    def um(self, sql, params=None):
        return self.exec(sql, params)[0][0]

    def falha(self, sql, params=None):
        """Roda como dono (autocommit); devolve a mensagem de erro, ou None se passou."""
        try:
            self.cur.execute(sql, params)
            return None
        except psycopg2.Error as e:
            return (e.pgerror or str(e)).splitlines()[0]

    def transacao(self, comandos, papel=None):
        """Roda vários comandos numa transação e dá COMMIT (os triggers adiados disparam aqui).
        Devolve None se confirmou, ou a mensagem de erro."""
        cur = self.tx.cursor()
        try:
            if papel:
                cur.execute(f"set local role {papel}")
            for c in comandos:
                if isinstance(c, tuple):
                    cur.execute(c[0], c[1])
                else:
                    cur.execute(c)
            self.tx.commit()
            return None
        except psycopg2.Error as e:
            self.tx.rollback()
            return (e.pgerror or str(e)).splitlines()[0]

    def fechar(self):
        for c in (self.tx, self.admin):
            c.close()
        self.srv.cleanup()
