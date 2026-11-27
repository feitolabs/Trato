-- ===========================================================================
-- Rollback de 20261125224600_medidas_conta.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA se houver qualquer medida (contestações dependem delas).
-- Os chamados continuam; só a FK chamados.medida_id é removida.
-- ===========================================================================

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.medidas_conta') is not null then
    lock table public.medidas_conta in access exclusive mode;
    execute 'select exists (select 1 from public.medidas_conta)' into v_tem;
    if v_tem then
      raise exception 'Rollback das medidas travado: há medidas registradas';
    end if;
  end if;
end;
$$;

alter table if exists public.chamados drop constraint if exists chamados_medida_fk;
drop table if exists public.medida_contestacoes;
drop table if exists public.medidas_conta;
drop function if exists public.medida_contestacoes_validar();
drop function if exists public.medidas_conta_encadeamento();
drop sequence if exists public.medidas_conta_protocolo_seq;
drop sequence if exists public.medida_contestacoes_protocolo_seq;

commit;
