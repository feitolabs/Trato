-- ===========================================================================
-- Rollback de 20261122150000_avaliacao_criterios.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
--
-- Desfaz a coluna `avaliacoes.criterios`, a constraint `avaliacoes_criterios_check`
-- e restaura o trigger `avaliacoes_proteger` ao estado de 20261122100000_avaliacao_nota_decimal.sql.
--
-- SEGURO: se alguma avaliação já tiver `criterios` preenchido, o rollback falha e
-- desfaz tudo para evitar perda silenciosa das notas individuais.
-- Para forçar mesmo assim, na mesma sessão:
--   set trato.forcar_rollback_criterios = 'sim';
-- ===========================================================================

begin;

do $$
declare
  tem_dados boolean := false;
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'avaliacoes' and column_name = 'criterios'
  ) then
    execute 'select exists (select 1 from public.avaliacoes where criterios is not null)'
      into tem_dados;
  end if;
  if tem_dados
     and coalesce(current_setting('trato.forcar_rollback_criterios', true), '') <> 'sim' then
    raise exception
      'Há avaliações com criterios preenchidos: apagar a coluna perde as notas individuais. Para forçar: set trato.forcar_rollback_criterios = ''sim'';';
  end if;
end $$;

-- Restaura trigger anterior (20261122100000_avaliacao_nota_decimal.sql).
drop trigger if exists avaliacoes_proteger on public.avaliacoes;
create trigger avaliacoes_proteger before update on public.avaliacoes
  for each row execute function public.proteger_colunas(
    'contrato_id', 'direcao', 'avaliador_id', 'avaliado_id', 'nota_geral', 'nota_decimal',
    'comentario', 'etiquetas', 'criada_em');

alter table public.avaliacoes drop constraint if exists avaliacoes_criterios_check;
alter table public.avaliacoes drop column if exists criterios;

commit;
