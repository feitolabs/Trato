-- ===========================================================================
-- Rollback de 20261124002000_recorrencias.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
--
-- Remove os índices e as tabelas `public.recorrencia_visitas` e `public.recorrencias`.
--
-- SEGURO: se já houver registros em `public.recorrencia_visitas` ou `public.recorrencias`,
-- o rollback falha e desfaz tudo para evitar perda silenciosa de dados.
-- Para forçar mesmo assim, na mesma sessão:
--   set trato.forcar_rollback_recorrencias = 'sim';
-- ===========================================================================

begin;

do $$
declare
  tem_dados boolean := false;
begin
  if to_regclass('public.recorrencia_visitas') is not null then
    execute 'select exists (select 1 from public.recorrencia_visitas)' into tem_dados;
  end if;
  if not tem_dados and to_regclass('public.recorrencias') is not null then
    execute 'select exists (select 1 from public.recorrencias)' into tem_dados;
  end if;
  if tem_dados
     and coalesce(current_setting('trato.forcar_rollback_recorrencias', true), '') <> 'sim' then
    raise exception
      'Há registros em recorrencias/recorrencia_visitas: apagar as tabelas perde os dados. Para forçar: set trato.forcar_rollback_recorrencias = ''sim'';';
  end if;
end $$;

drop index if exists public.ix_recorrencia_visitas_status_data;
drop index if exists public.ux_recorrencia_visitas_recorrencia_data;
drop table if exists public.recorrencia_visitas;

drop index if exists public.ix_recorrencias_profissional_status;
drop index if exists public.ix_recorrencias_cliente_status;
drop table if exists public.recorrencias;

commit;
