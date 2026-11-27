-- ===========================================================================
-- Rollback de 20261125224500_sac_chamados.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA se houver qualquer chamado. Rode antes os rollbacks
-- 20261125224700 e 20261125224600 (usam o gerador de protocolo e referenciam chamados).
-- ===========================================================================

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.chamados') is not null then
    lock table public.chamados in access exclusive mode;
    execute 'select exists (select 1 from public.chamados)' into v_tem;
    if v_tem then
      raise exception 'Rollback do SAC travado: há chamados registrados';
    end if;
  end if;
end;
$$;

drop table if exists public.chamado_mensagens;
drop table if exists public.chamados;
drop sequence if exists public.chamados_protocolo_seq;
drop function if exists public.anonimizar_chamado(uuid, uuid, text);
drop function if exists public.chamado_mensagens_imutavel();
drop function if exists public.sac_gerar_protocolo();

commit;
