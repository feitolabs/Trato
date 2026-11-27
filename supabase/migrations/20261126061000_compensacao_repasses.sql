-- ===========================================================================
-- 20261126061000_compensacao_repasses.sql
-- RASCUNHO (TERMOS-DB-86). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2: 8.6 e 17.4 (reembolso decidido depois de o valor já ter sido liberado é
-- compensado em repasses futuros, com aviso, motivo e possibilidade de contestar).
-- Depende de F3.5, F3.6, F3.7, 20261108120000 (contestacoes) e 20261125224700_disputa_contestacoes.
--
-- Livro (partidas dobradas, só lançamentos novos). Conta nova 'a_compensar' (por profissional):
--   dívida       tipo 'reembolso': débito a_compensar        -> crédito cliente_externo
--   compensação  tipo 'repasse':   débito liberado (prof)    -> crédito a_compensar
--   contestação  tipo 'estorno' de cada compensação, e 'reembolso': débito taxa_trato ->
--                crédito a_compensar (o Trato assume o que já devolveu ao cliente)
-- O repasse não espera: compensacao_aplicar roda na transação da liberação, antes do saque.
-- Só compensa dívida AVISADA, com valor liberado (a_liberar -> liberado) DEPOIS da dívida.
-- Liberação vinda de payout.paid (chave 'liq/<repasse>' ou evento do provedor) é dinheiro já
-- pago: conta para o teto da dívida, mas NUNCA é compensada.
-- Dívida cuja decisão de origem foi depois revertida ou reduzida por contestação (8.7) não é
-- compensada; o cancelamento é manual (compensacao_cancelar).
-- registrada_por = quem registrou (autor da auditoria); analista_id = quem decidiu/analisou.
--
-- ATENÇÃO: o backend precisa conhecer a conta e os pares novos em financeiro/ledger.py ANTES
-- da primeira chamada, senão não consegue mais carregar o livro do contrato.
--
-- RLS ligada, sem policy; service_role só LÊ as tabelas; escrita apenas pelas funções.
-- Rollback: supabase/rollback/20261126061000_compensacao_repasses_rollback.sql
-- Pré-checagem: supabase/consultas/pre_checagem_termos_db86.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.disputa_contestacoes') is null or to_regclass('public.lancamentos') is null then
    raise exception 'Aplique antes a F3.5 e a 20261125224700_disputa_contestacoes';
  end if;
end;
$$;

-- assinaturas anteriores deste rascunho não podem coexistir
drop function if exists public.compensacao_registrar_disputa(uuid, uuid, bigint, text);
drop function if exists public.compensacao_criar_divida(text, uuid, uuid, uuid, bigint, bigint, text, uuid, uuid);

create table if not exists public.compensacoes_dividas (
  id                   uuid primary key default gen_random_uuid(),
  contrato_id          uuid not null references public.contratos (id) on delete restrict,
  pedido_id            uuid not null references public.pedidos (id) on delete restrict,
  profissional_id      uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  origem_tipo          text not null check (origem_tipo in ('disputa', 'disputa_contestacao', 'regresso')),
  origem_id            uuid not null,
  disputa_id           uuid references public.disputas (id) on delete restrict,
  valor_centavos       bigint not null check (valor_centavos > 0),
  motivo               text not null check (btrim(motivo) <> ''),
  analista_id          uuid not null references public.equipe (usuario_id) on delete restrict,
  aprovada_por         uuid references public.equipe (usuario_id) on delete restrict,
  registrada_por       uuid not null references public.equipe (usuario_id) on delete restrict,
  lancamento_id        uuid not null unique references public.lancamentos (id) on delete restrict,
  status               text not null default 'aberta' check (status in ('aberta', 'quitada', 'cancelada')),
  avisado_em           timestamptz,
  cancelada_em         timestamptz,
  cancelada_por        uuid references public.equipe (usuario_id) on delete restrict,
  motivo_cancelamento  text,
  criada_em            timestamptz not null default now(),
  constraint compensacoes_dividas_origem_unica unique (origem_tipo, origem_id),
  constraint compensacoes_dividas_regresso_check check (
    origem_tipo <> 'regresso' or (aprovada_por is not null and aprovada_por <> analista_id)),
  constraint compensacoes_dividas_cancelamento_check check (
    case when status = 'cancelada'
         then cancelada_em is not null and cancelada_por is not null
              and btrim(coalesce(motivo_cancelamento, '')) <> ''
         else cancelada_em is null and cancelada_por is null and motivo_cancelamento is null end)
);
create index if not exists ix_compensacoes_dividas_abertas
  on public.compensacoes_dividas (profissional_id, criada_em) where status = 'aberta';
