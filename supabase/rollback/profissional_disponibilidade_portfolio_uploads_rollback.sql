-- Desfaz 20261030130000_profissional_disponibilidade_portfolio_uploads.sql
drop table if exists public.upload_solicitacoes;
alter table public.perfis_profissional
  drop column if exists disponibilidade,
  drop column if exists portfolio;
