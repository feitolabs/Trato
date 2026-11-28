-- ===========================================================================
-- 20261127213000_exclusividade_prazo_falha.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, 22.3: falha da plataforma prorroga o prazo de resposta da oferta de
-- exclusividade pelo tempo da falha. Mesma conta de backend/src/trato/disputas/
-- indisponibilidade.py (unir + prorrogar): janelas que se sobrepõem ou encostam contam
-- uma vez; falha que começa dentro da própria prorrogação também conta; falha ativa que
-- alcança o prazo o suspende.
--
-- ORIGEM CONSIDERADA: só 'app' (responder a oferta é ato no aplicativo e não passa pelo
-- Parceiro de Pagamento). O backend ainda não define a origem deste ato: CONFIRMAR.
--
-- Cria public.exclusividade_prazo_resposta e recria exclusividade_responder e
-- exclusividade_expirar (versão da 20261125223000) mudando só a comparação do prazo.
-- Assinaturas iguais. A coluna responder_ate NÃO é alterada. Sem UPDATE de dados ao
-- aplicar; sem mudança em tabela ou livro. Oferta já expirada não volta.
--
-- Depende de 20261125223000 e 20261127205000. Se a 20261125150000 ou a 20261125223000
-- rodarem de novo, rodar esta de novo.
-- Rollback: supabase/rollback/20261127213000_exclusividade_prazo_falha_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.janelas_indisponibilidade') is null then
    raise exception 'Pré-requisito ausente: public.janelas_indisponibilidade (aplicar 20261127205000 primeiro).';
  end if;
  if to_regprocedure('public.exclusividade_cliente_expirar(timestamptz)') is null then
    raise exception 'Pré-requisito ausente: aplicar 20261125223000 (exclusividade do cliente) primeiro.';
  end if;
end $$;

-- Vencimento efetivo da resposta. Nulo = suspenso (falha ativa alcançando o prazo).
create or replace function public.exclusividade_prazo_resposta(
  p_criada_em timestamptz, p_responder_ate timestamptz)
returns timestamptz
language plpgsql stable security definer set search_path = ''
as $$
declare
  j        record;
  v_limite timestamptz := p_responder_ate;
  v_inicio timestamptz;
  v_fim    timestamptz;  -- do bloco unido em montagem; nulo = ainda ativo
begin
  if p_criada_em is null or p_responder_ate is null then
    raise exception 'parâmetros inválidos para o prazo de resposta da exclusividade';
  end if;

  for j in select i.inicio_em, i.fim_em from public.janelas_indisponibilidade i
            where i.origem in ('app')
              and (i.fim_em is null or i.fim_em > p_criada_em)
            order by i.inicio_em
  loop
    if v_inicio is not null and (v_fim is null or j.inicio_em <= v_fim) then
      -- sobrepõe ou encosta: junta (aberta vence qualquer fim)
      if v_fim is not null and (j.fim_em is null or j.fim_em > v_fim) then
        v_fim := j.fim_em;
      end if;
      continue;
    end if;
    -- fecha o bloco anterior
    if v_inicio is not null then
      if v_inicio > v_limite then
        return v_limite;
      end if;
      -- bloco anterior fechado (um bloco ativo absorve todos os seguintes)
      v_limite := v_limite + (v_fim - greatest(v_inicio, p_criada_em));
    end if;
    v_inicio := j.inicio_em;
    v_fim := j.fim_em;
  end loop;

  if v_inicio is not null and v_inicio <= v_limite then
    if v_fim is null then
      return null;
    end if;
    v_limite := v_limite + (v_fim - greatest(v_inicio, p_criada_em));
  end if;
  return v_limite;
end;
$$;

revoke all on function public.exclusividade_prazo_resposta(timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.exclusividade_prazo_resposta(timestamptz, timestamptz) to service_role;

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
  v_limite timestamptz;
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
  select e.id, e.profissional_id, e.pedido_id, e.status, e.criada_em, e.responder_ate, e.moedas_cobradas into v_exc
    from public.exclusividades e where e.id = p_exclusividade for update;

  if v_exc.status = 'expirada_sem_resposta' then
    return query select 'prazo_vencido'::text, null::timestamptz;
    return;
  end if;
  if v_exc.status <> 'aguardando_cliente' then
    return query select 'ja_respondida'::text, null::timestamptz;
    return;
  end if;

  -- prazo vencido (já com a prorrogação por falha, 22.3; nulo = suspenso): marca como a rotina e estorna
  v_limite := public.exclusividade_prazo_resposta(v_exc.criada_em, v_exc.responder_ate);
  if v_limite < p_agora then
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
    -- 22.3: o filtro pelo prazo original só escolhe candidatas; quem decide é o prazo prorrogado
    -- (nulo = suspenso por falha ativa: a comparação não é verdadeira e a oferta fica).
    update public.exclusividades e
       set status = 'expirada_sem_resposta', encerrada_em = p_agora, atualizado_em = p_agora
     where e.id = r.id and e.status = 'aguardando_cliente' and e.responder_ate < p_agora
       and public.exclusividade_prazo_resposta(e.criada_em, e.responder_ate) < p_agora
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

commit;