create index if not exists ix_compensacoes_dividas_contrato on public.compensacoes_dividas (contrato_id);

create table if not exists public.compensacoes_aplicadas (
  id                  uuid primary key default gen_random_uuid(),
  divida_id           uuid not null references public.compensacoes_dividas (id) on delete restrict,
  contrato_id         uuid not null references public.contratos (id) on delete restrict,
  lancamento_id       uuid not null unique references public.lancamentos (id) on delete restrict,
  valor_centavos      bigint not null check (valor_centavos > 0),
  chave_idempotencia  text not null check (btrim(chave_idempotencia) <> ''),
  criada_em           timestamptz not null default now(),
  constraint compensacoes_aplicadas_chave_unica unique (chave_idempotencia, divida_id)
);
create index if not exists ix_compensacoes_aplicadas_divida on public.compensacoes_aplicadas (divida_id);
create index if not exists ix_compensacoes_aplicadas_contrato on public.compensacoes_aplicadas (contrato_id);

-- ---------------------------------------------------------------------------
-- Internas (ninguém executa direto)
-- ---------------------------------------------------------------------------
create or replace function public.compensacao_saldo(p_contrato uuid, p_codigo text, p_usuario uuid)
returns bigint
language sql volatile security definer set search_path = ''
as $$
  select coalesce(sum(case p.sentido when 'credito' then p.valor_centavos else -p.valor_centavos end), 0)::bigint
    from public.partidas p
    join public.lancamentos l on l.id = p.lancamento_id
    join public.contas_ledger c on c.id = p.conta_id
   where l.contrato_id = p_contrato and c.codigo = p_codigo and c.usuario_id is not distinct from p_usuario;
$$;

-- Repasses do contrato (a_liberar -> liberado), sem os estornados, desde um instante.
create or replace function public.compensacao_liberado_desde(p_contrato uuid, p_profissional uuid, p_desde timestamptz)
returns bigint
language sql volatile security definer set search_path = ''
as $$
  select coalesce(sum(pc.valor_centavos), 0)::bigint
    from public.lancamentos l
    join public.partidas pd on pd.lancamento_id = l.id and pd.sentido = 'debito'
    join public.contas_ledger cd on cd.id = pd.conta_id and cd.codigo = 'a_liberar' and cd.usuario_id = p_profissional
    join public.partidas pc on pc.lancamento_id = l.id and pc.sentido = 'credito'
    join public.contas_ledger cc on cc.id = pc.conta_id and cc.codigo = 'liberado' and cc.usuario_id = p_profissional
   where l.contrato_id = p_contrato and l.tipo = 'repasse' and l.criado_em >= p_desde
     and not exists (select 1 from public.lancamentos e where e.estorna_id = l.id);
$$;

-- Liberação vinda do payout.paid: o provedor JÁ pagou esse dinheiro ao profissional.
create or replace function public.compensacao_eh_payout(p_chave text, p_evento uuid)
returns boolean
language sql volatile security definer set search_path = ''
as $$
  select p_chave like 'liq/%'
      or exists (select 1 from public.eventos_webhook w where w.id = p_evento and w.tipo = 'payout.paid');
$$;

-- Quanto do contrato foi liberado por payout (sem os estornados).
create or replace function public.compensacao_pago_por_payout(p_contrato uuid, p_profissional uuid)
returns bigint
language sql volatile security definer set search_path = ''
as $$
  select coalesce(sum(pc.valor_centavos), 0)::bigint
    from public.lancamentos l
    join public.partidas pd on pd.lancamento_id = l.id and pd.sentido = 'debito'
    join public.contas_ledger cd on cd.id = pd.conta_id and cd.codigo = 'a_liberar' and cd.usuario_id = p_profissional
    join public.partidas pc on pc.lancamento_id = l.id and pc.sentido = 'credito'
    join public.contas_ledger cc on cc.id = pc.conta_id and cc.codigo = 'liberado' and cc.usuario_id = p_profissional
   where l.contrato_id = p_contrato and l.tipo = 'repasse'
     and public.compensacao_eh_payout(l.chave_idempotencia, l.evento_webhook_id)
     and not exists (select 1 from public.lancamentos e where e.estorna_id = l.id);
$$;

