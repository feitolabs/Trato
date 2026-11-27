-- Rollback de 20261126061100_ausencia_foto_chegada.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA (sem opção de forçar) se alguma ausência já tiver foto gravada.

begin;

do $$
declare
  v_tem boolean;
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'ausencias_cliente'
                and column_name = 'foto_chegada_midia_id') then
    lock table public.ausencias_cliente in access exclusive mode;
    execute 'select exists (select 1 from public.ausencias_cliente where foto_chegada_midia_id is not null)'
      into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há fotos de chegada gravadas';
    end if;
  end if;
end;
$$;

drop trigger if exists ausencias_cliente_foto_validar_trg on public.ausencias_cliente;
drop function if exists public.ausencias_cliente_foto_validar();
drop index if exists public.ix_ausencias_cliente_foto_chegada;
alter table if exists public.ausencias_cliente drop column if exists foto_chegada_midia_id;

commit;
