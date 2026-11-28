-- ===========================================================================
-- Rollback de 20261127220000_orcamento_validade_falha.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Volta exclusividade_cliente_solicitar à versão da 20261125223000 e remove
-- orcamento_validade_vigente. Não mexe em dados nem em exclusividades já criadas.
-- Desfazer antes das rollbacks de 20261127205000 e 20261125223000.
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.orcamento_validade_vigente(timestamptz,timestamptz,timestamptz)') is null then
    raise exception 'Nada a desfazer: public.orcamento_validade_vigente não existe.';
  end if;
end $$;

create or replace function public.exclusividade_cliente_solicitar(
  p_cliente uuid, p_pedido uuid, p_profissional uuid, p_orcamento uuid, p_chave text, p_agora timestamptz,
  p_exigir_mei boolean)  -- o backend passa a configuração TRATO_MEI_OBRIGATORIO
returns table (resultado text, exclusividade_id uuid, expira_em timestamptz, saldo_restante integer)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_custo  integer;
  v_horas  integer;
  v_saldo  bigint;
  v_exist  record;
  v_ped    record;
  v_orc    record;
  v_prof   uuid := p_profissional;
  v_id     uuid;
  v_fim    timestamptz;
begin
  if p_cliente is null or p_pedido is null or p_chave is null or btrim(p_chave) = '' or p_agora is null
     or (p_profissional is null and p_orcamento is null) or p_exigir_mei is null then
    raise exception 'parâmetros inválidos para solicitar exclusividade do cliente';
  end if;

  select c.exclusividade_custo_moedas, c.exclusividade_duracao_horas into v_custo, v_horas
    from public.moedas_config c where c.id;
  if not found then
    raise exception 'moedas_config sem a linha de configuração';
  end if;

  -- lock 1: a MESMA trava da reserva de desconto (o saldo do cliente não é gasto duas vezes)
  perform pg_advisory_xact_lock(hashtextextended(p_cliente::text, 0));

  -- saldo livre = saldo válido menos o que está preso em reservas de desconto abertas
  v_saldo := public.moedas_saldo(p_cliente, 'cliente', p_agora);
  v_saldo := greatest(v_saldo - coalesce((select sum(r.moedas) from public.moedas_reservas r
                                           where r.usuario_id = p_cliente and r.status = 'reservada'), 0), 0);

  select e.id, e.cliente_id, e.pedido_id, e.pagador, e.expira_em into v_exist
    from public.exclusividades e where e.chave_idempotencia = p_chave;
  if found then
    if v_exist.pagador <> 'cliente' or v_exist.cliente_id <> p_cliente or v_exist.pedido_id <> p_pedido then
      raise exception 'chave de idempotência já usada em outra exclusividade';
    end if;
    return query select 'ja_existe'::text, v_exist.id, v_exist.expira_em, v_saldo::integer;
    return;
  end if;

  -- lock 2: o pedido
  select p.cliente_id, p.status, p.expira_em into v_ped
    from public.pedidos p where p.id = p_pedido for update;
  if not found or v_ped.cliente_id <> p_cliente then
    return query select 'nao_encontrado'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;
  if v_ped.status <> 'aberto'
     or (v_ped.expira_em is not null and v_ped.expira_em <= p_agora)
     or exists (select 1 from public.exclusividades e
                 where e.pedido_id = p_pedido and e.status in ('aguardando_cliente', 'ativa')) then
    return query select 'pedido_indisponivel'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if p_orcamento is not null then
    select o.profissional_id, o.status, o.validade_ate into v_orc
      from public.orcamentos o where o.id = p_orcamento and o.pedido_id = p_pedido;
    if not found or v_orc.status <> 'enviado'
       or (v_orc.validade_ate is not null and v_orc.validade_ate <= p_agora)
       or (p_profissional is not null and p_profissional <> v_orc.profissional_id) then
      return query select 'orcamento_invalido'::text, null::uuid, null::timestamptz, v_saldo::integer;
      return;
    end if;
    v_prof := v_orc.profissional_id;
  end if;

  -- não cobra por quem não poderia enviar orçamento neste pedido
  if not public.profissional_pode_orcar(v_prof, p_pedido, p_exigir_mei) then
    return query select 'profissional_indisponivel'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if v_saldo < v_custo then
    return query select 'saldo_insuficiente'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  v_fim := p_agora + make_interval(hours => v_horas);
  insert into public.exclusividades
    (profissional_id, cliente_id, pedido_id, status, moedas_cobradas, chave_idempotencia, criada_em,
     responder_ate, expira_em, atualizado_em, pagador, orcamento_id)
  values (v_prof, p_cliente, p_pedido, 'ativa', v_custo, p_chave, p_agora,
          p_agora, v_fim, p_agora, 'cliente', p_orcamento)
  returning id into v_id;

  insert into public.moedas_lancamentos
    (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, criada_em)
  values (p_cliente, 'exclusividade_uso', -v_custo, 'exclusividade-uso:' || v_id::text,
          v_prof, v_id, 'cliente', p_agora);

  update public.pedidos set status = 'reservado' where id = p_pedido and status = 'aberto';
  insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, motivo, prova, ocorrida_em)
  values (p_pedido, 'aberto', 'reservado', p_cliente, 'exclusividade paga pelo cliente',
          jsonb_build_object('acao', 'reservar_exclusividade', 'papel', 'cliente',
                             'dados', jsonb_build_object('exclusividade_id', v_id)),
          p_agora);

  return query select 'ok'::text, v_id, v_fim, (v_saldo - v_custo)::integer;
end;
$$;

revoke all on function public.exclusividade_cliente_solicitar(uuid, uuid, uuid, uuid, text, timestamptz, boolean) from public, anon, authenticated;
grant execute on function public.exclusividade_cliente_solicitar(uuid, uuid, uuid, uuid, text, timestamptz, boolean) to service_role;

drop function public.orcamento_validade_vigente(timestamptz, timestamptz, timestamptz);

commit;
