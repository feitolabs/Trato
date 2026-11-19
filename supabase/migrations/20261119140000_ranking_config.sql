-- Ranking de profissionais na busca: pesos da nota composta e da média ponderada.
-- Linha única. Só o backend (service_role) lê e escreve; RLS ligada e sem policy para o app.
-- A conta fica em backend/src/trato/profissional/ranking.py; aqui só os números.
-- NÃO APLICADA: precisa do OK do João. Rollback em supabase/rollback/.

begin;

create table public.ranking_config (
  id                boolean primary key default true check (id),  -- linha única
  nota_prior        numeric(3, 2) not null default 4.00 check (nota_prior between 0 and 5),
  prior_avaliacoes  integer not null default 5 check (prior_avaliacoes between 0 and 1000),
  volume_referencia integer not null default 20 check (volume_referencia between 1 and 10000),
  peso_nota         integer not null default 60 check (peso_nota between 0 and 1000),
  peso_volume       integer not null default 20 check (peso_volume between 0 and 1000),
  peso_verificacao  integer not null default 10 check (peso_verificacao between 0 and 1000),
  peso_disponivel   integer not null default 10 check (peso_disponivel between 0 and 1000),
  atualizado_em     timestamptz not null default now(),
  check (peso_nota + peso_volume + peso_verificacao + peso_disponivel > 0)
);
insert into public.ranking_config (id) values (true);

alter table public.ranking_config enable row level security;

revoke all on table public.ranking_config from public, anon, authenticated, service_role;
grant select, update on table public.ranking_config to service_role;

commit;
