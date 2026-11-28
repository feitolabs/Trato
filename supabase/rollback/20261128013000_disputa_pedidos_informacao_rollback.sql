-- ===========================================================================
-- Rollback de 20261128013000_disputa_pedidos_informacao.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Trava se houver qualquer pedido de informação registrado. Idempotente quando vazio.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint;
begin
  if to_regclass('public.disputa_pedidos_informacao') is not null then
    lock table public.disputa_pedidos_informacao in access exclusive mode;
    execute 'select count(*) from public.disputa_pedidos_informacao' into v_qtd;
    if v_qtd > 0 then
      raise exception 'Rollback bloqueado: existem % pedido(s) de informação em public.disputa_pedidos_informacao.', v_qtd;
    end if;
  end if;
end $$;

drop table if exists public.disputa_pedidos_informacao;
drop function if exists public.disputa_pedidos_informacao_validar();

commit;
