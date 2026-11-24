-- ===========================================================================
-- 20261124001000_indicacoes.sql
-- RASCUNHO. NÃO aplicada no Supabase de produção. Aguarda o OK do João para aplicar.
--
-- Objetivo: estrutura do programa "Indique e Ganhe Tratinhos" (decisões aprovadas
-- em 23/11/2026, docs/decisoes-indicacao-e-recorrencia.md).
--
-- Mudanças (somente aditivas e idempotentes):
--   1. Tabela `public.codigos_indicacao`: código pessoal único por usuário
--      (6 a 12 caracteres alfanuméricos maiúsculos).
--   2. Tabela `public.indicacoes`: vínculo irrevogável (máx. 1 indicação por
--      `indicado_id`), sem auto-indicação (`indicador_id <> indicado_id`),
--      rastreamento de status, pedido gatilho, bônus em Tratinhos (>= 0) e
--      data prevista de liberação (7 dias sem disputa).
--   3. Índices: `ix_indicacoes_indicador_criado_em` e `ix_indicacoes_status_liberacao`.
--   4. RLS habilitada em ambas as tabelas, sem policies para `anon`/`authenticated`,
--      grants restritos a `service_role` (select, insert, update).
--
-- Rollback: supabase/rollback/20261124001000_indicacoes_rollback.sql
-- ===========================================================================

begin;

create table if not exists public.codigos_indicacao (
  usuario_id uuid primary key references public.usuarios (id) on delete cascade,
  codigo     text not null unique check (codigo ~ '^[A-Z0-9]{6,12}$'),
  criado_em  timestamptz not null default now()
);

comment on table public.codigos_indicacao is
  'Código pessoal único de indicação (6 a 12 caracteres alfanuméricos maiúsculos) por conta de usuário.';

create table if not exists public.indicacoes (
  id                        uuid primary key default gen_random_uuid(),
  indicador_id              uuid not null references public.usuarios (id),
  indicado_id               uuid not null unique references public.usuarios (id),
  codigo_usado              text not null check (codigo_usado ~ '^[A-Z0-9]{6,12}$'),
  tipo                      text not null
                              check (tipo in ('cliente_cliente', 'profissional_cliente', 'profissional_profissional')),
  status                    text not null default 'cadastrado'
                              check (status in ('cadastrado', 'aguardando_liberacao', 'liberado', 'cancelado', 'bloqueado_fraude')),
  pedido_gatilho_id         uuid references public.pedidos (id),
  bonus_indicador_tratinhos integer not null default 0 check (bonus_indicador_tratinhos >= 0),
  bonus_indicado_tratinhos  integer not null default 0 check (bonus_indicado_tratinhos >= 0),
  liberacao_prevista_em     timestamptz,
  liberado_em               timestamptz,
  motivo_bloqueio           text not null default '',
  criado_em                 timestamptz not null default now(),
  constraint indicacoes_sem_autoindicacao_check check (indicador_id <> indicado_id)
);

comment on table public.indicacoes is
  'Indicações do programa Indique e Ganhe Tratinhos (máx. 1 por indicado, sem auto-indicação, liberação após 7 dias sem disputa).';

create index if not exists ix_indicacoes_indicador_criado_em
  on public.indicacoes (indicador_id, criado_em desc);

create index if not exists ix_indicacoes_status_liberacao
  on public.indicacoes (status, liberacao_prevista_em);

-- RLS ligada sem policy para o app; acesso exclusivo do backend via service_role.
alter table public.codigos_indicacao enable row level security;
revoke all on table public.codigos_indicacao from public, anon, authenticated, service_role;
grant select, insert, update on table public.codigos_indicacao to service_role;

alter table public.indicacoes enable row level security;
revoke all on table public.indicacoes from public, anon, authenticated, service_role;
grant select, insert, update on table public.indicacoes to service_role;

commit;
