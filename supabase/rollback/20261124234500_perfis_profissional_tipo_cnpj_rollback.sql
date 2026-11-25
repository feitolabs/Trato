-- ===========================================================================
-- Rollback de 20261124234500_perfis_profissional_tipo_cnpj.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
--
-- Remove apenas a constraint `perfis_profissional_tipo_cnpj_check` e a coluna
-- `tipo_cnpj` de `public.perfis_profissional`, preservando todas as demais colunas.
--
-- SEGURO: se houver alguma linha com `tipo_cnpj` preenchido, o rollback falha e
-- desfaz tudo para evitar perda silenciosa de dados.
-- Para forçar mesmo assim, na mesma sessão:
--   set trato.forcar_rollback_tipo_cnpj = 'sim';
-- ===========================================================================

begin;

do $$
declare
  tem_dados boolean := false;
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'perfis_profissional'
       and column_name = 'tipo_cnpj'
  ) then
    execute 'select exists (select 1 from public.perfis_profissional where tipo_cnpj is not null)'
      into tem_dados;
  end if;

  if tem_dados
     and coalesce(current_setting('trato.forcar_rollback_tipo_cnpj', true), '') <> 'sim' then
    raise exception
      'Há profissionais com tipo_cnpj preenchido em public.perfis_profissional. Para forçar: set trato.forcar_rollback_tipo_cnpj = ''sim'';';
  end if;
end $$;

alter table public.perfis_profissional
  drop constraint if exists perfis_profissional_tipo_cnpj_check;

alter table public.perfis_profissional
  drop column if exists tipo_cnpj;

commit;
