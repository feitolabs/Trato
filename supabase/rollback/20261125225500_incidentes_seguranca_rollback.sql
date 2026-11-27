-- Rollback de 20261125225500_incidentes_seguranca.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA se houver incidente registrado.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.incidentes_seguranca') is not null then
    lock table public.incidentes_seguranca in access exclusive mode;
    execute 'select exists (select 1 from public.incidentes_seguranca)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há incidentes de segurança registrados';
    end if;
  end if;
end;
$$;

drop table if exists public.incidente_medidas;
drop table if exists public.incidentes_seguranca;
drop function if exists public.incidentes_validar();
drop function if exists public.incidente_medidas_validar();
drop sequence if exists public.incidentes_seguranca_protocolo_seq;

commit;
