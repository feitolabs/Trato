-- ===========================================================================
-- 20261127061000_contrato_versao_termos.sql
-- RASCUNHO (DB-TERMOS-100). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 5.3 (a Contratação ocorre quando o pagamento é confirmado), 23.6 e 23.7.
--
--   1. public.termos_versoes: histórico das versões (versão e dia em que passa a valer, no
--      horário de Brasília). Versão em vigor ou passada não muda nem se apaga.
--   2. contratos.termos_versao e contratos.termos_registrada_em: gravadas pelo BANCO na primeira
--      confirmação de pagamento (tipo diferente de 'aditivo'). Escrita única. Sem versão
--      cadastrada para o dia, ficam nulas (o pagamento não é bloqueado).
-- Só acrescenta; nenhum dado existente é alterado.
--
-- DADO DE CONFIGURAÇÃO: as versões entram por supabase/seeds/seed_termos_e_config_100.sql.
-- CONTRATOS JÁ CONFIRMADOS: preencher à parte, com OK próprio, DEPOIS do seed (grava dados):
--   update public.contratos c
--      set termos_versao = public.termos_versao_vigente(g.em), termos_registrada_em = g.em
--     from (select contrato_id, min(confirmado_em) as em from public.pagamentos
--            where confirmado_em is not null and tipo <> 'aditivo' group by contrato_id) g
--    where c.id = g.contrato_id and c.termos_versao is null
--      and public.termos_versao_vigente(g.em) is not null;
--
-- Rollback: supabase/rollback/20261127061000_contrato_versao_termos_rollback.sql
-- ===========================================================================

begin;

create table if not exists public.termos_versoes (
  versao        text primary key check (versao ~ '^[0-9]+\.[0-9]+$'),
  vigente_desde date not null unique,
  hash_texto    text check (hash_texto is null or hash_texto ~ '^[0-9a-f]{64}$'),
  criada_em     timestamptz not null default now()
);

create or replace function public.termos_versoes_proteger()
returns trigger
language plpgsql set search_path = ''
as $$
declare
  v_hoje date := (now() at time zone interval '-3 hours')::date;
begin
  if tg_op = 'INSERT' then
    return new;
  end if;
  if old.vigente_desde <= v_hoje then
    raise exception 'Versão dos Termos em vigor ou passada não muda' using errcode = 'restrict_violation';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke all on function public.termos_versoes_proteger() from public, anon, authenticated, service_role;
drop trigger if exists termos_versoes_proteger_trg on public.termos_versoes;
create trigger termos_versoes_proteger_trg before update or delete on public.termos_versoes
  for each row execute function public.termos_versoes_proteger();
drop trigger if exists termos_versoes_sem_truncate on public.termos_versoes;
create trigger termos_versoes_sem_truncate before truncate on public.termos_versoes
  for each statement execute function public.bloquear_alteracao();
alter table public.termos_versoes enable row level security;
revoke all on table public.termos_versoes from public, anon, authenticated, service_role;
grant select, insert on table public.termos_versoes to service_role;

create or replace function public.termos_versao_vigente(p_em timestamptz default now())
returns text
language sql stable security definer set search_path = ''
as $$
  select v.versao from public.termos_versoes v
   where v.vigente_desde <= (p_em at time zone interval '-3 hours')::date
   order by v.vigente_desde desc
   limit 1;
$$;
revoke all on function public.termos_versao_vigente(timestamptz) from public, anon, authenticated;
grant execute on function public.termos_versao_vigente(timestamptz) to service_role;

alter table public.contratos
  add column if not exists termos_versao text references public.termos_versoes (versao) on delete restrict,
  add column if not exists termos_registrada_em timestamptz;
alter table public.contratos drop constraint if exists contratos_termos_par_check;
alter table public.contratos add constraint contratos_termos_par_check
  check ((termos_versao is null) = (termos_registrada_em is null));

create or replace function public.contratos_termos_proteger()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.termos_versao is not null or new.termos_registrada_em is not null then
      raise exception 'A versão dos Termos é gravada na confirmação do pagamento'
        using errcode = 'check_violation';
    end if;
  elsif old.termos_versao is not null
        and (new.termos_versao, new.termos_registrada_em)
            is distinct from (old.termos_versao, old.termos_registrada_em) then
    raise exception 'A versão dos Termos do contrato não muda' using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.contratos_termos_proteger() from public, anon, authenticated, service_role;
drop trigger if exists contratos_termos_proteger_trg on public.contratos;
create trigger contratos_termos_proteger_trg before insert or update on public.contratos
  for each row execute function public.contratos_termos_proteger();

create or replace function public.pagamentos_registrar_termos()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_em     timestamptz := coalesce(new.confirmado_em, now());
  v_versao text := public.termos_versao_vigente(coalesce(new.confirmado_em, now()));
begin
  if v_versao is not null then
    update public.contratos
       set termos_versao = v_versao, termos_registrada_em = v_em
     where id = new.contrato_id and termos_versao is null;
  end if;
  return null;
end;
$$;
revoke all on function public.pagamentos_registrar_termos() from public, anon, authenticated, service_role;
drop trigger if exists pagamentos_registrar_termos_trg on public.pagamentos;
create trigger pagamentos_registrar_termos_trg after insert or update of status on public.pagamentos
  for each row when (new.status = 'confirmado' and new.tipo <> 'aditivo')
  execute function public.pagamentos_registrar_termos();

commit;
