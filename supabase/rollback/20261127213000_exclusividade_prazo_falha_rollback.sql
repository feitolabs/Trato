-- ===========================================================================
-- Rollback de 20261127213000_exclusividade_prazo_falha.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Volta exclusividade_responder e exclusividade_expirar à versão da 20261125223000 e
-- remove exclusividade_prazo_resposta. Não mexe em dados.
-- ATENÇÃO: depois dele, oferta que só estava de pé pela prorrogação (22.3) é expirada
-- no próximo ciclo. Desfazer antes das rollbacks de 20261127205000 e 20261125223000.
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.exclusividade_prazo_resposta(timestamptz,timestamptz)') is null then
    raise exception 'Nada a desfazer: public.exclusividade_prazo_resposta não existe.';
  end if;
end $$;

create or replace function public.exclusividade_responder(
  p_exclusividade uuid, p_cliente uuid, p_decisao text, p_agora timestamptz, p_duracao_horas integer)
returns table (resultado text, expira_em timestamptz)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ini  record;
  v_exc  record;
  v_ped  record;
  v_rows integer;
  v_fim  timestamptz;
begin
  if p_exclusividade is null or p_cliente is null or p_agora is null
     or p_decisao is null or p_decisao not in ('aceitar', 'recusar')
     or p_duracao_horas is null or p_duracao_horas <= 0 then
    raise exception 'parâmetros inválidos para responder exclusividade';
  end if;

  -- leitura sem lock só para achar o pedido (pedido_id e cliente_id nunca mudam)
  select e.pedido_id, e.cliente_id, e.pagador into v_ini from public.exclusividades e where e.id = p_exclusividade;
  if not found or v_ini.cliente_id <> p_cliente or v_ini.pagador <> 'profissional' then
    return query select 'nao_encontrada'::text, null::timestamptz;
    return;
  end if;

  -- lock 2: pedido; lock 3: exclusividade
  select p.status into v_ped from public.pedidos p where p.id = v_ini.pedido_id for update;
  select e.id, e.profissional_id, e.pedido_id, e.status, e.responder_ate, e.moedas_cobradas into v_exc
    from public.exclusividades e where e.id = p_exclusividade for update;

  if v_exc.status = 'expirada_sem_resposta' then
    return query select 'prazo_vencido'::text, null::timestamptz;
    return;
  end if;
  if v_exc.status <> 'aguardando_cliente' then
    return query select 'ja_respondida'::text, null::timestamptz;
    return;
  end if;

  -- prazo vencido: marca como a rotina e estorna
  if v_exc.responder_ate < p_agora then
    update public.exclusividades
       set status = 'expirada_sem_resposta', encerrada_em = p_agora, atualizado_em = p_agora
     where id = p_exclusividade and status = 'aguardando_cliente';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', p_exclusividade, p_cliente, v_exc.moedas_cobradas, p_agora);
    end if;
    return query select 'prazo_vencido'::text, null::timestamptz;
    return;
  end if;

  if p_decisao = 'recusar' then
    update public.exclusividades
       set status = 'recusada', respondida_em = p_agora, encerrada_em = p_agora, atualizado_em = p_agora
     where id = p_exclusividade and status = 'aguardando_cliente';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', p_exclusividade, p_cliente, v_exc.moedas_cobradas, p_agora);
    end if;
    return query select 'ok'::text, null::timestamptz;
    return;
  end if;

  -- aceitar: o pedido precisa seguir 'aberto'; senão cancela a oferta com estorno
  if v_ped.status is distinct from 'aberto' then
    update public.exclusividades
       set status = 'cancelada', respondida_em = p_agora, encerrada_em = p_agora, atualizado_em = p_agora
     where id = p_exclusividade and status = 'aguardando_cliente';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', p_exclusividade, p_cliente, v_exc.moedas_cobradas, p_agora);
    end if;
    return query select 'pedido_indisponivel'::text, null::timestamptz;
    return;
  end if;

  v_fim := p_agora + make_interval(hours => p_duracao_horas);
  update public.exclusividades
     set status = 'ativa', respondida_em = p_agora, expira_em = v_fim, atualizado_em = p_agora
   where id = p_exclusividade and status = 'aguardando_cliente';

  update public.pedidos set status = 'reservado' where id = v_exc.pedido_id and status = 'aberto';
  insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, motivo, prova, ocorrida_em)
  values (v_exc.pedido_id, 'aberto', 'reservado', p_cliente, 'exclusividade aceita pelo cliente',
          jsonb_build_object('acao', 'reservar_exclusividade', 'papel', 'cliente', 'dados', jsonb_build_object('exclusividade_id', p_exclusividade)),
          p_agora);

  return query select 'ok'::text, v_fim;
