"""Testa a migration F3.2 num Postgres LOCAL descartável (nunca no Supabase).
Uso: python -I supabase/testes/testar_f32.py <raiz-do-projeto> <pasta-temporaria>
Precisa de: pip install pgserver psycopg2-binary (num venv fora do projeto).
Limite: o Postgres embutido não traz btree_gist, então o EXCLUDE de faixas da taxa fica de fora.
"""
import sys, pathlib, pgserver, psycopg2
raiz = pathlib.Path(sys.argv[1]); dados = pathlib.Path(sys.argv[2]) / "pgdata_f32"
srv = pgserver.get_server(dados, cleanup_mode="delete")
con = psycopg2.connect(srv.get_uri()); con.autocommit = True; cur = con.cursor()
print(cur.execute("select version()") or cur.fetchone()[0][:40])
# Stubs do que o Supabase já tem (só no banco de teste descartável)
cur.execute("""create schema if not exists auth; create schema if not exists extensions;
  create table auth.users (id uuid primary key default gen_random_uuid());
  alter database postgres set search_path = "$user", public, extensions;""")
con.close(); con = psycopg2.connect(srv.get_uri()); con.autocommit = True; cur = con.cursor()
sql = (raiz / "supabase/migrations/20261029025430_f32_identidade_catalogo_config.sql").read_text(encoding="utf-8")
# O Postgres embutido não traz btree_gist: no teste local tiramos só a extensão e o EXCLUDE de faixas.
sql = sql.replace("create extension if not exists btree_gist with schema extensions;", "")
i = sql.index("  -- Faixas da mesma versão e escopo")
j = sql.index(chr(10) + ");" + chr(10) + "alter table public.config_faixas_taxa")
sql = sql[:i].rstrip().rstrip(",") + sql[j:]
cur.execute(sql); print("migration aplicada no banco de TESTE")
cur.execute("select count(*) from pg_tables where schemaname='public'"); print("tabelas:", cur.fetchone()[0])
cur.execute("select count(*) from pg_tables where schemaname='public' and not rowsecurity"); print("sem RLS:", cur.fetchone()[0])

def tenta(titulo, sql, deve_falhar):
    try:
        cur.execute(sql); ok = True
    except Exception as e:
        ok = False; msg = str(e).splitlines()[0]
    print(("OK   " if ok != deve_falhar else "ERRO ") + titulo + ("" if ok else f"  [{msg}]"))

cur.execute("insert into auth.users default values returning id"); u1 = cur.fetchone()[0]
cur.execute("insert into auth.users default values returning id"); u2 = cur.fetchone()[0]
cur.execute("insert into usuarios(id,nome) values (%s,'Ana'),(%s,'Beto')", (u1,u2))
cur.execute("insert into equipe(usuario_id,papel) values (%s,'administrador'),(%s,'financeiro')", (u1,u2))
tenta("cpf duplicado é bloqueado", f"insert into usuarios_privados(usuario_id,cpf) values ('{u1}','111'),('{u2}','111')", True)
tenta("status de usuário inválido é bloqueado", f"update usuarios set status='xyz' where id='{u1}'", True)
cur.execute("insert into config_definicoes(chave,descricao,unidade,minimo,maximo,escopos_permitidos,exige_dupla_aprovacao) values ('teste_bps','t','bps',0,10000,array['global','cidade'],true)")
cur.execute(f"insert into config_versoes(criada_por,motivo) values ('{u1}','teste') returning id"); v = cur.fetchone()[0]
tenta("criada_por = aprovada_por é bloqueado", f"update config_versoes set aprovada_por='{u1}' where id='{v}'", True)
tenta("parâmetro acima do máximo é bloqueado", f"insert into config_parametros(versao_id,chave,valor) values ('{v}','teste_bps',10001)", True)
tenta("escopo não permitido é bloqueado", f"insert into config_parametros(versao_id,chave,valor,escopo_tipo,escopo_texto) values ('{v}','teste_bps',5,'nivel','ouro')", True)
tenta("parâmetro válido entra", f"insert into config_parametros(versao_id,chave,valor) values ('{v}','teste_bps',750)", False)
tenta("parâmetro repetido é bloqueado", f"insert into config_parametros(versao_id,chave,valor) values ('{v}','teste_bps',800)", True)
tenta("faixa 0-50000 entra", f"insert into config_faixas_taxa(versao_id,de_centavos,ate_centavos,taxa_bps) values ('{v}',0,50000,750)", False)
print("PULADO faixa sobreposta (EXCLUDE precisa de btree_gist, só no Supabase)")
tenta("faixa seguinte sem teto entra", f"insert into config_faixas_taxa(versao_id,de_centavos,ate_centavos,taxa_bps) values ('{v}',50000,null,600)", False)
tenta("aprovar versão (outra pessoa)", f"update config_versoes set status='aprovada', aprovada_por='{u2}' where id='{v}'", False)
tenta("depois de aprovada: faixa não muda", f"update config_faixas_taxa set taxa_bps=1 where versao_id='{v}'", True)
tenta("depois de aprovada: parâmetro não muda", f"delete from config_parametros where versao_id='{v}'", True)
tenta("depois de aprovada: motivo não muda", f"update config_versoes set motivo='outro' where id='{v}'", True)
tenta("aprovada -> vigente entra", f"update config_versoes set status='vigente' where id='{v}'", False)
cur.execute(f"insert into config_versoes(criada_por,motivo) values ('{u1}','v2') returning id"); v2 = cur.fetchone()[0]
cur.execute(f"update config_versoes set status='aprovada', aprovada_por='{u2}' where id='{v2}'")
tenta("2ª versão vigente é bloqueada", f"update config_versoes set status='vigente' where id='{v2}'", True)
tenta("apagar versão aprovada é bloqueado", f"delete from config_versoes where id='{v2}'", True)
cur.execute("insert into cidades(nome,uf) values ('Cidade Teste','XX')")
cur.execute("insert into perfis_profissional(usuario_id) values (%s)", (u1,))
cur.execute("insert into cidades(nome,uf) values ('Outra','YY') returning id"); c = cur.fetchone()[0]
cur.execute("insert into profissional_regioes(profissional_id,cidade_id) values (%s,%s)", (u1,c))
tenta("região repetida (sem bairro) é bloqueada", f"insert into profissional_regioes(profissional_id,cidade_id) values ('{u1}','{c}')", True)
tenta("verificação recusada exige motivo", f"insert into verificacoes(profissional_id,nivel_solicitado,status,consentimento_lgpd_em) values ('{u1}','verificado','recusada',now())", True)

rb = (raiz / "supabase/rollback/F3.2_rollback.sql").read_text(encoding="utf-8")
cur.execute(rb); cur.execute("select count(*) from pg_tables where schemaname='public'"); print("rollback ->", cur.fetchone()[0], "tabelas restantes")
cur.execute(sql); print("migration reaplicada depois do rollback: ok")
con.close(); srv.cleanup()
