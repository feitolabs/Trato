-- Rollback de 20261125225700_lgpd_pedidos_titular.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA se houver pedido de titular.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.lgpd_pedidos_titular') is not null then
    lock table public.lgpd_pedidos_titular in access exclusive mode;
    execute 'select exists (select 1 from public.lgpd_pedidos_titular)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há pedidos de titular registrados';
    end if;
  end if;
end;
$$;

drop table if exists public.lgpd_pedidos_titular;
drop function if exists public.lgpd_pedidos_titular_validar();
drop function if exists public.lgpd_pedidos_titular_checar();
drop function if exists public.anonimizar_pedido_titular(uuid, uuid, text);
drop sequence if exists public.lgpd_pedidos_titular_protocolo_seq;

commit;
