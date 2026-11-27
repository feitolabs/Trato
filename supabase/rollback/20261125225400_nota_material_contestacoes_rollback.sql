-- Rollback de 20261125225400_nota_material_contestacoes.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA se houver contestação. O status das notas não é alterado.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.nota_material_contestacoes') is not null then
    lock table public.nota_material_contestacoes in access exclusive mode;
    execute 'select exists (select 1 from public.nota_material_contestacoes)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há contestações de nota de material';
    end if;
  end if;
end;
$$;

drop table if exists public.nota_material_contestacoes;
drop function if exists public.nota_material_contestacoes_validar();
drop sequence if exists public.nota_material_contestacoes_protocolo_seq;

commit;
