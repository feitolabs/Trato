-- Recusa de pedido aberto pelo profissional ("não tenho interesse"). Fonte: docs/api-rotas.md.
--
-- STATUS: APLICADA no Supabase em 30/10/2026 com o OK do João.
-- Só DDL. Depende da F3.3 (pedidos) e da F3.2 (perfis_profissional).
-- Reversão: supabase/rollback/pedido_recusas_rollback.sql
--
-- Por quê: o profissional precisa tirar um pedido da sua lista sem que o cliente seja avisado
-- ou o pedido mude de estado. A recusa é só do profissional; o motivo ajuda a calibrar a
-- vitrine e a moderação. Uma recusa por par (pedido, profissional): repetir não muda nada.

create table public.pedido_recusas (
  pedido_id       uuid not null references public.pedidos (id) on delete restrict,
  profissional_id uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  motivo          text not null check (btrim(motivo) <> '' and char_length(motivo) <= 500),
  criada_em       timestamptz not null default now(),
  primary key (pedido_id, profissional_id)
);
create index pedido_recusas_profissional_idx on public.pedido_recusas (profissional_id, criada_em desc);
create trigger pedido_recusas_sem_update before update on public.pedido_recusas
  for each row execute function public.bloquear_alteracao();
create trigger pedido_recusas_sem_delete before delete on public.pedido_recusas
  for each row execute function public.bloquear_alteracao();
alter table public.pedido_recusas enable row level security;

-- O profissional lê as próprias recusas; toda escrita é do backend.
create policy pedido_recusas_ler_proprio on public.pedido_recusas
  for select to authenticated using (profissional_id = (select auth.uid()));

revoke all on table public.pedido_recusas from public, anon, authenticated, service_role;
grant select on table public.pedido_recusas to authenticated;
grant select, insert on table public.pedido_recusas to service_role;
