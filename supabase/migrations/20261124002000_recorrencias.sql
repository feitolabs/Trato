-- ===========================================================================
-- 20261124002000_recorrencias.sql
-- RASCUNHO. NÃO aplicada no Supabase de produção. Aguarda o OK do João para aplicar.
--
-- Objetivo: estrutura de "Serviço Recorrente" (decisões aprovadas em 23/11/2026,
-- docs/decisoes-indicacao-e-recorrencia.md). Recorrência nasce sempre a partir de
-- um serviço já realizado (`pedido_origem_id`), sem cobrança automática: cada
-- visita vira um pedido quando o cliente confirma e paga.
--
-- Mudanças (somente aditivas e idempotentes):
--   1. Tabela `public.recorrencias`: série recorrente (semanal, quinzenal, mensal),
--      valores em centavos inteiros (> 0), suporte a reajuste proposto pelo
--      profissional (`valor_proposto_centavos`), status e bloqueio de partes iguais.
--   2. Tabela `public.recorrencia_visitas`: ocorrências agendadas da série, com
--      vínculo opcional ao `pedido_id` quando confirmada/paga.
--   3. Índices: `ux_recorrencia_visitas_recorrencia_data` (único por série/data),
--      `ix_recorrencia_visitas_status_data`, `ix_recorrencias_cliente_status` e
--      `ix_recorrencias_profissional_status`.
--   4. RLS habilitada em ambas as tabelas, sem policies para `anon`/`authenticated`,
--      grants restritos a `service_role` (select, insert, update).
--
-- Rollback: supabase/rollback/20261124002000_recorrencias_rollback.sql
-- ===========================================================================

begin;

create table if not exists public.recorrencias (
  id                      uuid primary key default gen_random_uuid(),
  cliente_id              uuid not null references public.usuarios (id),
  profissional_id         uuid not null references public.usuarios (id),
  pedido_origem_id        uuid not null references public.pedidos (id),
  categoria_id            uuid references public.categorias (id),
  frequencia              text not null
                            check (frequencia in ('semanal', 'quinzenal', 'mensal')),
  valor_centavos          integer not null check (valor_centavos > 0),
  valor_proposto_centavos integer check (valor_proposto_centavos is null or valor_proposto_centavos > 0),
  proxima_visita_em       timestamptz not null,
  status                  text not null default 'proposta'
                            check (status in ('proposta', 'ativa', 'pausada', 'cancelada')),
  proposto_por            uuid not null references public.usuarios (id),
  cancelado_por           uuid references public.usuarios (id),
  cancelado_em            timestamptz,
  criado_em               timestamptz not null default now(),
  atualizado_em           timestamptz not null default now(),
  constraint recorrencias_partes_distintas_check check (cliente_id <> profissional_id)
);

comment on table public.recorrencias is
  'Séries de serviço recorrente (semanal, quinzenal ou mensal) criadas a partir de um pedido já realizado, com aprovação manual de cada visita.';

create index if not exists ix_recorrencias_cliente_status
  on public.recorrencias (cliente_id, status);

create index if not exists ix_recorrencias_profissional_status
  on public.recorrencias (profissional_id, status);

create table if not exists public.recorrencia_visitas (
  id               uuid primary key default gen_random_uuid(),
  recorrencia_id   uuid not null references public.recorrencias (id) on delete cascade,
  data_prevista_em timestamptz not null,
  status           text not null default 'agendada'
                     check (status in ('agendada', 'confirmada_paga', 'pulada', 'expirada', 'cancelada')),
  pedido_id        uuid references public.pedidos (id),
  pulada_por       uuid references public.usuarios (id),
  criado_em        timestamptz not null default now()
);

comment on table public.recorrencia_visitas is
  'Visitas individuais de uma série recorrente; pedido_id é preenchido quando o cliente confirma e paga a visita.';

create unique index if not exists ux_recorrencia_visitas_recorrencia_data
  on public.recorrencia_visitas (recorrencia_id, data_prevista_em);

create index if not exists ix_recorrencia_visitas_status_data
  on public.recorrencia_visitas (status, data_prevista_em);

-- RLS ligada sem policy para o app; acesso exclusivo do backend via service_role.
alter table public.recorrencias enable row level security;
revoke all on table public.recorrencias from public, anon, authenticated, service_role;
grant select, insert, update on table public.recorrencias to service_role;

alter table public.recorrencia_visitas enable row level security;
revoke all on table public.recorrencia_visitas from public, anon, authenticated, service_role;
grant select, insert, update on table public.recorrencia_visitas to service_role;

commit;
