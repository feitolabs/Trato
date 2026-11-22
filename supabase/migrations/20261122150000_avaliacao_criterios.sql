-- ===========================================================================
-- 20261122150000_avaliacao_criterios.sql
-- RASCUNHO. NÃO aplicada no Supabase de produção. Aguarda o OK do João.
--
-- Objetivo: salvar as notas individuais dos 5 critérios na avaliação de cliente
-- para profissional (pontualidade, qualidade, limpeza, comunicacao, preco_justo),
-- para exibição ao profissional e no perfil público.
--
-- Mudança mínima e retrocompatível:
--   1. Coluna nova `avaliacoes.criterios jsonb`, ANULÁVEL, sem default.
--      Avaliações antigas permanecem com NULL (nenhum UPDATE de dados).
--   2. Constraint CHECK `avaliacoes_criterios_check`: quando `criterios IS NOT NULL`,
--      garante que é um objeto JSON (`jsonb_typeof(criterios) = 'object'`), contém
--      apenas chaves permitidas (`pontualidade`, `qualidade`, `limpeza`,
--      `comunicacao`, `preco_justo`) e cada valor presente é inteiro entre 1 e 5.
--   3. Imutabilidade: `criterios` entra no trigger `avaliacoes_proteger` junto com
--      `nota_geral` e `nota_decimal`.
--
-- Idempotente (`add column if not exists`, `drop constraint/trigger if exists`).
-- RLS já está ativa em `public.avaliacoes` (sem alteração de policies ou grants).
-- Nota: a tabela legada `public.avaliacao_criterios` (F3.6) permanece intacta.
--
-- Rollback: supabase/rollback/20261122150000_avaliacao_criterios_rollback.sql
-- ===========================================================================

begin;

alter table public.avaliacoes
  add column if not exists criterios jsonb;

alter table public.avaliacoes
  drop constraint if exists avaliacoes_criterios_check;
alter table public.avaliacoes
  add constraint avaliacoes_criterios_check
  check (
    criterios is null
    or (
      jsonb_typeof(criterios) = 'object'
      and (criterios - array['pontualidade', 'qualidade', 'limpeza', 'comunicacao', 'preco_justo']) = '{}'::jsonb
      and (not (criterios ? 'pontualidade') or (jsonb_typeof(criterios -> 'pontualidade') = 'number' and (criterios ->> 'pontualidade') ~ '^[1-5]$'))
      and (not (criterios ? 'qualidade')    or (jsonb_typeof(criterios -> 'qualidade')    = 'number' and (criterios ->> 'qualidade')    ~ '^[1-5]$'))
      and (not (criterios ? 'limpeza')      or (jsonb_typeof(criterios -> 'limpeza')      = 'number' and (criterios ->> 'limpeza')      ~ '^[1-5]$'))
      and (not (criterios ? 'comunicacao')  or (jsonb_typeof(criterios -> 'comunicacao')  = 'number' and (criterios ->> 'comunicacao')  ~ '^[1-5]$'))
      and (not (criterios ? 'preco_justo')  or (jsonb_typeof(criterios -> 'preco_justo')  = 'number' and (criterios ->> 'preco_justo')  ~ '^[1-5]$'))
    )
  );

comment on column public.avaliacoes.criterios is
  'Notas individuais (1 a 5) dos 5 critérios da avaliação: pontualidade, qualidade, limpeza, comunicacao, preco_justo. NULL em avaliações antigas.';

-- Imutável como nota_geral e nota_decimal.
drop trigger if exists avaliacoes_proteger on public.avaliacoes;
create trigger avaliacoes_proteger before update on public.avaliacoes
  for each row execute function public.proteger_colunas(
    'contrato_id', 'direcao', 'avaliador_id', 'avaliado_id', 'nota_geral', 'nota_decimal',
    'criterios', 'comentario', 'etiquetas', 'criada_em');

commit;
