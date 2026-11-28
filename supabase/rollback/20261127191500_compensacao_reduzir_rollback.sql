-- Rollback de 20261127191500_compensacao_reduzir.sql
-- RASCUNHO (DB-COMP-REDUZIR). NÃO aplicado no Supabase de produção.
-- Preserva dados: trava se houver redução. Volta as funções da 061000 e da 195000.
-- Rodar ANTES dos rollbacks delas.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.compensacoes_reducoes') is not null then
    lock table public.compensacoes_reducoes in access exclusive mode;
    execute 'select exists (select 1 from public.compensacoes_reducoes)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há reduções de dívida no livro';
    end if;
  end if;
end;
$$;

create or replace function public.compensacao_origem_revista(p_divida uuid)
returns boolean
language sql volatile security definer set search_path = ''
as $$
  select exists (
    select 1
      from public.compensacoes_dividas dv
      join public.disputas d on d.id = dv.disputa_id
      left join public.disputa_contestacoes o
        on dv.origem_tipo = 'disputa_contestacao' and o.id = dv.origem_id
      join public.disputa_contestacoes x
        on x.disputa_id = d.id and x.status in ('alterada', 'revertida')
       and x.id is distinct from o.id and (o.id is null or x.decidida_em >= o.decidida_em)
     where dv.id = p_divida
       and public.compensacao_reembolso(x.nova_decisao, x.novo_valor_reembolso_centavos, d.valor_congelado_centavos)
           < case when o.id is null
                  then public.compensacao_reembolso(d.decisao, d.valor_reembolso_centavos, d.valor_congelado_centavos)
                  else public.compensacao_reembolso(o.nova_decisao, o.novo_valor_reembolso_centavos, d.valor_congelado_centavos)
             end);
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
      - coalesce((select sum(d.valor_centavos) from public.compensacoes_dividas d
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
      - coalesce((select sum(d.valor_centavos) from public.compensacoes_dividas d
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

create or replace function public.compensacao_aplicar(p_contrato uuid, p_chave text)
returns table (resultado text, aplicado_centavos bigint, liberado_restante_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_prof     uuid;
  v_saldo    bigint;
  v_payout   bigint;
  v_tirado   bigint;
  v_aberto   bigint;
  v_x        bigint;
  v_total    bigint := 0;
  v_lanc     uuid;
  r          record;
begin
  if p_contrato is null or p_chave is null or btrim(p_chave) = '' then
    raise exception 'contrato e chave são obrigatórios';
  end if;
  select c.profissional_id into v_prof from public.contratos c where c.id = p_contrato for update;
  if not found then
    return query select 'contrato_nao_encontrado'::text, 0::bigint, 0::bigint;
    return;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('compensacao:' || v_prof::text, 0));
  -- só o que ainda não foi pago: o saldo 'liberado' menos o que saiu por payout
  v_payout := public.compensacao_pago_por_payout(p_contrato, v_prof);
  v_saldo := greatest(public.compensacao_saldo(p_contrato, 'liberado', v_prof) - v_payout, 0);

  if exists (select 1 from public.compensacoes_aplicadas a where a.chave_idempotencia = p_chave) then
    if exists (select 1 from public.compensacoes_aplicadas a
                where a.chave_idempotencia = p_chave and a.contrato_id <> p_contrato) then
      raise exception 'chave de idempotência já usada em outro contrato';
    end if;
    return query select 'ja_aplicada'::text,
      (select sum(a.valor_centavos)::bigint from public.compensacoes_aplicadas a
        where a.chave_idempotencia = p_chave), v_saldo;
    return;
  end if;

  select coalesce(sum(a.valor_centavos), 0) into v_tirado from public.compensacoes_aplicadas a
   where a.contrato_id = p_contrato
     and not exists (select 1 from public.lancamentos e where e.estorna_id = a.lancamento_id);

  for r in select d.id, d.valor_centavos, d.criada_em, d.disputa_id from public.compensacoes_dividas d
            where d.profissional_id = v_prof and d.status = 'aberta' and d.avisado_em is not null
            order by d.criada_em, d.id
            for update
  loop
    exit when v_saldo <= 0;
    if public.compensacao_origem_revista(r.id) then
      continue;  -- decisão revertida ou reduzida: cancelamento manual
    end if;
    v_aberto := r.valor_centavos - public.compensacao_compensado(r.id);
    v_x := least(v_aberto, v_saldo,
                 public.compensacao_compensavel_desde(p_contrato, v_prof, r.criada_em) - v_tirado);
    if v_x <= 0 then
      continue;
    end if;
    v_lanc := public.compensacao_lancar(
      p_contrato, 'repasse',
      public.compensacao_conta('liberado', v_prof),
      public.compensacao_conta('a_compensar', v_prof),
      v_x, 'comp/' || p_chave || '/' || r.id::text,
      'Compensação em repasse (Termos 8.6 e 17.4)', r.disputa_id, null, null);
    insert into public.compensacoes_aplicadas (divida_id, contrato_id, lancamento_id, valor_centavos, chave_idempotencia)
    values (r.id, p_contrato, v_lanc, v_x, p_chave);
    v_saldo := v_saldo - v_x;
    v_tirado := v_tirado + v_x;
    v_total := v_total + v_x;
    if v_x = v_aberto then
      update public.compensacoes_dividas set status = 'quitada' where id = r.id;
    end if;
  end loop;

  return query select case when v_total > 0 then 'ok' else 'nada_a_compensar' end, v_total, v_saldo;
end;
$$;

create or replace function public.compensacao_cancelar(p_divida uuid, p_analista uuid, p_motivo text)
returns table (resultado text, devolvido_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_d      record;
  v_total  bigint := 0;
  r        record;
begin
  if p_divida is null or p_analista is null or p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'dívida, analista e motivo são obrigatórios';
  end if;
  -- cancelar devolve dinheiro: só líder de suporte ou administrador
  if not public.compensacao_papel_ok(p_analista, '{lider_suporte,administrador}') then
    return query select 'analista_invalido'::text, 0::bigint;
    return;
  end if;
  select d.contrato_id, d.profissional_id into v_d from public.compensacoes_dividas d where d.id = p_divida;
  if not found then
    return query select 'nao_encontrada'::text, 0::bigint;
    return;
  end if;
  -- o estorno escreve nos contratos já compensados, e compensacao_aplicar segura o contrato
  -- antes do profissional: travar todos os contratos dele PRIMEIRO, em ordem, evita deadlock
  perform 1 from public.contratos c where c.profissional_id = v_d.profissional_id order by c.id for update;
  perform pg_advisory_xact_lock(hashtextextended('compensacao:' || v_d.profissional_id::text, 0));
  select d.contrato_id, d.profissional_id, d.status, d.valor_centavos, d.disputa_id into v_d
    from public.compensacoes_dividas d where d.id = p_divida for update;
  if v_d.status = 'cancelada' then
    return query select 'ja_cancelada'::text, 0::bigint;
    return;
  end if;

  for r in select a.lancamento_id, a.contrato_id, a.valor_centavos from public.compensacoes_aplicadas a
            where a.divida_id = p_divida
              and not exists (select 1 from public.lancamentos e where e.estorna_id = a.lancamento_id)
            order by a.criada_em, a.id
  loop
    perform public.compensacao_lancar(
      r.contrato_id, 'estorno',
      public.compensacao_conta('a_compensar', v_d.profissional_id),
      public.compensacao_conta('liberado', v_d.profissional_id),
      r.valor_centavos, 'comp/estorno/' || r.lancamento_id::text,
      'Estorno de compensação contestada', v_d.disputa_id, r.lancamento_id, p_analista);
    v_total := v_total + r.valor_centavos;
  end loop;
  perform public.compensacao_lancar(
    v_d.contrato_id, 'reembolso',
    public.compensacao_conta('taxa_trato', null),
    public.compensacao_conta('a_compensar', v_d.profissional_id),
    v_d.valor_centavos, 'comp/assume/' || p_divida::text,
    'Dívida cancelada: o Trato assume o reembolso', v_d.disputa_id, null, p_analista);
  update public.compensacoes_dividas
     set status = 'cancelada', cancelada_em = now(), cancelada_por = p_analista,
         motivo_cancelamento = btrim(p_motivo)
   where id = p_divida;
  perform public.registrar_auditoria(
    p_analista, 'equipe', 'financeiro.compensacao_cancelada', 'compensacao', p_divida,
    jsonb_build_object('status', v_d.status), jsonb_build_object('devolvido_centavos', v_total),
    btrim(p_motivo), null, null, null);
  return query select 'ok'::text, v_total;
end;
$$;

revoke all on function public.compensacao_origem_revista(uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_criar_divida(text, uuid, uuid, uuid, bigint, bigint, text, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_aplicar(uuid, text) from public, anon, authenticated;
grant execute on function public.compensacao_aplicar(uuid, text) to service_role;
revoke all on function public.compensacao_cancelar(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.compensacao_cancelar(uuid, uuid, text) to service_role;

drop function if exists public.compensacao_reduzir(uuid, uuid, bigint, text, uuid);
drop function if exists public.compensacao_valor_efetivo(uuid);
drop function if exists public.compensacao_estornado_ao_cliente(uuid);
drop table if exists public.compensacoes_reducoes;

commit;
