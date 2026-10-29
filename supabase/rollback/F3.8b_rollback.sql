-- Desfaz a migration F3.8b (supabase/migrations/20261029030600_f38b_policies_rls.sql).
-- Remove TODAS as policies do schema public e as concessões de leitura. Depois disto, com RLS ligado e
-- sem policy, ninguém do app lê nada (estado de antes da F3.8b).
-- Rodar ANTES: rollback F3.8c. Rodar DEPOIS: rollback F3.8a.
-- Só rodar com OK do João.

do $$
declare
  p record;
begin
  for p in select schemaname, tablename, policyname from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end;
$$;

-- Estado das tabelas da F3.3 a F3.7 antes da F3.8b: sem acesso para anon e authenticated.
revoke all on all tables in schema public from anon, authenticated;

-- Estado original das tabelas da F3.2 (padrão da plataforma: tudo liberado, protegido só pelo RLS).
grant all on table public.usuarios, public.usuarios_privados, public.equipe, public.cidades,
  public.categorias, public.categoria_perguntas, public.perfis_profissional,
  public.profissional_categorias, public.profissional_regioes, public.verificacoes,
  public.verificacao_documentos, public.config_definicoes, public.config_versoes,
  public.config_parametros, public.config_faixas_taxa
  to anon, authenticated;
grant all on all sequences in schema public to anon, authenticated;
grant execute on function public.definir_atualizado_em(), public.config_versoes_proteger(),
  public.config_parametros_validar(), public.config_faixas_proteger()
  to public, anon, authenticated;
