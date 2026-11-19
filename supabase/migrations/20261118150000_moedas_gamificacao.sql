-- Gamificação: moedas do Trato (fase 1 = bônus por avaliar).
-- Livro SEPARADO do ledger de dinheiro: moeda não é dinheiro e não entra na contabilidade financeira.
-- Só acrescenta (nunca edita nem apaga); correção é estorno. Saldo = soma dos lançamentos.
-- Só o backend (service_role) escreve e lê; RLS ligada e sem policy para o app.
-- APLICADA no Supabase Trato em 2026-11-18 com o OK do João (ativo = false). Rollback em supabase/rollback/.

begin;

create table public.moedas_config (
  id                        boolean primary key default true check (id),  -- linha única
  ativo                     boolean not null default false,
  bonus_avaliacao_moedas    integer not null default 50 check (bonus_avaliacao_moedas >= 0),
  valor_moeda_centavos      integer not null default 1 check (valor_moeda_centavos >= 0),
  teto_mensal_moedas        integer not null default 500 check (teto_mensal_moedas >= 0),
  min_servico_centavos      integer not null default 5000 check (min_servico_centavos >= 0),
  max_bonus_por_profissional_mes integer not null default 1 check (max_bonus_por_profissional_mes >= 0),
  validade_dias             integer check (validade_dias is null or validade_dias > 0),
  atualizado_em             timestamptz not null default now()
);
insert into public.moedas_config (id) values (true);

create table public.moedas_lancamentos (
  id                 uuid primary key default gen_random_uuid(),
  usuario_id         uuid not null references public.usuarios (id) on delete restrict,
  tipo               text not null check (tipo in ('bonus_avaliacao', 'estorno', 'uso', 'ajuste')),
  quantidade         integer not null check (quantidade <> 0),  -- + credita, - debita
  chave_idempotencia text not null unique,
  parceiro_id        uuid references public.usuarios (id) on delete restrict,  -- ex.: o profissional avaliado
  referencia_id      uuid,           -- ex.: o pedido avaliado
  expira_em          timestamptz,
  criada_em          timestamptz not null default now()
);
create index moedas_lancamentos_usuario_idx on public.moedas_lancamentos (usuario_id, criada_em desc);

create trigger moedas_lancamentos_imutavel before update or delete on public.moedas_lancamentos
  for each row execute function public.bloquear_alteracao();
create trigger moedas_lancamentos_sem_truncate before truncate on public.moedas_lancamentos
  for each statement execute function public.bloquear_alteracao();

alter table public.moedas_config enable row level security;
alter table public.moedas_lancamentos enable row level security;

revoke all on table public.moedas_config, public.moedas_lancamentos
  from public, anon, authenticated, service_role;
grant select, update on table public.moedas_config to service_role;
grant select, insert on table public.moedas_lancamentos to service_role;

commit;
