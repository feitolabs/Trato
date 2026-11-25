-- ===========================================================================
-- 20261124214500_profissional_mei.sql
-- Migration de validação de MEI do profissional em `public.perfis_profissional`
-- (fonte: docs/mei-profissional-colunas.md).
--
-- Nota de produção: a coluna `cnpj text` já existia em `public.perfis_profissional`
-- (com 0/11 linhas preenchidas e sem constraints/índices). O `add column if not exists`
-- a mantém intacta e acrescenta as 4 colunas novas, os 2 checks e o índice único parcial.
--
-- Mudanças (somente aditivas e idempotentes):
--   1. Colunas em `public.perfis_profissional` (todas nullable ou com default,
--      retrocompatíveis com o backend atual, sem UPDATE de dados):
--      - `cnpj text` (pré-existente; NULL ou 14 dígitos numéricos)
--      - `mei_status text not null default 'nao_informado'`
--        check in ('nao_informado', 'pendente', 'valido', 'invalido')
--      - `mei_validado_em timestamptz`
--      - `razao_social text`
--      - `mei_motivo text`
--   2. Índice único parcial `ux_perfis_profissional_cnpj` em `(cnpj) where cnpj is not null`:
--      impede que o mesmo CNPJ seja usado por dois profissionais.
--   3. RLS mantida em `public.perfis_profissional`, sem nova policy de leitura pública
--      e sem `grant select` dessas colunas para `anon`/`authenticated` (dado de negócio:
--      acesso no banco restrito a `service_role`, exposto pelo backend apenas ao próprio
--      profissional).
--
-- Rollback: supabase/rollback/20261124214500_profissional_mei_rollback.sql
-- ===========================================================================

begin;

alter table public.perfis_profissional
  add column if not exists cnpj text,
  add column if not exists mei_status text not null default 'nao_informado',
  add column if not exists mei_validado_em timestamptz,
  add column if not exists razao_social text,
  add column if not exists mei_motivo text;

alter table public.perfis_profissional
  drop constraint if exists perfis_profissional_cnpj_check;
alter table public.perfis_profissional
  add constraint perfis_profissional_cnpj_check
  check (cnpj is null or cnpj ~ '^[0-9]{14}$');

alter table public.perfis_profissional
  drop constraint if exists perfis_profissional_mei_status_check;
alter table public.perfis_profissional
  add constraint perfis_profissional_mei_status_check
  check (mei_status in ('nao_informado', 'pendente', 'valido', 'invalido'));

create unique index if not exists ux_perfis_profissional_cnpj
  on public.perfis_profissional (cnpj)
  where cnpj is not null;

comment on column public.perfis_profissional.cnpj is
  'CNPJ do MEI do profissional (14 dígitos numéricos). Dado de negócio: sem grant público; acesso apenas via backend (service_role).';
comment on column public.perfis_profissional.mei_status is
  'Estado da validação do MEI: nao_informado, pendente, valido ou invalido.';
comment on column public.perfis_profissional.mei_validado_em is
  'Instante da validação do MEI (NULL enquanto nao_informado/pendente).';
comment on column public.perfis_profissional.razao_social is
  'Razão social retornada na validação do CNPJ (BrasilAPI); NULL se não validado.';
comment on column public.perfis_profissional.mei_motivo is
  'Mensagem curta em português explicando o estado atual da validação do MEI.';

commit;
