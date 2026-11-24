-- ===========================================================================
-- 20261123232000_reagendamentos.sql
-- RASCUNHO. NÃO aplicada no Supabase de produção. Aguarda o OK do João para aplicar.
--
-- Objetivo: armazenar propostas de reagendamento da janela de atendimento de um
-- pedido (sem cancelar o pedido). Cliente ou profissional propõe nova data/hora;
-- a outra parte aceita ou recusa (ou o proponente cancela).
--
-- Mudanças (somente aditivas e idempotentes):
--   1. Tabela `public.reagendamentos` com constraints de motivo (<= 500 chars),
--      status ('pendente', 'aceito', 'recusado', 'cancelado') e janela válida
--      (`nova_janela_fim > nova_janela_inicio`).
--   2. Índice único parcial `ux_reagendamentos_pedido_pendente`: garante no máximo
--      1 proposta `pendente` por pedido.
--   3. Índice `ix_reagendamentos_pedido_criado_em` em `(pedido_id, criado_em desc)`
--      para listagem rápida do histórico de propostas do pedido.
--   4. RLS habilitada sem policies para `anon`/`authenticated`; grants restritos
--      a `service_role` (select, insert, update), seguindo o padrão de `exclusividades`.
--
-- Rollback: supabase/rollback/20261123232000_reagendamentos_rollback.sql
-- ===========================================================================

begin;

create table if not exists public.reagendamentos (
  id                 uuid primary key default gen_random_uuid(),
  pedido_id          uuid not null references public.pedidos (id) on delete cascade,
  proposto_por       uuid not null references public.usuarios (id),
  nova_janela_inicio timestamptz not null,
  nova_janela_fim    timestamptz not null,
  motivo             text not null default '' check (char_length(motivo) <= 500),
  status             text not null default 'pendente'
                       check (status in ('pendente', 'aceito', 'recusado', 'cancelado')),
  respondido_por     uuid references public.usuarios (id),
  respondido_em      timestamptz,
  criado_em          timestamptz not null default now(),
  constraint reagendamentos_janela_check check (nova_janela_fim > nova_janela_inicio)
);

comment on table public.reagendamentos is
  'Propostas de reagendamento da janela de atendimento de um pedido (cliente ou profissional propõe; a outra parte aceita ou recusa).';

-- No máximo 1 proposta pendente por pedido.
create unique index if not exists ux_reagendamentos_pedido_pendente
  on public.reagendamentos (pedido_id)
  where status = 'pendente';

-- Listagem rápida das propostas de um pedido (mais recentes primeiro).
create index if not exists ix_reagendamentos_pedido_criado_em
  on public.reagendamentos (pedido_id, criado_em desc);

-- RLS ligada sem policy para o app; acesso exclusivo do backend via service_role.
alter table public.reagendamentos enable row level security;
revoke all on table public.reagendamentos from public, anon, authenticated, service_role;
grant select, insert, update on table public.reagendamentos to service_role;

commit;
