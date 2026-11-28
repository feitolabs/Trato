-- Rollback de 20261128040000_compensacao_conta_reembolso_retido.sql
-- Volta as duas funções ao texto da 20261127191500. Não mexe em dados. ATENÇÃO: volta o teto que
-- ignora o reembolso direto do saldo retido; religar antes a trava 'reembolso_direto_na_disputa'
-- no backend. Rodar ANTES do rollback da 191500. Pode rodar de novo.

begin;

do $$
begin
  if to_regclass('public.compensacoes_reducoes') is null
     or to_regprocedure('public.compensacao_estornado_ao_cliente(uuid)') is null then
    raise exception 'Aplique antes a 20261127191500_compensacao_reduzir';
  end if;
end;
$$;

create or replace function public.compensacao_estornado_ao_cliente(p_disputa uuid)
returns bigint
language sql volatile security definer set search_path = ''
as $$
  select greatest(coalesce(sum(case pa.sentido when 'credito' then pa.valor_centavos
                                                else -pa.valor_centavos end), 0), 0)::bigint
    from public.disputas ds
    join public.lancamentos l on l.contrato_id = ds.contrato_id and l.criado_em >= ds.aberta_em
    join public.partidas pa on pa.lancamento_id = l.id
    join public.contas_ledger c on c.id = pa.conta_id and c.codigo = 'cliente_externo'
   where ds.id = p_disputa
     and (l.tipo = 'estorno' or (l.tipo = 'cobranca' and l.chave_idempotencia like '%/mantida/%'));
$$;

create or replace function public.compensacao_criar_divida(
  p_origem_tipo text, p_origem_id uuid, p_contrato uuid, p_disputa uuid, p_valor bigint,
  p_teto_decisao bigint, p_motivo text, p_analista uuid, p_aprovador uuid, p_operador uuid)
returns table (resultado text, divida_id uuid, maximo_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ctr     record;
  v_exist   record;
  v_max     bigint;
  v_chargeback bigint;
  v_lanc    uuid;
  v_id      uuid;
begin
  -- travas, sempre nesta ordem: contrato (a mesma do livro do backend) e depois o profissional
  select c.id, c.pedido_id, c.profissional_id into v_ctr
    from public.contratos c where c.id = p_contrato for update;
  if not found then
    return query select 'contrato_nao_encontrado'::text, null::uuid, 0::bigint;
    return;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('compensacao:' || v_ctr.profissional_id::text, 0));

  select d.id, d.valor_centavos, d.contrato_id into v_exist
    from public.compensacoes_dividas d where d.origem_tipo = p_origem_tipo and d.origem_id = p_origem_id;
  if found then
    return query select case when v_exist.valor_centavos = p_valor and v_exist.contrato_id = p_contrato
                             then 'ja_registrada' else 'conflito' end,
                        v_exist.id, v_exist.valor_centavos;
    return;
  end if;

  -- nunca mais que: o repassado deste contrato sem dívida, o que o cliente ainda tem pago e,
  -- quando há disputa, o reembolso decidido menos o já devolvido desde a abertura
  v_max := least(
    public.compensacao_liberado_desde(p_contrato, v_ctr.profissional_id, '-infinity')
      - coalesce((select sum(public.compensacao_valor_efetivo(d.id)) from public.compensacoes_dividas d
                   where d.contrato_id = p_contrato and d.status <> 'cancelada'), 0),
    -public.compensacao_saldo(p_contrato, 'cliente_externo', null));
  -- 6.11: contestação de cartão perdida já devolveu dinheiro ao cliente pelo banco. É
  -- descontada inteira (se o livro já a refletir, o teto fica menor, nunca maior).
  select coalesce(sum(k.valor_centavos), 0) into v_chargeback
    from public.contestacoes k where k.pedido_id = v_ctr.pedido_id and k.status = 'perdida';
  v_max := least(v_max, -public.compensacao_saldo(p_contrato, 'cliente_externo', null) - v_chargeback);  if p_teto_decisao is not null then
    v_max := least(v_max,
      p_teto_decisao
      - greatest(coalesce((
          select sum(case pa.sentido when 'credito' then pa.valor_centavos else -pa.valor_centavos end)
            from public.lancamentos l
            join public.partidas pa on pa.lancamento_id = l.id
            join public.contas_ledger c on c.id = pa.conta_id and c.codigo = 'cliente_externo'
            join public.disputas ds on ds.id = p_disputa
           where l.contrato_id = p_contrato and l.criado_em >= ds.aberta_em
             and (l.tipo = 'estorno' or (l.tipo = 'cobranca' and l.chave_idempotencia like '%/mantida/%'))), 0), 0)
      - coalesce((select sum(public.compensacao_valor_efetivo(d.id)) from public.compensacoes_dividas d
                   where d.disputa_id = p_disputa and d.status <> 'cancelada'), 0));
  end if;
  v_max := greatest(v_max, 0);
  if p_valor > v_max then
    return query select 'acima_do_devido'::text, null::uuid, v_max;
    return;
  end if;

  v_lanc := public.compensacao_lancar(
    p_contrato, 'reembolso',
    public.compensacao_conta('a_compensar', v_ctr.profissional_id),
    public.compensacao_conta('cliente_externo', null),
    p_valor, 'comp/divida/' || p_origem_tipo || '/' || p_origem_id::text,
    'Reembolso decidido após o repasse (Termos 8.6 e 17.4)', p_disputa, null, p_operador);
  insert into public.compensacoes_dividas
    (contrato_id, pedido_id, profissional_id, origem_tipo, origem_id, disputa_id, valor_centavos, motivo,
     analista_id, aprovada_por, registrada_por, lancamento_id)
  values (p_contrato, v_ctr.pedido_id, v_ctr.profissional_id, p_origem_tipo, p_origem_id, p_disputa, p_valor,
          btrim(p_motivo), p_analista, p_aprovador, p_operador, v_lanc)
  returning id into v_id;
  perform public.registrar_auditoria(
    p_operador, 'equipe', 'financeiro.compensacao_registrada', 'compensacao', v_id, null,
    jsonb_build_object('valor_centavos', p_valor, 'origem_tipo', p_origem_tipo, 'origem_id', p_origem_id,
                       'contrato_id', p_contrato, 'analista_id', p_analista, 'aprovada_por', p_aprovador),
    btrim(p_motivo), null, null, null);
  return query select 'ok'::text, v_id, v_max;
end;
$$;

revoke all on function public.compensacao_estornado_ao_cliente(uuid) from public, anon, authenticated;
grant execute on function public.compensacao_estornado_ao_cliente(uuid) to service_role;
revoke all on function public.compensacao_criar_divida(text, uuid, uuid, uuid, bigint, bigint, text, uuid, uuid, uuid) from public, anon, authenticated, service_role;

commit;