end;
$$;

create or replace function public.exclusividade_expirar(p_agora timestamptz)
returns table (exclusividade_id uuid, motivo text, profissional_id uuid, cliente_id uuid, pedido_id uuid)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  r      record;
  v_lock uuid;
  v_exc  record;
  v_rows integer;
begin
  if p_agora is null then
    raise exception 'p_agora é obrigatório';
  end if;

  -- (a) ofertas sem resposta no prazo: expiram COM estorno
  for r in select e.id, e.pedido_id from public.exclusividades e
            where e.pagador = 'profissional' and e.status = 'aguardando_cliente' and e.responder_ate < p_agora
            order by e.responder_ate
  loop
    -- lock 2 (pula se outra transação já está com o pedido); lock 3 pelo update condicional
    select p.id into v_lock from public.pedidos p where p.id = r.pedido_id for update skip locked;
    if not found then
      continue;
    end if;
    update public.exclusividades e
       set status = 'expirada_sem_resposta', encerrada_em = p_agora, atualizado_em = p_agora
     where e.id = r.id and e.status = 'aguardando_cliente' and e.responder_ate < p_agora
    returning e.id, e.profissional_id, e.cliente_id, e.pedido_id, e.moedas_cobradas into v_exc;
    if not found then
      continue;
    end if;
    perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', v_exc.id, v_exc.cliente_id, v_exc.moedas_cobradas, p_agora);
    return query select v_exc.id, 'sem_resposta'::text, v_exc.profissional_id, v_exc.cliente_id, v_exc.pedido_id;
  end loop;

  -- (b) exclusividade ativa que passou das horas sem atendimento: expira SEM estorno; pedido reservado -> aberto
  for r in select e.id, e.pedido_id from public.exclusividades e
            where e.pagador = 'profissional' and e.status = 'ativa' and e.expira_em < p_agora
            order by e.expira_em
  loop
    select p.id into v_lock from public.pedidos p where p.id = r.pedido_id for update skip locked;
    if not found then
      continue;
    end if;
    update public.exclusividades e
       set status = 'expirada_sem_atendimento', encerrada_em = p_agora, atualizado_em = p_agora
     where e.id = r.id and e.status = 'ativa' and e.expira_em < p_agora
    returning e.id, e.profissional_id, e.cliente_id, e.pedido_id into v_exc;
    if not found then
      continue;
    end if;
    update public.pedidos set status = 'aberto' where id = v_exc.pedido_id and status = 'reservado';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, motivo, prova, ocorrida_em)
      values (v_exc.pedido_id, 'reservado', 'aberto', null, 'exclusividade expirou sem atendimento',
              jsonb_build_object('acao', 'expirar_exclusividade', 'papel', 'sistema', 'dados', jsonb_build_object('exclusividade_id', v_exc.id)),
              p_agora);
    end if;
    return query select v_exc.id, 'sem_atendimento'::text, v_exc.profissional_id, v_exc.cliente_id, v_exc.pedido_id;
  end loop;

  return;
end;
$$;

revoke all on function public.exclusividade_responder(uuid, uuid, text, timestamptz, integer) from public, anon, authenticated;
grant execute on function public.exclusividade_responder(uuid, uuid, text, timestamptz, integer) to service_role;
revoke all on function public.exclusividade_expirar(timestamptz) from public, anon, authenticated;
grant execute on function public.exclusividade_expirar(timestamptz) to service_role;

drop function public.exclusividade_prazo_resposta(timestamptz, timestamptz);

commit;
