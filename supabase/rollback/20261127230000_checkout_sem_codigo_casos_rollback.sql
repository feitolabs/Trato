-- ===========================================================================
-- Rollback de 20261127230000_checkout_sem_codigo_casos.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Trava se houver qualquer caso registrado. Não mexe em Pedido nem em dinheiro.
-- O parâmetro tem rollback próprio: seed_config_checkout_sem_codigo_rollback.sql.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint;
begin
  if to_regclass('public.checkout_sem_codigo_casos') is not null then
    lock table public.checkout_sem_codigo_casos in access exclusive mode;
    execute 'select count(*) from public.checkout_sem_codigo_casos' into v_qtd;
    if v_qtd > 0 then
      raise exception 'Rollback bloqueado: existem % caso(s) em public.checkout_sem_codigo_casos.', v_qtd;
    end if;
  end if;
end $$;

drop table if exists public.checkout_sem_codigo_casos;
drop function if exists public.checkout_sem_codigo_casos_validar();
drop function if exists public.checkout_sem_codigo_vigente(uuid);

commit;
