-- ===========================================================================
-- 20261127230000_checkout_sem_codigo_casos.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, 5.7 e Anexo II (fase 1, SEM dinheiro): registro do contato do Trato e da
-- resposta do Cliente quando o Check-out foi feito sem o Código Final. Nada aqui libera,
-- estorna ou muda o Pedido. Silêncio nunca libera: não há rotina, prazo automático nem
-- efeito ao vencer responder_ate. Colunas de decisão travadas em nulo nesta fase.
--
-- QUEM É CASO: só o Pedido em 'em_confirmacao' cujo evento mais recente entre
-- 'fazer_check_out' e 'resolver_retrabalho' no pedido_historico é um 'fazer_check_out'
-- com prova.dados.sem_codigo = true. O retrabalho resolvido NÃO é caso.
-- check_out_em = pedido_historico.ocorrida_em desse evento (não presencas.registrada_em).
--
-- responder_ate: ao menos 5 dias de segunda a sexta depois do dia do contato, no
-- calendário de Brasília (UTC-3). Feriados e o parâmetro configurado são do backend.
-- Valor gravado é o original (prorrogação 22.3 se calcula na leitura).
--
-- Parâmetro: supabase/seeds/seed_config_checkout_sem_codigo.sql.
-- Só acrescenta; sem UPDATE de dados. Depende de F3.2 (equipe, bloquear_alteracao),
-- F3.3 (pedidos, pedido_historico).
--
-- Rollback: supabase/rollback/20261127230000_checkout_sem_codigo_casos_rollback.sql
-- ===========================================================================

begin;

create table if not exists public.checkout_sem_codigo_casos (
  id            uuid primary key default gen_random_uuid(),
  pedido_id     uuid not null references public.pedidos (id) on delete restrict,
  check_out_em  timestamptz not null,
  contatado_em  timestamptz,
  canal         text constraint checkout_sem_codigo_casos_canal_check
                  check (canal is null or btrim(canal) <> ''),
  responder_ate timestamptz,
  respondido_em timestamptz,
  resposta      text constraint checkout_sem_codigo_casos_resposta_check
                  check (resposta is null or btrim(resposta) <> ''),
  analista_id   uuid references public.equipe (usuario_id) on delete restrict,
  decisao       text,
  justificativa text,
  decidido_em   timestamptz,
  criado_em     timestamptz not null default now(),
  constraint checkout_sem_codigo_casos_contato_check
    check (num_nulls(contatado_em, canal, responder_ate) in (0, 3)),
  constraint checkout_sem_codigo_casos_prazo_check
    check (responder_ate is null or responder_ate > contatado_em),
  constraint checkout_sem_codigo_casos_respondido_check
    check (num_nulls(respondido_em, resposta) in (0, 2)),
  -- fase 1: a fase de decisão remove este check em migration própria
  constraint checkout_sem_codigo_casos_fase1_check
    check (num_nulls(analista_id, decisao, justificativa, decidido_em) = 4)
);
create unique index if not exists checkout_sem_codigo_casos_unico_uidx
  on public.checkout_sem_codigo_casos (pedido_id, check_out_em);
create index if not exists checkout_sem_codigo_casos_prazo_idx
  on public.checkout_sem_codigo_casos (responder_ate) where respondido_em is null;
create index if not exists checkout_sem_codigo_casos_analista_idx
  on public.checkout_sem_codigo_casos (analista_id) where analista_id is not null;

-- Instante do Check-out sem código VIGENTE do Pedido; nulo = não há caso.
create or replace function public.checkout_sem_codigo_vigente(p_pedido uuid)
returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select case when u.acao = 'fazer_check_out' and u.sem_codigo = 'true' then u.ocorrida_em end
    from public.pedidos p
    cross join lateral (
      select h.prova ->> 'acao' as acao, h.prova -> 'dados' ->> 'sem_codigo' as sem_codigo, h.ocorrida_em
        from public.pedido_historico h
       where h.pedido_id = p.id and h.prova ->> 'acao' in ('fazer_check_out', 'resolver_retrabalho')
       order by h.id desc limit 1) u
   where p.id = p_pedido and p.status = 'em_confirmacao';
$$;
revoke all on function public.checkout_sem_codigo_vigente(uuid) from public, anon, authenticated;
grant execute on function public.checkout_sem_codigo_vigente(uuid) to service_role;

create or replace function public.checkout_sem_codigo_casos_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_dias integer;
begin
  if tg_op = 'INSERT' then
    -- trava o pedido: o estado não muda entre a conferência e a gravação
    perform 1 from public.pedidos p where p.id = new.pedido_id for share;
    if public.checkout_sem_codigo_vigente(new.pedido_id) is distinct from new.check_out_em then
      raise exception 'checkout_sem_codigo_invalido: o pedido não tem esse check-out sem código vigente'
        using errcode = 'check_violation';
    end if;
  else
    if (new.id, new.pedido_id, new.check_out_em, new.criado_em)
       is distinct from (old.id, old.pedido_id, old.check_out_em, old.criado_em)
       or (old.contatado_em is not null and (new.contatado_em, new.canal, new.responder_ate)
           is distinct from (old.contatado_em, old.canal, old.responder_ate))
       or (old.respondido_em is not null and (new.respondido_em, new.resposta)
           is distinct from (old.respondido_em, old.resposta)) then
      raise exception 'checkout_sem_codigo_imutavel: dado já registrado não pode ser alterado'
        using errcode = 'restrict_violation';
    end if;
  end if;

  -- contato incompleto cai no check de contato
  if num_nulls(new.contatado_em, new.canal, new.responder_ate) = 0 and (tg_op = 'INSERT' or old.contatado_em is null) then
    if new.contatado_em < new.check_out_em then
      raise exception 'checkout_sem_codigo_invalido: contato anterior ao check-out'
        using errcode = 'check_violation';
    end if;
    select count(*) into v_dias
      from generate_series(
             (new.contatado_em at time zone interval '-3 hours')::date + 1,
             (new.responder_ate at time zone interval '-3 hours')::date,
             interval '1 day') d
     where extract(isodow from d) < 6;
    if v_dias < 5 then
      raise exception 'checkout_sem_codigo_prazo_curto: responder_ate precisa dar ao menos 5 dias úteis (Brasília)'
        using errcode = 'check_violation';
    end if;
  end if;
  if new.respondido_em is not null and new.respondido_em < new.check_out_em then
    raise exception 'checkout_sem_codigo_invalido: resposta anterior ao check-out'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function public.checkout_sem_codigo_casos_validar() from public, anon, authenticated, service_role;

drop trigger if exists checkout_sem_codigo_casos_validar_trg on public.checkout_sem_codigo_casos;
create trigger checkout_sem_codigo_casos_validar_trg before insert or update on public.checkout_sem_codigo_casos
  for each row execute function public.checkout_sem_codigo_casos_validar();
drop trigger if exists checkout_sem_codigo_casos_sem_delete on public.checkout_sem_codigo_casos;
create trigger checkout_sem_codigo_casos_sem_delete before delete on public.checkout_sem_codigo_casos
  for each row execute function public.bloquear_alteracao();
drop trigger if exists checkout_sem_codigo_casos_sem_truncate on public.checkout_sem_codigo_casos;
create trigger checkout_sem_codigo_casos_sem_truncate before truncate on public.checkout_sem_codigo_casos
  for each statement execute function public.bloquear_alteracao();

alter table public.checkout_sem_codigo_casos enable row level security;
revoke all on table public.checkout_sem_codigo_casos from public, anon, authenticated, service_role;
grant select, insert, update on table public.checkout_sem_codigo_casos to service_role;

commit;
