-- Rollback da migration 20261117120000_profissional_recebimento_disponivel_ausencia.sql.

alter table public.presencas drop constraint if exists presencas_tipo_check;
alter table public.presencas add constraint presencas_tipo_check
  check (tipo in ('check_in', 'check_out'));

drop index if exists public.perfis_profissional_disponivel_idx;

revoke select (disponivel_agora) on public.perfis_profissional from authenticated;

alter table public.perfis_profissional
  drop column if exists conta_recebimento,
  drop column if exists disponivel_agora;
