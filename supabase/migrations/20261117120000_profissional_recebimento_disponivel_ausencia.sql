-- Conta de recebimento (Pix / banco para repasse), disponibilidade imediata ("Disponível agora")
-- e registro formal de ausência do cliente no check-in (`presencas.tipo = 'cliente_ausente'`).
-- Rollback em supabase/rollback/20261117120000_profissional_recebimento_disponivel_ausencia_rollback.sql.

alter table public.perfis_profissional
  add column if not exists disponivel_agora boolean not null default false,
  add column if not exists conta_recebimento jsonb;

grant select (disponivel_agora) on public.perfis_profissional to authenticated;

create index if not exists perfis_profissional_disponivel_idx
  on public.perfis_profissional (usuario_id)
  where disponivel_agora = true and status = 'aprovado';

alter table public.presencas drop constraint if exists presencas_tipo_check;
alter table public.presencas add constraint presencas_tipo_check
  check (tipo in ('check_in', 'check_out', 'cliente_ausente'));
