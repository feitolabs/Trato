-- ===========================================================================
-- Rollback de 20261124001000_indicacoes.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
--
-- Remove os índices e as tabelas `public.indicacoes` e `public.codigos_indicacao`.
--
-- SEGURO: se já houver registros em `public.indicacoes` ou `public.codigos_indicacao`,
-- o rollback falha e desfaz tudo para evitar perda silenciosa de dados.
-- Para forçar mesmo assim, na mesma sessão:
--   set trato.forcar_rollback_indicacoes = 'sim';
-- ===========================================================================

begin;

do $$
declare
  tem_dados boolean := false;
begin
  if to_regclass('public.indicacoes') is not null then
    execute 'select exists (select 1 from public.indicacoes)' into tem_dados;
  end if;
  if not tem_dados and to_regclass('public.codigos_indicacao') is not null then
    execute 'select exists (select 1 from public.codigos_indicacao)' into tem_dados;
  end if;
  if tem_dados
     and coalesce(current_setting('trato.forcar_rollback_indicacoes', true), '') <> 'sim' then
    raise exception
      'Há registros em indicacoes/codigos_indicacao: apagar as tabelas perde os dados. Para forçar: set trato.forcar_rollback_indicacoes = ''sim'';';
  end if;
end $$;

drop index if exists public.ix_indicacoes_status_liberacao;
drop index if exists public.ix_indicacoes_indicador_criado_em;
drop table if exists public.indicacoes;
drop table if exists public.codigos_indicacao;

commit;
