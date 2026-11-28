-- ===========================================================================
-- 20261128011500_categorias_escopo_36.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, cláusula 3.6: acrescenta em public.categorias as listas
-- incluido e nao_incluido (text[] not null default '{}') para exibir o escopo
-- padrão de cada categoria (o que está incluído e o que não está incluído).
--
-- Só acrescenta; sem UPDATE de dados (os textos por categoria entram depois).
-- Depende apenas de: 20261029025430_f32_identidade_catalogo_config.sql (public.categorias).
-- Rollback: supabase/rollback/20261128011500_categorias_escopo_36_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.categorias') is null then
    raise exception 'Aplique antes a migration 20261029025430_f32_identidade_catalogo_config.sql (public.categorias)';
  end if;
end $$;

alter table public.categorias
  add column if not exists incluido     text[] not null default '{}',
  add column if not exists nao_incluido text[] not null default '{}';

alter table public.categorias
  drop constraint if exists categorias_incluido_check,
  drop constraint if exists categorias_nao_incluido_check;

alter table public.categorias
  add constraint categorias_incluido_check
    check (
      (array_ndims(incluido) is null or array_ndims(incluido) = 1)
      and array_position(incluido, null) is null
    ),
  add constraint categorias_nao_incluido_check
    check (
      (array_ndims(nao_incluido) is null or array_ndims(nao_incluido) = 1)
      and array_position(nao_incluido, null) is null
    );

commit;
