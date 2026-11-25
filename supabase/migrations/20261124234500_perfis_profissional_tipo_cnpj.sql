-- ===========================================================================
-- 20261124234500_perfis_profissional_tipo_cnpj.sql
-- RASCUNHO. NÃO aplicada no Supabase de produção. Aguarda o OK do João para aplicar.
--
-- Objetivo: adicionar a coluna opcional `tipo_cnpj text` em
-- `public.perfis_profissional` para diferenciar MEI de outro tipo de CNPJ
-- (`'mei'` ou `'outro'`).
--
-- Mudanças (somente aditivas e idempotentes):
--   1. Coluna `tipo_cnpj text` (nullable, sem default, sem UPDATE de dados).
--   2. Constraint CHECK `perfis_profissional_tipo_cnpj_check`:
--      `tipo_cnpj is null or tipo_cnpj in ('mei', 'outro')`.
--   3. RLS mantida em `public.perfis_profissional`, sem nova policy e sem
--      `grant select` para `anon`/`authenticated` (acesso no banco restrito
--      a `service_role`, como as demais colunas do MEI).
--
-- Rollback: supabase/rollback/20261124234500_perfis_profissional_tipo_cnpj_rollback.sql
-- ===========================================================================

begin;

alter table public.perfis_profissional
  add column if not exists tipo_cnpj text;

alter table public.perfis_profissional
  drop constraint if exists perfis_profissional_tipo_cnpj_check;
alter table public.perfis_profissional
  add constraint perfis_profissional_tipo_cnpj_check
  check (tipo_cnpj is null or tipo_cnpj in ('mei', 'outro'));

comment on column public.perfis_profissional.tipo_cnpj is
  'Tipo de CNPJ informado pelo profissional: ''mei'' ou ''outro'' (NULL se não informado). Sem grant público; acesso apenas via backend (service_role).';

commit;
