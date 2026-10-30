-- Ordens de estorno (outbox) e valor já devolvido por pagamento. Correção A7 da revisão de segurança.
-- Fonte: docs/fix-dinheiro.md.
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Só DDL. Depende da F3.5 (pagamentos, lancamentos). Reversão: supabase/rollback/ordens_estorno_rollback.sql
--
-- Por quê: o estorno no provedor tem de ser PRECEDIDO pelo registro da intenção. Fluxo:
--   1. numa transação: lançamentos do ledger (estorno) + a ordem aqui (`pendente`);
--   2. depois do COMMIT: chamar o provedor com `chave_idempotencia` da ordem;
--   3. ao confirmar: `estado = 'enviada'`. Se a chamada falhar, a ordem continua `pendente` e a
--      rotina de reconciliação reenvia (o provedor é idempotente pela mesma chave).
-- Assim nunca sai dinheiro sem registro, e a retentativa não devolve duas vezes.

alter table public.pagamentos
  add column estornado_centavos bigint not null default 0 check (estornado_centavos >= 0);
alter table public.pagamentos
  add constraint pagamentos_estornado_ate_valor check (estornado_centavos <= valor_centavos);

create table public.ordens_estorno (
  id                 uuid primary key default gen_random_uuid(),
  contrato_id        uuid not null references public.contratos (id) on delete restrict,
  pagamento_id       uuid not null references public.pagamentos (id) on delete restrict,
  valor_centavos     bigint not null check (valor_centavos > 0),
  estado             text not null default 'pendente' check (estado in ('pendente', 'enviada')),
  chave_idempotencia text not null unique check (btrim(chave_idempotencia) <> ''),
  provedor_estorno_id text unique,
  criada_em          timestamptz not null default now(),
  enviada_em         timestamptz,
  check ((estado = 'enviada') = (enviada_em is not null))
);
create index ordens_estorno_pendentes_idx on public.ordens_estorno (criada_em) where estado = 'pendente';
create index ordens_estorno_pagamento_idx on public.ordens_estorno (pagamento_id);
-- Só o andamento muda: o que foi pedido (contrato, pagamento, valor, chave) é congelado.
create trigger ordens_estorno_proteger before update on public.ordens_estorno
  for each row execute function public.proteger_colunas(
    'contrato_id', 'pagamento_id', 'valor_centavos', 'chave_idempotencia', 'criada_em');
create trigger ordens_estorno_sem_delete before delete on public.ordens_estorno
  for each row execute function public.bloquear_alteracao();
create trigger ordens_estorno_sem_truncate before truncate on public.ordens_estorno
  for each statement execute function public.bloquear_alteracao();
alter table public.ordens_estorno enable row level security;

-- O pagamento e a ordem precisam ser do mesmo contrato.
create or replace function public.ordens_estorno_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from public.pagamentos where id = new.pagamento_id and contrato_id = new.contrato_id) then
    raise exception 'O pagamento da ordem de estorno é de outro contrato' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger ordens_estorno_validar_trg before insert on public.ordens_estorno
  for each row execute function public.ordens_estorno_validar();

-- Acesso: igual às demais tabelas de dinheiro (anon/authenticated nada; service_role sem DELETE/TRUNCATE).
revoke all on table public.ordens_estorno from public, anon, authenticated, service_role;
grant select, insert, update on table public.ordens_estorno to service_role;
revoke execute on function public.ordens_estorno_validar() from public, anon, authenticated;
