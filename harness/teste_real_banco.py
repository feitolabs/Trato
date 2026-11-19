"""Banco REAL (Supabase): extensão, RLS ligada e privilégios.

Leitura do catálogo + uma transação que SEMPRE termina em ROLLBACK (nada fica gravado).
Variáveis: TRATO_TESTE_REAL=sim, DATABASE_URL (conexão do projeto "Trato"; só no seu .env).
Rode com o Python do backend:  backend/.venv/Scripts/python harness/teste_real_banco.py
"""

from __future__ import annotations

import sys

from teste_real_comum import encerrar, exigir_teste_real, registra, variavel

exigir_teste_real()
try:
    import psycopg
except ImportError:
    print("Use o Python do backend (precisa do psycopg).")
    sys.exit(2)

with psycopg.connect(variavel("DATABASE_URL"), autocommit=False) as conn:
    cur = conn.cursor()

    cur.execute("select count(*) from pg_extension where extname = 'btree_gist'")
    registra("extensão btree_gist instalada", cur.fetchone()[0] == 1)
    cur.execute("select to_regclass('public.config_faixas_taxa') is null")
    registra("config_faixas_taxa removida (app gratuito)", cur.fetchone()[0])
    cur.execute("select count(*) from pg_tables where schemaname = 'public' and not rowsecurity")
    registra("toda tabela de public tem RLS", cur.fetchone()[0] == 0)
    cur.execute(
        "select count(*) from information_schema.role_table_grants "
        "where table_schema = 'public' and grantee = 'anon'"
    )
    registra("anon não tem nenhum grant em public", cur.fetchone()[0] == 0)
    cur.execute(
        "select count(*) from information_schema.column_privileges "
        "where table_schema = 'public' and grantee = 'authenticated' and privilege_type = 'SELECT' "
        "and (table_name, column_name) in (('lancamentos','criado_por'),"
        "('repasses','provedor_transferencia_id'),('eventos_webhook','payload'),"
        "('retrabalhos','custo_centavos'),('aditivos','decidido_por'))"
    )
    registra("B2: colunas internas do dinheiro fechadas para authenticated", cur.fetchone()[0] == 0)

encerrar()
