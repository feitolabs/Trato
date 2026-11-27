-- Rollback de 20261127061200_acessos_conta.sql
-- RASCUNHO (DB-TERMOS-100). NÃO aplicado no Supabase de produção.
-- Preserva dados (guarda legal): trava se houver registro de acesso ou guarda.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.acessos_conta') is not null then
    lock table public.acessos_conta in access exclusive mode;
    execute 'select exists (select 1 from public.acessos_conta)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há registros de acesso';
    end if;
  end if;
  if to_regclass('public.acessos_conta_guardas') is not null then
    lock table public.acessos_conta_guardas in access exclusive mode;
    execute 'select exists (select 1 from public.acessos_conta_guardas)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há guardas de acesso';
    end if;
  end if;
end;
$$;

drop function if exists public.registrar_acesso_conta(uuid, text, text, text, text, text, text, text, integer);
drop function if exists public.expurgar_acessos_conta(integer);
drop table if exists public.acessos_conta_guardas;
drop table if exists public.acessos_conta;
drop function if exists public.acessos_conta_proteger();
drop function if exists public.acessos_guardas_validar();

commit;
