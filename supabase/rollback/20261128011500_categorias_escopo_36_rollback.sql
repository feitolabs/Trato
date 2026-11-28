-- ===========================================================================
-- Rollback de 20261128011500_categorias_escopo_36.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Trava se alguma categoria tiver incluido ou nao_incluido preenchido (evita perda de dados).
-- Idempotente quando vazio.
-- ===========================================================================

begin;

do $$
declare
  v_qtd     bigint := 0;
  v_tem_inc boolean;
  v_tem_nao boolean;
begin
  if to_regclass('public.categorias') is null then
    return;
  end if;

  lock table public.categorias in access exclusive mode;

  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'categorias' and column_name = 'incluido'
  ) into v_tem_inc;

  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'categorias' and column_name = 'nao_incluido'
  ) into v_tem_nao;

  if v_tem_inc and v_tem_nao then
    execute 'select count(*) from public.categorias where cardinality(incluido) > 0 or cardinality(nao_incluido) > 0' into v_qtd;
  elsif v_tem_inc then
    execute 'select count(*) from public.categorias where cardinality(incluido) > 0' into v_qtd;
  elsif v_tem_nao then
    execute 'select count(*) from public.categorias where cardinality(nao_incluido) > 0' into v_qtd;
  end if;

  if v_qtd > 0 then
    raise exception 'Rollback bloqueado: existem % categoria(s) com incluido/nao_incluido preenchido em public.categorias.', v_qtd;
  end if;
end $$;

alter table public.categorias
  drop constraint if exists categorias_incluido_check,
  drop constraint if exists categorias_nao_incluido_check;

alter table public.categorias
  drop column if exists incluido,
  drop column if exists nao_incluido;

commit;