-- Liberações COMPENSÁVEIS desde um instante: as de compensacao_liberado_desde sem as de payout.
create or replace function public.compensacao_compensavel_desde(p_contrato uuid, p_profissional uuid, p_desde timestamptz)
returns bigint
language sql volatile security definer set search_path = ''
as $$
  select coalesce(sum(pc.valor_centavos), 0)::bigint
    from public.lancamentos l
    join public.partidas pd on pd.lancamento_id = l.id and pd.sentido = 'debito'
    join public.contas_ledger cd on cd.id = pd.conta_id and cd.codigo = 'a_liberar' and cd.usuario_id = p_profissional
    join public.partidas pc on pc.lancamento_id = l.id and pc.sentido = 'credito'
    join public.contas_ledger cc on cc.id = pc.conta_id and cc.codigo = 'liberado' and cc.usuario_id = p_profissional
   where l.contrato_id = p_contrato and l.tipo = 'repasse' and l.criado_em >= p_desde
     and not public.compensacao_eh_payout(l.chave_idempotencia, l.evento_webhook_id)
     and not exists (select 1 from public.lancamentos e where e.estorna_id = l.id);
$$;

-- Reembolso que uma decisão dá ao cliente.
create or replace function public.compensacao_reembolso(p_decisao text, p_parcial bigint, p_congelado bigint)
returns bigint
language sql immutable security definer set search_path = ''
as $$
  select coalesce(case p_decisao when 'reembolso_total' then p_congelado
                                 when 'reembolso_parcial' then p_parcial else 0 end, 0);
$$;

-- A decisão que gerou a dívida foi depois revertida ou reduzida por contestação (8.7)?
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

-- Quanto da dívida já foi compensado (compensação estornada não conta).
create or replace function public.compensacao_compensado(p_divida uuid)
returns bigint
language sql volatile security definer set search_path = ''
as $$
  select coalesce(sum(a.valor_centavos), 0)::bigint
    from public.compensacoes_aplicadas a
   where a.divida_id = p_divida
     and not exists (select 1 from public.lancamentos e where e.estorna_id = a.lancamento_id);
$$;

