-- ===========================================================================
-- 20261127191500_compensacao_reduzir.sql
-- RASCUNHO (DB-COMP-REDUZIR). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 8.6, 8.7 e 17.4. Depende de 20261126061000 e 20261126195000.
--
-- Contestação que ALTERA a decisão para menos permite reduzir a dívida em vez de cancelar.
--   * valor efetivo = valor_centavos - soma das reduções (aplicar, tetos e cancelar usam ele);
--   * livro: taxa_trato (débito) -> a_compensar (crédito) só da diferença. NADA em
--     cliente_externo e nenhuma ordem de estorno: o Trato absorve o já devolvido ao cliente;
--   * descontado acima do novo valor volta ao profissional: estorno do desconto e novo
--     lançamento liberado -> a_compensar do que continua devido (pares já existentes);
--   * só reduz decisão que baixa a base atual (teto menor e não anterior a ela); "posterior"
--     é por (decidida_em, id), como no backend;
--   * teto = reembolso da contestação - outras dívidas da disputa - estorno direto ao cliente;
--     exige efeito financeiro diferente de 'nenhum' e nenhuma decisão posterior que a supere;
--   * a contestação usada deixa de suspender a dívida e vira a nova base de comparação.
-- Nenhum dado existente é alterado.
--
-- Rollback: supabase/rollback/20261127191500_compensacao_reduzir_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.compensacao_papel_ok(uuid,text[])') is null then
    raise exception 'Aplique antes as migrations 20261126061000 e 20261126195000';
  end if;
end;
$$;

create table if not exists public.compensacoes_reducoes (
  id                  uuid primary key default gen_random_uuid(),
  divida_id           uuid not null references public.compensacoes_dividas (id) on delete restrict,
  contestacao_id      uuid not null references public.disputa_contestacoes (id) on delete restrict,
  reducao_centavos    bigint not null check (reducao_centavos > 0),
  novo_valor_centavos bigint not null check (novo_valor_centavos > 0),
  devolvido_centavos  bigint not null check (devolvido_centavos >= 0),
  lancamento_id       uuid not null unique references public.lancamentos (id) on delete restrict,
  operador            uuid not null references public.equipe (usuario_id) on delete restrict,
  motivo              text not null check (btrim(motivo) <> ''),
  criada_em           timestamptz not null default now(),
  constraint compensacoes_reducoes_contestacao_unica unique (contestacao_id)
);
create index if not exists ix_compensacoes_reducoes_divida on public.compensacoes_reducoes (divida_id);

drop trigger if exists compensacoes_reducoes_imutavel on public.compensacoes_reducoes;
create trigger compensacoes_reducoes_imutavel before update or delete on public.compensacoes_reducoes
  for each row execute function public.bloquear_alteracao();
drop trigger if exists compensacoes_reducoes_sem_truncate on public.compensacoes_reducoes;
create trigger compensacoes_reducoes_sem_truncate before truncate on public.compensacoes_reducoes
  for each statement execute function public.bloquear_alteracao();
alter table public.compensacoes_reducoes enable row level security;
revoke all on table public.compensacoes_reducoes from public, anon, authenticated, service_role;
grant select on table public.compensacoes_reducoes to service_role;

create or replace function public.compensacao_valor_efetivo(p_divida uuid)
returns bigint
language sql volatile security definer set search_path = ''
as $$
  select (d.valor_centavos - coalesce((select sum(r.reducao_centavos) from public.compensacoes_reducoes r
                                        where r.divida_id = d.id), 0))::bigint
    from public.compensacoes_dividas d where d.id = p_divida;
$$;
revoke all on function public.compensacao_valor_efetivo(uuid) from public, anon, authenticated;
grant execute on function public.compensacao_valor_efetivo(uuid) to service_role;

-- Estorno direto ao cliente desde a abertura da disputa: estornos e o que foi relançado como
-- mantido. É a mesma conta de compensacao_criar_divida. A dívida e a redução são lançamentos
-- 'reembolso' e não entram: nada é contado duas vezes.
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
revoke all on function public.compensacao_estornado_ao_cliente(uuid) from public, anon, authenticated;
grant execute on function public.compensacao_estornado_ao_cliente(uuid) to service_role;

