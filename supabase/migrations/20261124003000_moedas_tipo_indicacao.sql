-- ===========================================================================
-- 20261124003000_moedas_tipo_indicacao.sql
-- RASCUNHO. NÃO aplicada no Supabase de produção. Aguarda o OK do João para aplicar.
--
-- Objetivo: ampliar a constraint `moedas_lancamentos_tipo_check` em
-- `public.moedas_lancamentos` para aceitar `'bonus_indicacao'` (crédito de
-- Tratinhos do programa Indique e Ganhe), mantendo todos os 7 tipos existentes.
--
-- Mudança aditiva e idempotente (`drop constraint if exists` + `add constraint`),
-- sem UPDATE de dados e sem alterar RLS, grants ou imutabilidade do ledger.
--
-- Rollback: supabase/rollback/20261124003000_moedas_tipo_indicacao_rollback.sql
-- ===========================================================================

begin;

alter table public.moedas_lancamentos
  drop constraint if exists moedas_lancamentos_tipo_check;

alter table public.moedas_lancamentos
  add constraint moedas_lancamentos_tipo_check
  check (tipo in (
    'bonus_avaliacao',
    'estorno',
    'uso',
    'ajuste',
    'bonus_avaliacao_profissional',
    'exclusividade_uso',
    'exclusividade_estorno',
    'bonus_indicacao'
  ));

commit;
