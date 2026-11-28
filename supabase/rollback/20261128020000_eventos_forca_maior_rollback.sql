-- ===========================================================================
-- Rollback de 20261128020000_eventos_forca_maior.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Trava se houver qualquer registro em public.eventos_forca_maior.
-- Idempotente quando vazia.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint;
begin
  if to_regclass('public.eventos_forca_maior') is not null then
    lock table public.eventos_forca_maior in access exclusive mode;
    execute 'select count(*) from public.eventos_forca_maior' into v_qtd;
    if v_qtd > 0 then
      raise exception 'Rollback bloqueado: existem % registro(s) em public.eventos_forca_maior.', v_qtd;
    end if;
  end if;
end $$;

drop table if exists public.eventos_forca_maior;
drop function if exists public.eventos_forca_maior_validar();

commit;
