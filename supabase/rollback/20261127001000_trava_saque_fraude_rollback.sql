-- ===========================================================================
-- Rollback de 20261127001000_trava_saque_fraude.sql
-- RASCUNHO (DB-TRAVA-FRAUDE). NÃO aplicado no Supabase de produção.
-- Preserva dados: trava se houver medida marcada como fraude. Definição de configuração já usada
-- em alguma versão permanece. Rodar ANTES do rollback de 20261126213500 / 20261125224600.
-- ===========================================================================

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.medidas_conta') is not null then
    lock table public.medidas_conta in access exclusive mode;
    if exists (select 1 from pg_attribute
                where attrelid = to_regclass('public.medidas_conta')
                  and attname = 'motivo_fraude' and not attisdropped) then
      execute 'select exists (select 1 from public.medidas_conta where motivo_fraude)' into v_tem;
      if v_tem then
        raise exception 'Rollback travado: há travas de saque por fraude registradas';
      end if;
    end if;
    execute 'drop trigger if exists medidas_conta_fraude_validar_trg on public.medidas_conta';
    execute 'drop trigger if exists medidas_conta_fraude_proteger on public.medidas_conta';
    execute 'alter table public.medidas_conta drop constraint if exists medidas_conta_fraude_prazo_check';
    execute 'alter table public.medidas_conta drop constraint if exists medidas_conta_limite_retencao_check';
    execute 'alter table public.medidas_conta drop constraint if exists medidas_conta_motivo_fraude_check';
    execute 'alter table public.medidas_conta drop column if exists limite_retencao_centavos';
    execute 'alter table public.medidas_conta drop column if exists motivo_fraude';
  end if;
end;
$$;

drop function if exists public.medidas_conta_fraude_validar();
drop function if exists public.trava_fraude_prazo_maximo_dias_vigente();

delete from public.config_definicoes d
 where d.chave = 'trava_fraude_prazo_maximo_dias'
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
