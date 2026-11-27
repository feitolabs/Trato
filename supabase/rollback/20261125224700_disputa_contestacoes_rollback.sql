-- ===========================================================================
-- Rollback de 20261125224700_disputa_contestacoes.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA se houver qualquer contestação de disputa.
-- ===========================================================================

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.disputa_contestacoes') is not null then
    lock table public.disputa_contestacoes in access exclusive mode;
    execute 'select exists (select 1 from public.disputa_contestacoes)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há contestações de disputa registradas';
    end if;
  end if;
end;
$$;

drop table if exists public.disputa_contestacoes;
drop function if exists public.disputa_contestacoes_validar();
drop sequence if exists public.disputa_contestacoes_protocolo_seq;

commit;
