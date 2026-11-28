-- ===========================================================================
-- Rollback de 20261128010000_checkout_sem_codigo_fase2.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Trava se houver qualquer decisão gravada (ou chave_idempotencia preenchida).
-- Restaura a trava da fase 1 e a função de validação da 20261127230000.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint;
begin
  if to_regclass('public.checkout_sem_codigo_casos') is null then
    return;
  end if;

  lock table public.checkout_sem_codigo_casos in access exclusive mode;

  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'checkout_sem_codigo_casos'
       and column_name = 'chave_idempotencia'
  ) then
    execute 'select count(*) from public.checkout_sem_codigo_casos
              where decidido_em is not null
                 or analista_id is not null
                 or decisao is not null
                 or justificativa is not null
                 or chave_idempotencia is not null' into v_qtd;
  else
    execute 'select count(*) from public.checkout_sem_codigo_casos
              where decidido_em is not null
                 or analista_id is not null
                 or decisao is not null
                 or justificativa is not null' into v_qtd;
  end if;

  if v_qtd > 0 then
    raise exception 'Rollback bloqueado: existem % caso(s) com decisão gravada em public.checkout_sem_codigo_casos.', v_qtd;
  end if;
end $$;

drop index if exists public.checkout_sem_codigo_casos_idempotencia_uidx;

alter table public.checkout_sem_codigo_casos
  drop constraint if exists checkout_sem_codigo_casos_decisao_completa_check,
  drop constraint if exists checkout_sem_codigo_casos_decisao_valor_check,
  drop constraint if exists checkout_sem_codigo_casos_justificativa_check,
  drop constraint if exists checkout_sem_codigo_casos_idempotencia_check,
  drop constraint if exists checkout_sem_codigo_casos_fase1_check;

alter table public.checkout_sem_codigo_casos
  drop column if exists chave_idempotencia;

alter table public.checkout_sem_codigo_casos
  add constraint checkout_sem_codigo_casos_fase1_check
    check (num_nulls(analista_id, decisao, justificativa, decidido_em) = 4);

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

commit;
