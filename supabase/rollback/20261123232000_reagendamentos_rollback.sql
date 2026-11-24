-- ===========================================================================
-- Rollback de 20261123232000_reagendamentos.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
--
-- Remove os índices e a tabela `public.reagendamentos`.
--
-- SEGURO: se já houver registros em `public.reagendamentos`, o rollback falha e
-- desfaz tudo para evitar perda silenciosa do histórico de reagendamentos.
-- Para forçar mesmo assim, na mesma sessão:
--   set trato.forcar_rollback_reagendamentos = 'sim';
-- ===========================================================================

begin;

do $$
declare
  tem_dados boolean := false;
begin
  if to_regclass('public.reagendamentos') is not null then
    execute 'select exists (select 1 from public.reagendamentos)'
      into tem_dados;
  end if;
  if tem_dados
     and coalesce(current_setting('trato.forcar_rollback_reagendamentos', true), '') <> 'sim' then
    raise exception
      'Há registros em public.reagendamentos: apagar a tabela perde o histórico. Para forçar: set trato.forcar_rollback_reagendamentos = ''sim'';';
  end if;
end $$;

drop index if exists public.ix_reagendamentos_pedido_criado_em;
drop index if exists public.ux_reagendamentos_pedido_pendente;
drop table if exists public.reagendamentos;

commit;