create or replace function public.compensacao_origem_revista(p_divida uuid)
returns boolean
language sql volatile security definer set search_path = ''
as $$
  -- base da comparação: a contestação da redução mais recente; sem redução, a origem da dívida
  with base as (
    select dv.id, d.id as disputa_id, d.valor_congelado_centavos as congelado,
           coalesce(red.id, o.id) as contestacao_id,
           coalesce(red.decidida_em, o.decidida_em) as decidida_em,
           case when coalesce(red.id, o.id) is null
                then public.compensacao_reembolso(d.decisao, d.valor_reembolso_centavos, d.valor_congelado_centavos)
                else public.compensacao_reembolso(coalesce(red.nova_decisao, o.nova_decisao),
                       case when red.id is not null then red.novo_valor_reembolso_centavos
                            else o.novo_valor_reembolso_centavos end,
                       d.valor_congelado_centavos)
           end as teto
      from public.compensacoes_dividas dv
      join public.disputas d on d.id = dv.disputa_id
      left join public.disputa_contestacoes o
        on dv.origem_tipo = 'disputa_contestacao' and o.id = dv.origem_id
      left join lateral (
        select k.id, k.decidida_em, k.nova_decisao, k.novo_valor_reembolso_centavos
          from public.compensacoes_reducoes r
          join public.disputa_contestacoes k on k.id = r.contestacao_id
         where r.divida_id = dv.id
         order by k.decidida_em desc, r.criada_em desc limit 1) red on true
     where dv.id = p_divida
  )
  select exists (
    select 1 from base b
      join public.disputa_contestacoes x
        on x.disputa_id = b.disputa_id and x.status in ('alterada', 'revertida')
       and x.id is distinct from b.contestacao_id
       and (b.contestacao_id is null or x.decidida_em >= b.decidida_em)
     where not exists (select 1 from public.compensacoes_reducoes r
                        where r.divida_id = b.id and r.contestacao_id = x.id)
       and public.compensacao_reembolso(x.nova_decisao, x.novo_valor_reembolso_centavos, b.congelado) < b.teto);
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

  for r in select d.id, d.criada_em, d.disputa_id from public.compensacoes_dividas d
            where d.profissional_id = v_prof and d.status = 'aberta' and d.avisado_em is not null
            order by d.criada_em, d.id
            for update
  loop
    exit when v_saldo <= 0;
    if public.compensacao_origem_revista(r.id) then
      continue;  -- decisão revertida ou reduzida: cancelamento manual
    end if;
    v_aberto := public.compensacao_valor_efetivo(r.id) - public.compensacao_compensado(r.id);
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
  -- as reduções já foram assumidas pelo Trato: falta só o valor efetivo
  perform public.compensacao_lancar(
    v_d.contrato_id, 'reembolso',
    public.compensacao_conta('taxa_trato', null),
    public.compensacao_conta('a_compensar', v_d.profissional_id),
    public.compensacao_valor_efetivo(p_divida), 'comp/assume/' || p_divida::text,
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

create or replace function public.compensacao_reduzir(
  p_divida uuid, p_contestacao uuid, p_novo_valor bigint, p_motivo text, p_operador uuid)
returns table (resultado text, divida_id uuid, devolvido_ao_profissional_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_d        record;
  v_x        record;
  v_feita    record;
  v_base     record;
  v_efetivo  bigint;
  v_teto     bigint;
  v_outras   bigint;
  v_direto   bigint;
  v_reducao  bigint;
  v_excesso  bigint;
  v_falta    bigint;
  v_lanc     uuid;
  v_novo     uuid;
  r          record;
begin
  if p_divida is null or p_contestacao is null or p_novo_valor is null or p_motivo is null
     or btrim(p_motivo) = '' or p_operador is null then
    raise exception 'dívida, contestação, novo valor, motivo e operador são obrigatórios';
  end if;
  if not public.compensacao_papel_ok(p_operador, '{lider_suporte,administrador}') then
    return query select 'analista_invalido'::text, p_divida, 0::bigint;
    return;
  end if;
  select d.profissional_id into v_d from public.compensacoes_dividas d where d.id = p_divida;
  if not found then
    return query select 'nao_encontrada'::text, p_divida, 0::bigint;
    return;
  end if;
  -- mesmas travas do cancelar: contratos do profissional em ordem, profissional e dívida
  perform 1 from public.contratos c where c.profissional_id = v_d.profissional_id order by c.id for update;
  perform pg_advisory_xact_lock(hashtextextended('compensacao:' || v_d.profissional_id::text, 0));
  select d.contrato_id, d.profissional_id, d.status, d.disputa_id, d.origem_tipo, d.origem_id into v_d
    from public.compensacoes_dividas d where d.id = p_divida for update;
  -- a mesma contestação não reduz duas dívidas, nem com chamadas simultâneas
  perform pg_advisory_xact_lock(hashtextextended('compensacao_reducao:' || p_contestacao::text, 0));

  select z.divida_id, z.novo_valor_centavos, z.devolvido_centavos into v_feita
    from public.compensacoes_reducoes z where z.contestacao_id = p_contestacao;
  if found then
    if v_feita.divida_id = p_divida and v_feita.novo_valor_centavos = p_novo_valor then
      return query select 'ja_reduzida'::text, p_divida, v_feita.devolvido_centavos;
    else
      return query select 'conflito'::text, v_feita.divida_id, 0::bigint;
    end if;
    return;
  end if;
  if v_d.status = 'cancelada' then
    return query select 'ja_cancelada'::text, p_divida, 0::bigint;
    return;
  end if;

  select k.disputa_id, k.status, k.aprovada_por, k.efeito_financeiro, k.decidida_em, k.nova_decisao,
         k.novo_valor_reembolso_centavos, ds.valor_congelado_centavos as congelado
    into v_x
    from public.disputa_contestacoes k join public.disputas ds on ds.id = k.disputa_id
   where k.id = p_contestacao for share of k;
  if not found or v_x.disputa_id is distinct from v_d.disputa_id
     or v_x.status <> 'alterada' or v_x.aprovada_por is null or v_x.efeito_financeiro = 'nenhum'
     or (v_d.origem_tipo = 'disputa_contestacao' and (v_d.origem_id = p_contestacao
         or v_x.decidida_em < (select o.decidida_em from public.disputa_contestacoes o where o.id = v_d.origem_id))) then
    return query select 'contestacao_invalida'::text, p_divida, 0::bigint;
    return;
  end if;
  v_teto := public.compensacao_reembolso(v_x.nova_decisao, v_x.novo_valor_reembolso_centavos, v_x.congelado);
  -- superada por qualquer decisão posterior que mudou o resultado, maior ou menor; cobre também
  -- a usada na última redução
  if exists (select 1 from public.disputa_contestacoes y
              where y.disputa_id = v_d.disputa_id and y.id <> p_contestacao
                and y.status in ('alterada', 'revertida')
                and (y.decidida_em, y.id) > (v_x.decidida_em, p_contestacao)) then
    return query select 'decisao_substituida'::text, p_divida, 0::bigint;
    return;
  end if;

  -- só reduz a decisão que BAIXA a base atual (mesma base de compensacao_origem_revista):
  -- a contestação da última redução; sem redução, a de origem da dívida ou a própria disputa
  select coalesce(red.id, o.id) as contestacao_id,
         coalesce(red.decidida_em, o.decidida_em) as decidida_em,
         case when coalesce(red.id, o.id) is null
              then public.compensacao_reembolso(ds.decisao, ds.valor_reembolso_centavos, ds.valor_congelado_centavos)
              else public.compensacao_reembolso(coalesce(red.nova_decisao, o.nova_decisao),
                     case when red.id is not null then red.novo_valor_reembolso_centavos
                          else o.novo_valor_reembolso_centavos end,
                     ds.valor_congelado_centavos)
         end as teto
    into v_base
    from public.compensacoes_dividas dv
    join public.disputas ds on ds.id = dv.disputa_id
    left join public.disputa_contestacoes o
      on dv.origem_tipo = 'disputa_contestacao' and o.id = dv.origem_id
    left join lateral (
      select k.id, k.decidida_em, k.nova_decisao, k.novo_valor_reembolso_centavos
        from public.compensacoes_reducoes z
        join public.disputa_contestacoes k on k.id = z.contestacao_id
       where z.divida_id = dv.id
       order by k.decidida_em desc, z.criada_em desc limit 1) red on true
   where dv.id = p_divida;
  if v_base.contestacao_id = p_contestacao or v_x.decidida_em < v_base.decidida_em
     or v_teto >= v_base.teto then
    return query select 'contestacao_invalida'::text, p_divida, 0::bigint;
    return;
  end if;

  v_efetivo := public.compensacao_valor_efetivo(p_divida);
  -- o teto da contestação vale para a soma das dívidas não canceladas da disputa
  select coalesce(sum(public.compensacao_valor_efetivo(d.id)), 0) into v_outras
    from public.compensacoes_dividas d
   where d.disputa_id = v_d.disputa_id and d.id <> p_divida and d.status <> 'cancelada';
  -- o que já voltou ao cliente por estorno direto também ocupa o teto (como em criar_divida)
  v_direto := public.compensacao_estornado_ao_cliente(v_d.disputa_id);
  if p_novo_valor <= 0 or p_novo_valor >= v_efetivo or p_novo_valor > v_teto - v_outras - v_direto then
    return query select 'valor_invalido'::text, p_divida, 0::bigint;
    return;
  end if;
  v_reducao := v_efetivo - p_novo_valor;
  v_excesso := greatest(public.compensacao_compensado(p_divida) - p_novo_valor, 0);

  -- o Trato absorve só a diferença; o cliente não é tocado
  v_lanc := public.compensacao_lancar(
    v_d.contrato_id, 'reembolso',
    public.compensacao_conta('taxa_trato', null),
    public.compensacao_conta('a_compensar', v_d.profissional_id),
    v_reducao, 'comp/reducao/' || p_contestacao::text,
    'Dívida reduzida por contestação: o Trato assume a diferença', v_d.disputa_id, null, p_operador);
  insert into public.compensacoes_reducoes
    (divida_id, contestacao_id, reducao_centavos, novo_valor_centavos, devolvido_centavos,
     lancamento_id, operador, motivo)
  values (p_divida, p_contestacao, v_reducao, p_novo_valor, v_excesso, v_lanc, p_operador, btrim(p_motivo));

  -- descontado a mais: estorna descontos (do mais novo) e relança só o que continua devido
  v_falta := v_excesso;
  for r in select a.id, a.lancamento_id, a.contrato_id, a.valor_centavos from public.compensacoes_aplicadas a
            where a.divida_id = p_divida
              and not exists (select 1 from public.lancamentos e where e.estorna_id = a.lancamento_id)
            order by a.criada_em desc, a.id desc
  loop
    exit when v_falta <= 0;
    perform public.compensacao_lancar(
      r.contrato_id, 'estorno',
      public.compensacao_conta('a_compensar', v_d.profissional_id),
      public.compensacao_conta('liberado', v_d.profissional_id),
      r.valor_centavos, 'comp/estorno/' || r.lancamento_id::text,
      'Estorno de compensação por redução da dívida', v_d.disputa_id, r.lancamento_id, p_operador);
    if r.valor_centavos > v_falta then
      v_novo := public.compensacao_lancar(
        r.contrato_id, 'repasse',
        public.compensacao_conta('liberado', v_d.profissional_id),
        public.compensacao_conta('a_compensar', v_d.profissional_id),
        r.valor_centavos - v_falta, 'comp/reaplica/' || p_contestacao::text || '/' || r.id::text,
        'Compensação mantida após redução da dívida', v_d.disputa_id, null, p_operador);
      insert into public.compensacoes_aplicadas (divida_id, contrato_id, lancamento_id, valor_centavos, chave_idempotencia)
      values (p_divida, r.contrato_id, v_novo, r.valor_centavos - v_falta,
              'reducao/' || p_contestacao::text || '/' || r.id::text);
    end if;
    v_falta := v_falta - r.valor_centavos;
  end loop;

  if v_d.status = 'aberta' and public.compensacao_compensado(p_divida) >= p_novo_valor then
    update public.compensacoes_dividas set status = 'quitada' where id = p_divida;
  end if;
  perform public.registrar_auditoria(
    p_operador, 'equipe', 'financeiro.compensacao_reduzida', 'compensacao', p_divida,
    jsonb_build_object('valor_efetivo_centavos', v_efetivo),
    jsonb_build_object('valor_efetivo_centavos', p_novo_valor, 'contestacao_id', p_contestacao,
                       'devolvido_centavos', v_excesso),
    btrim(p_motivo), null, null, null);
  return query select 'ok'::text, p_divida, v_excesso;
end;
$$;
revoke all on function public.compensacao_reduzir(uuid, uuid, bigint, text, uuid) from public, anon, authenticated;
grant execute on function public.compensacao_reduzir(uuid, uuid, bigint, text, uuid) to service_role;

revoke all on function public.compensacao_origem_revista(uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_criar_divida(text, uuid, uuid, uuid, bigint, bigint, text, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_aplicar(uuid, text) from public, anon, authenticated;
grant execute on function public.compensacao_aplicar(uuid, text) to service_role;
revoke all on function public.compensacao_cancelar(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.compensacao_cancelar(uuid, uuid, text) to service_role;

commit;
