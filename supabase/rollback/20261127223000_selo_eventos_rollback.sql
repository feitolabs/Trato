-- ===========================================================================
-- Rollback de 20261127223000_selo_eventos.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Trava se houver qualquer evento (histórico não se perde). Não muda nível de ninguém.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint;
begin
  if to_regclass('public.selo_eventos') is not null then
    lock table public.selo_eventos in access exclusive mode;
    execute 'select count(*) from public.selo_eventos' into v_qtd;
    if v_qtd > 0 then
      raise exception 'Rollback bloqueado: existem % evento(s) em public.selo_eventos.', v_qtd;
    end if;
  end if;
end $$;

drop trigger if exists perfis_profissional_selo_retirado_trg on public.perfis_profissional;
drop function if exists public.perfis_profissional_selo_retirado();
drop function if exists public.selo_retirar(uuid, uuid, text, text, timestamptz);
drop function if exists public.selo_pedir_reconferencia(uuid, uuid, text, text, timestamptz);
drop function if exists public.selo_regularizar(uuid, uuid, text, text, timestamptz);
drop function if exists public.selo_operador_ok(uuid, text[]);
drop table if exists public.selo_eventos;

commit;
