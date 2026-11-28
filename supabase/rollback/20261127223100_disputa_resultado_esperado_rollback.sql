-- ===========================================================================
-- Rollback de 20261127223100_disputa_resultado_esperado.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Trava se alguma disputa já tiver resultado_esperado preenchido.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint;
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public'
              and table_name = 'disputas' and column_name = 'resultado_esperado') then
    lock table public.disputas in access exclusive mode;
    execute 'select count(*) from public.disputas where resultado_esperado is not null' into v_qtd;
    if v_qtd > 0 then
      raise exception 'Rollback bloqueado: % disputa(s) com resultado_esperado preenchido.', v_qtd;
    end if;
  end if;
end $$;

drop trigger if exists disputas_proteger_resultado_esperado on public.disputas;
alter table public.disputas drop constraint if exists disputas_resultado_esperado_check;
alter table public.disputas drop column if exists resultado_esperado;

commit;