create or replace function public.compensacao_conta(p_codigo text, p_usuario uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.contas_ledger (codigo, natureza, usuario_id)
  values (p_codigo, case p_codigo when 'liberado' then 'passivo' when 'taxa_trato' then 'receita' else 'ativo' end,
          p_usuario)
  on conflict (codigo, (coalesce(usuario_id, '00000000-0000-0000-0000-000000000000'::uuid))) do nothing;
  select c.id into v_id from public.contas_ledger c
   where c.codigo = p_codigo and c.usuario_id is not distinct from p_usuario;
  return v_id;
end;
$$;

create or replace function public.compensacao_lancar(
  p_contrato uuid, p_tipo text, p_debito uuid, p_credito uuid, p_valor bigint, p_chave text,
  p_descricao text, p_disputa uuid, p_estorna uuid, p_ator uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.lancamentos (contrato_id, tipo, estorna_id, chave_idempotencia, descricao, disputa_id, criado_por)
  values (p_contrato, p_tipo, p_estorna, p_chave, p_descricao, p_disputa, p_ator)
  returning id into v_id;
  insert into public.partidas (lancamento_id, conta_id, sentido, valor_centavos)
  values (v_id, p_debito, 'debito', p_valor), (v_id, p_credito, 'credito', p_valor);
  return v_id;
end;
$$;

-- Núcleo do registro. Quem chama já validou a origem e a decisão.
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

-- ---------------------------------------------------------------------------
-- 1) Registrar a partir de uma disputa decidida ou da contestação que a mudou
-- ---------------------------------------------------------------------------
create or replace function public.compensacao_registrar_disputa(
  p_disputa uuid, p_contestacao uuid, p_valor_centavos bigint, p_motivo text, p_operador uuid)
returns table (resultado text, divida_id uuid, maximo_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_d     record;
  v_c     record;
  v_teto  bigint;
begin
  if p_disputa is null or p_valor_centavos is null or p_valor_centavos <= 0
     or p_motivo is null or btrim(p_motivo) = '' or p_operador is null then
    raise exception 'disputa, valor positivo, motivo e operador são obrigatórios';
  end if;
  -- quem registra: pessoa ativa da equipe com papel de análise
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = p_operador and q.ativo and q.revogado_em is null
                    and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')) then
    return query select 'analista_invalido'::text, null::uuid, 0::bigint;
    return;
  end if;
  -- trava a disputa: a decisão não muda no meio do registro
  select d.id, d.contrato_id, d.status, d.decisao, d.valor_congelado_centavos, d.valor_reembolso_centavos,
         d.decidida_por, d.aprovada_por
    into v_d from public.disputas d where d.id = p_disputa for share;
  if not found or v_d.status <> 'decidida' then
    return query select 'origem_nao_decidida'::text, null::uuid, 0::bigint;
    return;
  end if;

  if p_contestacao is null then
    if exists (select 1 from public.disputa_contestacoes x
                where x.disputa_id = p_disputa and x.status in ('alterada', 'revertida'))
       and not exists (select 1 from public.compensacoes_dividas dv
                        where dv.origem_tipo = 'disputa' and dv.origem_id = p_disputa) then
      return query select 'decisao_substituida'::text, null::uuid, 0::bigint;
      return;
    end if;
    v_teto := case v_d.decisao when 'reembolso_total' then v_d.valor_congelado_centavos
                               when 'reembolso_parcial' then v_d.valor_reembolso_centavos else 0 end;
    return query select * from public.compensacao_criar_divida(
      'disputa', p_disputa, v_d.contrato_id, p_disputa, p_valor_centavos, coalesce(v_teto, 0),
      p_motivo, v_d.decidida_por, v_d.aprovada_por, p_operador);
    return;
  end if;

  select x.status, x.nova_decisao, x.novo_valor_reembolso_centavos, x.analista_id, x.aprovada_por,
         x.efeito_financeiro, x.decidida_em
    into v_c from public.disputa_contestacoes x
   where x.id = p_contestacao and x.disputa_id = p_disputa for share;
  if not found or v_c.status not in ('alterada', 'revertida') or v_c.aprovada_por is null
     or v_c.efeito_financeiro = 'nenhum' then
    return query select 'origem_nao_decidida'::text, null::uuid, 0::bigint;
    return;
  end if;
  v_teto := public.compensacao_reembolso(
    v_c.nova_decisao, v_c.novo_valor_reembolso_centavos, v_d.valor_congelado_centavos);
  -- outra contestação, depois desta, já reverteu ou reduziu: esta decisão não vale mais
  if exists (select 1 from public.disputa_contestacoes y
              where y.disputa_id = p_disputa and y.id <> p_contestacao
                and y.status in ('alterada', 'revertida') and y.decidida_em >= v_c.decidida_em
                and public.compensacao_reembolso(
                      y.nova_decisao, y.novo_valor_reembolso_centavos, v_d.valor_congelado_centavos) < v_teto)
     and not exists (select 1 from public.compensacoes_dividas dv
                      where dv.origem_tipo = 'disputa_contestacao' and dv.origem_id = p_contestacao) then
    return query select 'decisao_substituida'::text, null::uuid, 0::bigint;
    return;
  end if;
  return query select * from public.compensacao_criar_divida(
    'disputa_contestacao', p_contestacao, v_d.contrato_id, p_disputa, p_valor_centavos, coalesce(v_teto, 0),
    p_motivo, v_c.analista_id, v_c.aprovada_por, p_operador);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Registrar regresso sem disputa (17.4; ex.: garantia depois do repasse): duas pessoas
-- ---------------------------------------------------------------------------
create or replace function public.compensacao_registrar_regresso(
  p_contrato uuid, p_referencia uuid, p_valor_centavos bigint, p_motivo text, p_analista uuid, p_aprovador uuid)
returns table (resultado text, divida_id uuid, maximo_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if p_contrato is null or p_referencia is null or p_valor_centavos is null or p_valor_centavos <= 0
     or p_motivo is null or btrim(p_motivo) = '' or p_analista is null or p_aprovador is null then
    raise exception 'contrato, referência, valor positivo, motivo, analista e aprovador são obrigatórios';
  end if;
  if p_analista = p_aprovador
     or not exists (select 1 from public.equipe q
                     where q.usuario_id = p_analista and q.ativo and q.revogado_em is null)
     or not exists (select 1 from public.equipe q
                     where q.usuario_id = p_aprovador and q.ativo and q.revogado_em is null
                       and q.papel in ('lider_suporte', 'administrador')) then
    return query select 'analista_invalido'::text, null::uuid, 0::bigint;
    return;
  end if;
  return query select * from public.compensacao_criar_divida(
    'regresso', p_referencia, p_contrato, null, p_valor_centavos, null, p_motivo, p_analista, p_aprovador,
    p_analista);
end;
$$;

-- 3) Aviso ao profissional (17.4): sem ele a dívida não é compensada. Data do banco.
create or replace function public.compensacao_avisar(p_divida uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_avisado timestamptz;
begin
  select d.avisado_em into v_avisado from public.compensacoes_dividas d where d.id = p_divida for update;
  if not found then
    return 'nao_encontrada';
  end if;
  if v_avisado is not null then
    return 'ja_avisada';
  end if;
  update public.compensacoes_dividas set avisado_em = now() where id = p_divida;
  return 'ok';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Compensar no repasse (chamar na transação da liberação, antes do saque)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 5) Contestação aceita (20.5): estorna as compensações e o Trato assume a dívida
-- ---------------------------------------------------------------------------
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
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = p_analista and q.ativo and q.revogado_em is null) then
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

-- Situação das dívidas só avança.
create or replace function public.compensacoes_dividas_validar()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if (old.status = 'cancelada' and new is distinct from old)
     or (old.status = 'quitada' and new.status = 'aberta')
     or (old.avisado_em is not null and new.avisado_em is distinct from old.avisado_em) then
    raise exception 'A dívida de compensação não volta atrás' using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists compensacoes_dividas_validar_trg on public.compensacoes_dividas;
create trigger compensacoes_dividas_validar_trg before update on public.compensacoes_dividas
  for each row execute function public.compensacoes_dividas_validar();
drop trigger if exists compensacoes_dividas_proteger on public.compensacoes_dividas;
create trigger compensacoes_dividas_proteger before update on public.compensacoes_dividas
  for each row execute function public.proteger_colunas(
    'id', 'contrato_id', 'pedido_id', 'profissional_id', 'origem_tipo', 'origem_id', 'disputa_id',
    'valor_centavos', 'motivo', 'analista_id', 'aprovada_por', 'registrada_por', 'lancamento_id', 'criada_em');
drop trigger if exists compensacoes_dividas_sem_delete on public.compensacoes_dividas;
create trigger compensacoes_dividas_sem_delete before delete on public.compensacoes_dividas
  for each row execute function public.bloquear_alteracao();
drop trigger if exists compensacoes_dividas_sem_truncate on public.compensacoes_dividas;
create trigger compensacoes_dividas_sem_truncate before truncate on public.compensacoes_dividas
  for each statement execute function public.bloquear_alteracao();
drop trigger if exists compensacoes_aplicadas_imutavel on public.compensacoes_aplicadas;
create trigger compensacoes_aplicadas_imutavel before update or delete on public.compensacoes_aplicadas
  for each row execute function public.bloquear_alteracao();
drop trigger if exists compensacoes_aplicadas_sem_truncate on public.compensacoes_aplicadas;
create trigger compensacoes_aplicadas_sem_truncate before truncate on public.compensacoes_aplicadas
  for each statement execute function public.bloquear_alteracao();

alter table public.compensacoes_dividas enable row level security;
alter table public.compensacoes_aplicadas enable row level security;
revoke all on table public.compensacoes_dividas, public.compensacoes_aplicadas
  from public, anon, authenticated, service_role;
grant select on table public.compensacoes_dividas, public.compensacoes_aplicadas to service_role;

revoke all on function public.compensacao_saldo(uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_liberado_desde(uuid, uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_compensado(uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_conta(text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_lancar(uuid, text, uuid, uuid, bigint, text, text, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_criar_divida(text, uuid, uuid, uuid, bigint, bigint, text, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_eh_payout(text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_pago_por_payout(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_compensavel_desde(uuid, uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_reembolso(text, bigint, bigint) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_origem_revista(uuid) from public, anon, authenticated, service_role;
revoke all on function public.compensacoes_dividas_validar() from public, anon, authenticated, service_role;
revoke all on function public.compensacao_registrar_disputa(uuid, uuid, bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.compensacao_registrar_regresso(uuid, uuid, bigint, text, uuid, uuid) from public, anon, authenticated;
revoke all on function public.compensacao_avisar(uuid) from public, anon, authenticated;
revoke all on function public.compensacao_aplicar(uuid, text) from public, anon, authenticated;
revoke all on function public.compensacao_cancelar(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.compensacao_registrar_disputa(uuid, uuid, bigint, text, uuid) to service_role;
grant execute on function public.compensacao_registrar_regresso(uuid, uuid, bigint, text, uuid, uuid) to service_role;
grant execute on function public.compensacao_avisar(uuid) to service_role;
grant execute on function public.compensacao_aplicar(uuid, text) to service_role;
grant execute on function public.compensacao_cancelar(uuid, uuid, text) to service_role;

commit;
