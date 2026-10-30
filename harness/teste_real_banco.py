"""Banco REAL (Supabase): EXCLUDE das faixas de taxa, RLS ligada e privilégios.

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

INSERE = (
    "insert into public.config_faixas_taxa (versao_id, de_centavos, ate_centavos, taxa_bps) "
    "values (%s, %s, %s, %s)"
)

with psycopg.connect(variavel("DATABASE_URL"), autocommit=False) as conn:
    cur = conn.cursor()

    cur.execute("select count(*) from pg_extension where extname = 'btree_gist'")
    registra("extensão btree_gist instalada", cur.fetchone()[0] == 1)
    cur.execute(
        "select count(*) from pg_constraint "
        "where conrelid = 'public.config_faixas_taxa'::regclass and contype = 'x'"
    )
    registra("EXCLUDE de sobreposição existe em config_faixas_taxa", cur.fetchone()[0] == 1)
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

    # Escrita descartável: duas faixas sobrepostas na mesma versão de rascunho. O banco deve recusar.
    # Tudo termina em ROLLBACK, inclusive se algo der errado.
    try:
        cur.execute("select id from public.config_versoes where status = 'rascunho' limit 1")
        linha = cur.fetchone()
        if not linha:
            registra("EXCLUDE recusa faixas sobrepostas", None, "não há versão em rascunho (crie uma no painel)")
        else:
            versao = linha[0]
            cur.execute(INSERE, (versao, 900_000_000, 900_001_000, 100))
            cur.execute("savepoint s2")
            recusou = False
            try:
                cur.execute(INSERE, (versao, 900_000_500, 900_002_000, 200))
            except psycopg.errors.ExclusionViolation:
                recusou = True
            registra("EXCLUDE recusa faixas sobrepostas (sqlstate 23P01)", recusou)
            if recusou:
                cur.execute("rollback to savepoint s2")
                cur.execute(INSERE, (versao, 900_001_000, 900_002_000, 200))
                registra("faixas vizinhas (sem sobreposição) são aceitas", True)
    except psycopg.Error as erro:
        registra("EXCLUDE recusa faixas sobrepostas", False, f"{type(erro).__name__}: {str(erro)[:100]}")
    finally:
        conn.rollback()  # nada fica gravado

encerrar()
