-- Financeiro do painel (07/11/2026): contestação de cartão, fechamento mensal e trava do mês.
-- AINDA NÃO APLICADA no Supabase: precisa do OK do João. Idempotente. Não apaga nem altera dado.
--
--   1. contestacoes: chargeback avisado pelo provedor (charge.dispute.*). Status, valor, prazo para
--      mandar provas e resultado. O histórico completo fica em eventos_webhook.
--   2. fechamentos_mensais: o retrato do mês fechado (totais + hash). Imutável depois de gravado.
--   3. Trava: o ledger recusa lançamento com data dentro de um mês já fechado. Correção de mês
--      fechado entra como estorno no mês corrente (o ledger já é só de inclusão).
--   4. Definição de configuração: depois de quantos minutos um pagamento parado vira alerta.
--
-- Rollback em supabase/rollback/20261108120000_financeiro_contestacoes_fechamento_rollback.sql.

begin;

-- 1. Contestações --------------------------------------------------------------------------------
create table if not exists public.contestacoes (
  id                       uuid primary key default gen_random_uuid(),
  provedor                 text not null default 'stripe' check (btrim(provedor) <> ''),
  provedor_contestacao_id  text not null check (btrim(provedor_contestacao_id) <> ''),
  cobranca_id              text,                               -- id da cobrança no provedor
  pedido_id                uuid references public.pedidos (id) on delete restrict,
  valor_centavos           bigint not null check (valor_centavos > 0),
  motivo                   text,                               -- código do provedor (fraudulent…)
  status                   text not null
                             check (status in ('aberta', 'em_analise', 'ganha', 'perdida', 'encerrada')),
  prazo_provas             timestamptz,
  aberta_em                timestamptz not null,
  atualizada_em            timestamptz not null,
  encerrada_em             timestamptz,
  unique (provedor, provedor_contestacao_id)
);
create index if not exists contestacoes_pedido_idx on public.contestacoes (pedido_id);
create index if not exists contestacoes_status_idx on public.contestacoes (status);
alter table public.contestacoes enable row level security;
grant select, insert, update on table public.contestacoes to service_role;
comment on table public.contestacoes is
  'Contestação de cartão (chargeback) avisada pelo provedor. Sem DELETE: o histórico é do financeiro.';

-- 2. Fechamento mensal ---------------------------------------------------------------------------
create table if not exists public.fechamentos_mensais (
  mes          date primary key check (extract(day from mes) = 1),  -- primeiro dia do mês
  totais       jsonb not null,
  hash         text not null check (length(hash) = 64),
  fechado_por  uuid not null references public.usuarios (id) on delete restrict,
  fechado_em   timestamptz not null default now(),
  motivo       text not null check (length(btrim(motivo)) >= 10)
);
drop trigger if exists fechamentos_mensais_imutavel on public.fechamentos_mensais;
create trigger fechamentos_mensais_imutavel before update or delete on public.fechamentos_mensais
  for each row execute function public.bloquear_alteracao();
drop trigger if exists fechamentos_mensais_sem_truncate on public.fechamentos_mensais;
create trigger fechamentos_mensais_sem_truncate before truncate on public.fechamentos_mensais
  for each statement execute function public.bloquear_alteracao();
alter table public.fechamentos_mensais enable row level security;
grant select, insert on table public.fechamentos_mensais to service_role;

-- 3. Trava do mês fechado ------------------------------------------------------------------------
-- O mês é o do horário de Brasília (o mesmo do relatório do contador).
create or replace function public.recusar_lancamento_em_mes_fechado()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.fechamentos_mensais f
     where f.mes = date_trunc('month', new.ocorrido_em at time zone 'America/Sao_Paulo')::date
  ) then
    raise exception 'O mês de % já foi fechado: corrija com um estorno no mês corrente.',
      to_char(new.ocorrido_em at time zone 'America/Sao_Paulo', 'MM/YYYY')
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
revoke execute on function public.recusar_lancamento_em_mes_fechado() from public, anon, authenticated;
drop trigger if exists lancamentos_mes_fechado on public.lancamentos;
create trigger lancamentos_mes_fechado before insert on public.lancamentos
  for each row execute function public.recusar_lancamento_em_mes_fechado();

-- 4. Prazo do alerta de pagamento parado ---------------------------------------------------------
insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values ('alerta_pagamento_parado_minutos', 'Alerta de pagamento sem confirmação', 'minutos', 5, 1440, array['global'], true)
on conflict (chave) do nothing;

commit;
