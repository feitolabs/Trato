-- ===========================================================================
-- 20261128010000_checkout_sem_codigo_fase2.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, 5.7 (fase 2): destrava o registro da decisão administrativa
-- ('liberar' ou 'estornar') em public.checkout_sem_codigo_casos, mantendo a
-- imutabilidade após decidido, bloqueando decisão quando o cliente já respondeu
-- e acrescentando chave_idempotencia opcional com unicidade parcial.
--
-- Nada aqui executa liberação ou estorno sozinho: o Backend coordena o ledger
-- e a transição do Pedido dentro da transação com a decisão.
--
-- Depende de: 20261127230000_checkout_sem_codigo_casos.sql.
-- Só acrescenta (remove apenas a trava temporária da fase 1); sem UPDATE de dados.
-- Rollback: supabase/rollback/20261128010000_checkout_sem_codigo_fase2_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.checkout_sem_codigo_casos') is null then
    raise exception 'Aplique antes a migration 20261127230000_checkout_sem_codigo_casos.sql';
  end if;
end $$;

alter table public.checkout_sem_codigo_casos
  add column if not exists chave_idempotencia text;

alter table public.checkout_sem_codigo_casos
  drop constraint if exists checkout_sem_codigo_casos_fase1_check;

alter table public.checkout_sem_codigo_casos
  drop constraint if exists checkout_sem_codigo_casos_decisao_completa_check,
  drop constraint if exists checkout_sem_codigo_casos_decisao_valor_check,
  drop constraint if exists checkout_sem_codigo_casos_justificativa_check,
  drop constraint if exists checkout_sem_codigo_casos_idempotencia_check;

alter table public.checkout_sem_codigo_casos
  add constraint checkout_sem_codigo_casos_decisao_completa_check
    check (num_nulls(analista_id, decisao, justificativa, decidido_em) in (0, 4)),
  add constraint checkout_sem_codigo_casos_decisao_valor_check
    check (decisao is null or decisao in ('liberar', 'estornar')),
  add constraint checkout_sem_codigo_casos_justificativa_check
    check (
      justificativa is null
      or (char_length(btrim(justificativa)) >= 10 and char_length(justificativa) <= 500)
    ),
  add constraint checkout_sem_codigo_casos_idempotencia_check
    check (
      chave_idempotencia is null
      or (btrim(chave_idempotencia) <> '' and decidido_em is not null)
    );

create unique index if not exists checkout_sem_codigo_casos_idempotencia_uidx
  on public.checkout_sem_codigo_casos (chave_idempotencia)
  where chave_idempotencia is not null;

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
           is distinct from (old.respondido_em, old.resposta))
       or (old.decidido_em is not null and (new.analista_id, new.decisao, new.justificativa, new.decidido_em, new.chave_idempotencia)
           is distinct from (old.analista_id, old.decisao, old.justificativa, old.decidido_em, old.chave_idempotencia)) then
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

  if new.decidido_em is not null and new.respondido_em is not null then
    raise exception 'checkout_sem_codigo_ja_respondido: não é possível gravar decisão e resposta no mesmo caso'
      using errcode = 'check_violation';
  end if;

  if new.decidido_em is not null and (tg_op = 'INSERT' or old.decidido_em is null) then
    if new.contatado_em is null or new.responder_ate is null or new.decidido_em <= new.responder_ate then
      raise exception 'checkout_sem_codigo_prazo_aberto: só é possível decidir após contato e depois de vencer responder_ate'
        using errcode = 'check_violation';
    end if;
    if new.decidido_em < new.check_out_em then
      raise exception 'checkout_sem_codigo_invalido: decisão anterior ao check-out'
        using errcode = 'check_violation';
    end if;
    if not exists (
      select 1 from public.equipe e
       where e.usuario_id = new.analista_id
         and e.ativo
         and e.revogado_em is null
    ) then
      raise exception 'checkout_sem_codigo_analista_inativo: analista precisa estar ativo na equipe'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end $$;
revoke all on function public.checkout_sem_codigo_casos_validar() from public, anon, authenticated, service_role;

commit;
