-- Dispositivos de push e registro de execuções do agendador.
-- NÃO APLICADA: depende do OK do João (CLAUDE.md). Rollback: supabase/rollback/notificacoes_dispositivos_rollback.sql

create table public.dispositivos_push (
  id            uuid primary key default gen_random_uuid(),
  usuario_id    uuid not null references public.usuarios (id) on delete restrict,
  token         text not null check (btrim(token) <> ''),
  plataforma    text not null check (plataforma in ('android', 'ios', 'web')),
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (token)
);
create index dispositivos_push_usuario_idx on public.dispositivos_push (usuario_id) where ativo;
create trigger dispositivos_push_atualizado_em before update on public.dispositivos_push
  for each row execute function public.definir_atualizado_em();
alter table public.dispositivos_push enable row level security;

-- Uma linha por ação de rotina já executada (chave estável vinda de trato.rotinas).
create table public.agendador_execucoes (
  chave       text primary key check (btrim(chave) <> ''),
  tipo        text not null,
  pedido_id   uuid,
  executada_em timestamptz not null default now()
);
alter table public.agendador_execucoes enable row level security;

revoke all on table public.dispositivos_push, public.agendador_execucoes
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.dispositivos_push to service_role;
grant select, insert on table public.agendador_execucoes to service_role;
