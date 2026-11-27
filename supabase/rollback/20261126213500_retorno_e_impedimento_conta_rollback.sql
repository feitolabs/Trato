-- ===========================================================================
-- Rollback de 20261126213500_retorno_e_impedimento_conta.sql
-- RASCUNHO (TERMOS-DB-209). NÃO aplicado no Supabase de produção.
-- Preserva dados: trava se houver impedimento, pedido de retorno ou medida
-- marcada como infração grave / impedimento de nova conta. Definição de
-- configuração já usada em alguma versão permanece.
-- ===========================================================================

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.conta_pedidos_retorno') is not null then
    lock table public.conta_pedidos_retorno in access exclusive mode;
    execute 'select exists (select 1 from public.conta_pedidos_retorno)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há pedidos de retorno registrados';
    end if;
  end if;

  if to_regclass('public.conta_impedimentos_cadastro') is not null then
    lock table public.conta_impedimentos_cadastro in access exclusive mode;
    execute 'select exists (select 1 from public.conta_impedimentos_cadastro)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há impedimentos de cadastro registrados';
    end if;
  end if;

  if to_regclass('public.medidas_conta') is not null then
    lock table public.medidas_conta in access exclusive mode;
    if exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'medidas_conta'
         and column_name in ('infracao_grave', 'impedir_nova_conta')
    ) then
      execute 'select exists (select 1 from public.medidas_conta where infracao_grave or impedir_nova_conta)' into v_tem;
      if v_tem then
        raise exception 'Rollback travado: há medidas marcadas como infração grave ou impedimento';
      end if;
    end if;
  end if;
end;
$$;

drop table if exists public.conta_pedidos_retorno;
drop table if exists public.conta_impedimentos_cadastro;
drop function if exists public.conta_pedidos_retorno_validar();
drop function if exists public.conta_impedimentos_validar();
drop function if exists public.conta_retorno_prazo_dias_vigente();
drop sequence if exists public.conta_pedidos_retorno_protocolo_seq;

do $$
begin
  if to_regclass('public.medidas_conta') is not null then
    execute 'drop trigger if exists medidas_conta_retorno_proteger on public.medidas_conta';
    execute 'alter table public.medidas_conta drop constraint if exists medidas_conta_impedir_nova_conta_check';
    execute 'alter table public.medidas_conta drop constraint if exists medidas_conta_infracao_grave_check';
    execute 'alter table public.medidas_conta drop column if exists impedir_nova_conta';
    execute 'alter table public.medidas_conta drop column if exists infracao_grave';
  end if;
end;
$$;

delete from public.config_definicoes d
 where d.chave = 'conta_retorno_prazo_dias'
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
