-- ===========================================================================
-- 20261127092000_tratinhos_guarda_restauracao.sql
-- RASCUNHO (DB-GUARDA-TRATINHOS). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 13.10 e I.11: encerrada pelo Trato SEM FALTA do usuário, os Tratinhos não usados
-- são mantidos por 90 dias, para uso caso a conta seja restabelecida.
-- Depende de 20261125150000 (moedas_saldo), 20261125224600 e 20261126213500.
--
--   1. medidas_conta.sem_falta (só encerramento, nunca junto de infracao_grave). Pode passar de
--      false para true (correção a favor do usuário); de true não volta.
--   2. moedas_lancamentos: tipo 'restauracao' (positivo, com nova validade), uma vez por medida e
--      carteira, chave 'restauracao:<medida_id>:<carteira>', referencia_id = medida.
--   3. moedas_restauracao_devida(medida, carteira, agora): quanto venceu desde o encerramento
--      (saldo válido no início da medida menos o válido agora). Os que não venceram continuam no
--      livro e voltam a valer com a conta: não se lançam de novo.
--
-- ESCOLHAS onde o texto não define (a favor do consumidor; confirmar com o João):
--   a) medida REVERTIDA: restaura em qualquer data, mesmo com sem_falta false (o encerramento foi
--      desfeito); b) sem reversão, só com pedido de retorno APROVADO, feito até 90 dias do início,
--      e medida sem_falta; c) nova validade de no mínimo 30 dias (igual à 13.8).
--
-- O livro continua imutável. Nenhum dado existente é alterado.
-- Rollback: supabase/rollback/20261127092000_tratinhos_guarda_restauracao_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.moedas_saldo(uuid,text,timestamptz)') is null
     or to_regclass('public.conta_pedidos_retorno') is null then
    raise exception 'Aplique antes as migrations 20261125150000 e 20261126213500';
  end if;
end;
$$;

alter table public.medidas_conta add column if not exists sem_falta boolean not null default false;
alter table public.medidas_conta drop constraint if exists medidas_conta_sem_falta_check;
alter table public.medidas_conta add constraint medidas_conta_sem_falta_check
  check (not sem_falta or (tipo = 'encerramento' and not infracao_grave));

create or replace function public.medidas_conta_sem_falta_proteger()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.sem_falta and not new.sem_falta then
    raise exception 'Encerramento marcado como sem falta não volta atrás'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.medidas_conta_sem_falta_proteger() from public, anon, authenticated, service_role;
drop trigger if exists medidas_conta_sem_falta_trg on public.medidas_conta;
create trigger medidas_conta_sem_falta_trg before update on public.medidas_conta
  for each row execute function public.medidas_conta_sem_falta_proteger();

alter table public.moedas_lancamentos drop constraint if exists moedas_lancamentos_tipo_check;
alter table public.moedas_lancamentos add constraint moedas_lancamentos_tipo_check
  check (tipo in ('bonus_avaliacao', 'estorno', 'uso', 'ajuste', 'bonus_avaliacao_profissional',
                  'exclusividade_uso', 'exclusividade_estorno', 'bonus_indicacao', 'restauracao'));

alter table public.moedas_lancamentos drop constraint if exists moedas_lancamentos_restauracao_check;
alter table public.moedas_lancamentos add constraint moedas_lancamentos_restauracao_check
  check (case when tipo = 'restauracao'
              then quantidade > 0 and referencia_id is not null
                   and expira_em is not null and expira_em >= criada_em + interval '720 hours'
                   and chave_idempotencia = 'restauracao:' || referencia_id::text || ':' || carteira
              else chave_idempotencia not like 'restauracao:%' end);

create or replace function public.moedas_restauracao_devida(
  p_medida uuid, p_carteira text, p_agora timestamptz default now())
returns integer
language sql stable security definer set search_path = ''
as $$
  select greatest(public.moedas_saldo(m.usuario_id, p_carteira, m.inicio_em)
                  - public.moedas_saldo(m.usuario_id, p_carteira, greatest(p_agora, m.inicio_em)), 0)::integer
    from public.medidas_conta m
   where m.id = p_medida and m.tipo = 'encerramento';
$$;
revoke all on function public.moedas_restauracao_devida(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.moedas_restauracao_devida(uuid, text, timestamptz) to service_role;

create or replace function public.moedas_restauracao_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_m       record;
  v_desde   timestamptz;
  v_devida  integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('moedas_restauracao:' || new.usuario_id::text, 0));
  -- repetição: deixa o índice único responder (on conflict do nothing continua funcionando)
  if exists (select 1 from public.moedas_lancamentos l where l.chave_idempotencia = new.chave_idempotencia) then
    return new;
  end if;
  select m.usuario_id, m.tipo, m.sem_falta, m.inicio_em, m.revertida_em into v_m
    from public.medidas_conta m where m.id = new.referencia_id for share;
  if not found or v_m.tipo <> 'encerramento' or v_m.usuario_id is distinct from new.usuario_id then
    raise exception 'Restauração exige um encerramento do próprio usuário' using errcode = 'check_violation';
  end if;
  v_desde := v_m.revertida_em;
  if v_desde is null and v_m.sem_falta then
    select min(r.decidido_em) into v_desde from public.conta_pedidos_retorno r
     where r.medida_id = new.referencia_id and r.status = 'aprovado'
       and r.solicitado_em <= v_m.inicio_em + interval '2160 hours';
  end if;
  if v_desde is null then
    raise exception 'Restauração exige a conta restabelecida (medida revertida ou retorno aprovado no prazo)'
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.medidas_conta o
              where o.usuario_id = new.usuario_id and o.id <> new.referencia_id
                and o.tipo = 'encerramento' and o.revertida_em is null
                and not exists (select 1 from public.conta_pedidos_retorno r
                                 where r.medida_id = o.id and r.status = 'aprovado')) then
    raise exception 'Há outro encerramento em vigor para este usuário' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.moedas_lancamentos l
              where l.usuario_id = new.usuario_id and l.carteira = new.carteira
                and l.tipo = 'restauracao' and l.criada_em >= v_m.inicio_em) then
    raise exception 'Os Tratinhos deste período já foram restaurados' using errcode = 'check_violation';
  end if;
  if new.criada_em < v_desde - interval '5 minutes' or new.criada_em > now() + interval '5 minutes' then
    raise exception 'Data da restauração fora do intervalo (do restabelecimento até agora)'
      using errcode = 'check_violation';
  end if;
  v_devida := public.moedas_restauracao_devida(new.referencia_id, new.carteira, new.criada_em);
  if new.quantidade > coalesce(v_devida, 0) then
    raise exception 'Restauração de % passa do devido (%)', new.quantidade, coalesce(v_devida, 0)
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.moedas_restauracao_validar() from public, anon, authenticated, service_role;
drop trigger if exists moedas_restauracao_validar_trg on public.moedas_lancamentos;
create trigger moedas_restauracao_validar_trg before insert on public.moedas_lancamentos
  for each row when (new.tipo = 'restauracao')
  execute function public.moedas_restauracao_validar();

commit;
