-- ===========================================================================
-- Rollback de 20261128014500_pedidos_substituicao_77.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Trava se houver qualquer pedido com substitui_pedido_id preenchido.
-- Idempotente quando vazio.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint;
begin
  if to_regclass('public.pedidos') is not null then
    lock table public.pedidos in access exclusive mode;
    if exists (
      select 1 from information_schema.columns
       where table_schema = 'public'
         and table_name = 'pedidos'
         and column_name = 'substitui_pedido_id'
    ) then
      execute 'select count(*) from public.pedidos where substitui_pedido_id is not null' into v_qtd;
      if v_qtd > 0 then
        raise exception 'Rollback bloqueado: existem % pedido(s) de substituição em public.pedidos.', v_qtd;
      end if;
    end if;
  end if;
end $$;

drop index if exists public.ix_cancelamentos_pedido_profissional_faltas;
drop trigger if exists pedidos_proteger_substituicao on public.pedidos;
drop index if exists public.pedidos_substitui_pedido_uidx;
drop index if exists public.pedidos_substitui_pedido_idx;

alter table public.pedidos
  drop constraint if exists pedidos_substitui_pedido_check;

alter table public.pedidos
  drop column if exists substitui_pedido_id;

commit;
