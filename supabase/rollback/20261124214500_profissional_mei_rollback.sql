-- ===========================================================================
-- Rollback de 20261124214500_profissional_mei.sql
--
-- Nota de produção: a coluna `cnpj` já existia em `public.perfis_profissional`
-- antes desta migration; portanto este rollback NÃO remove `cnpj`. Remove apenas
-- o índice `ux_perfis_profissional_cnpj`, as 2 constraints CHECK e as 4 colunas
-- novas (`mei_motivo`, `razao_social`, `mei_validado_em`, `mei_status`).
--
-- SEGURO: se algum profissional já tiver dados nos campos novos de MEI
-- (`mei_status <> 'nao_informado'`, `mei_validado_em`, `razao_social` ou
-- `mei_motivo`), o rollback falha e desfaz tudo para evitar perda silenciosa.
-- Para forçar mesmo assim, na mesma sessão:
--   set trato.forcar_rollback_profissional_mei = 'sim';
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
       and column_name = 'mei_status'
  ) then
    execute $q$
      select exists (
        select 1 from public.perfis_profissional
         where mei_status <> 'nao_informado'
            or mei_validado_em is not null
            or razao_social is not null
            or mei_motivo is not null
      )
    $q$ into tem_dados;
  end if;

  if tem_dados
     and coalesce(current_setting('trato.forcar_rollback_profissional_mei', true), '') <> 'sim' then
    raise exception
      'Há profissionais com dados de MEI preenchidos em public.perfis_profissional. Para forçar: set trato.forcar_rollback_profissional_mei = ''sim'';';
  end if;
end $$;

drop index if exists public.ux_perfis_profissional_cnpj;

alter table public.perfis_profissional
  drop constraint if exists perfis_profissional_mei_status_check,
  drop constraint if exists perfis_profissional_cnpj_check;

alter table public.perfis_profissional
  drop column if exists mei_motivo,
  drop column if exists razao_social,
  drop column if exists mei_validado_em,
  drop column if exists mei_status;

commit;
