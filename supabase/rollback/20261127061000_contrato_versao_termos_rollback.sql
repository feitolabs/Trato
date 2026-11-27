-- Rollback de 20261127061000_contrato_versao_termos.sql
-- RASCUNHO (DB-TERMOS-100). NÃO aplicado no Supabase de produção.
-- Preserva dados: trava se algum contrato já tem versão gravada ou se há versões cadastradas.

begin;

do $$
declare
  v_tem boolean;
begin
  lock table public.contratos in access exclusive mode;
  if exists (select 1 from pg_attribute where attrelid = 'public.contratos'::regclass
              and attname = 'termos_versao' and not attisdropped) then
    execute 'select exists (select 1 from public.contratos where termos_versao is not null)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há contratos com a versão dos Termos gravada';
    end if;
  end if;
  if to_regclass('public.termos_versoes') is not null then
    lock table public.termos_versoes in access exclusive mode;
    execute 'select exists (select 1 from public.termos_versoes)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há versões dos Termos cadastradas';
    end if;
  end if;
end;
$$;

drop trigger if exists pagamentos_registrar_termos_trg on public.pagamentos;
drop trigger if exists contratos_termos_proteger_trg on public.contratos;
alter table public.contratos drop constraint if exists contratos_termos_par_check;
alter table public.contratos drop column if exists termos_registrada_em;
alter table public.contratos drop column if exists termos_versao;
drop function if exists public.pagamentos_registrar_termos();
drop function if exists public.contratos_termos_proteger();
drop function if exists public.termos_versao_vigente(timestamptz);
drop table if exists public.termos_versoes;
drop function if exists public.termos_versoes_proteger();

commit;
