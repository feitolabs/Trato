-- Moedas, fase 3: orçamento de desconto (mensal + teto diário) e liberação do bônus após N dias sem disputa.
-- A empresa paga o desconto; só o CLIENTE usa moeda como desconto. Valores em centavos inteiros.
-- 1) moedas_config: orçamento do mês, aviso, teto por cliente/mês, teto diário, dias de liberação do bônus.
-- 2) moedas_orcamento_mensal e moedas_orcamento_diario: quanto já foi usado no mês e no dia.
-- 3) Funções de reserva atômica (mês + dia) e de devolução (estorno). Só service_role executa.
-- 4) moedas_pendentes: bônus aguardando liberação (o backend processa por rotina).
-- 5) Índices: uso por cliente/mês e fila de pendentes.
-- Só o backend (service_role) lê e escreve; RLS ligada e sem policy para o app.
-- APLICADA no Supabase Trato em 2026-11-20 com o OK do João. Rollback em supabase/rollback/.
--
-- VALIDADE DE 90 DIAS (não está nesta migration; é só configuração, rodar com OK do João):
--   update public.moedas_config set validade_dias = 90, atualizado_em = now() where id;
--
-- CONTRATO DAS FUNÇÕES (p_mes e p_dia chegam prontos do backend; dia = data em America/Sao_Paulo;
-- p_mes é normalizado para o dia 1 do mês):
--   public.moedas_reservar_orcamento(p_mes date, p_dia date, p_valor_centavos integer,
--                                    p_orcamento_mes_centavos integer, p_teto_dia_centavos integer) returns text
--     Reserva MÊS e DIA na mesma transação. Retorna:
--       'ok'                 = reservou nos dois;
--       'limite_diario'      = estouraria o teto do dia (nada muda);
--       'orcamento_esgotado' = estouraria o orçamento do mês (nada muda).
--     p_valor <= 0 ou nulo gera erro.
--   public.moedas_devolver_orcamento(p_mes date, p_dia date, p_valor_centavos integer) returns integer
--     Estorno: subtrai do mês e do dia, nunca abaixo de 0. Devolve o usado do MÊS depois do estorno (0 se não existe).
--
-- LIBERAÇÃO DO BÔNUS: o backend cria a linha em moedas_pendentes (status 'pendente', liberar_em = agora + dias_liberacao_bonus).
-- Se não houver disputa no pedido até liberar_em, a rotina cria o lançamento 'bonus_avaliacao' em moedas_lancamentos
-- e marca a pendente como 'liberado'; com disputa, marca 'cancelado'.

begin;

alter table public.moedas_config
  add column if not exists orcamento_mensal_desconto_centavos integer not null default 30000
    check (orcamento_mensal_desconto_centavos >= 0),
  add column if not exists aviso_percentual integer not null default 80
    check (aviso_percentual between 0 and 100),
  add column if not exists teto_desconto_cliente_mes_centavos integer not null default 500
    check (teto_desconto_cliente_mes_centavos >= 0),
  add column if not exists teto_diario_desconto_centavos integer not null default 1000
    check (teto_diario_desconto_centavos >= 0),
  add column if not exists dias_liberacao_bonus integer not null default 7
    check (dias_liberacao_bonus >= 0);

create table public.moedas_orcamento_mensal (
  mes_ref        date primary key check (mes_ref = date_trunc('month', mes_ref)::date),  -- sempre o dia 1
  usado_centavos integer not null default 0 check (usado_centavos >= 0),
  atualizado_em  timestamptz not null default now()
);

create table public.moedas_orcamento_diario (
  dia_ref        date primary key,  -- data em America/Sao_Paulo, calculada pelo backend
  usado_centavos integer not null default 0 check (usado_centavos >= 0),
  atualizado_em  timestamptz not null default now()
);

create table public.moedas_pendentes (
  id                 uuid primary key default gen_random_uuid(),
  usuario_id         uuid not null references public.usuarios (id) on delete restrict,
  pedido_id          uuid,
  quantidade         integer not null check (quantidade > 0),
  liberar_em         timestamptz not null,
  status             text not null default 'pendente' check (status in ('pendente', 'liberado', 'cancelado')),
  chave_idempotencia text not null unique,
  parceiro_id        uuid references public.usuarios (id) on delete restrict,
  criada_em          timestamptz not null default now()
);
create index moedas_pendentes_status_liberar_idx on public.moedas_pendentes (status, liberar_em);

create or replace function public.moedas_reservar_orcamento(
  p_mes date, p_dia date, p_valor_centavos integer,
  p_orcamento_mes_centavos integer, p_teto_dia_centavos integer)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_mes  date := date_trunc('month', p_mes)::date;
  v_rows integer;
begin
  if p_mes is null or p_dia is null or p_valor_centavos is null or p_valor_centavos <= 0
     or p_orcamento_mes_centavos is null or p_teto_dia_centavos is null then
    raise exception 'parâmetros inválidos para reserva de orçamento';
  end if;

  -- garante as linhas (zeradas) e reserva primeiro o DIA, depois o MÊS; se o mês falhar, desfaz o dia.
  insert into public.moedas_orcamento_mensal (mes_ref) values (v_mes) on conflict (mes_ref) do nothing;
  insert into public.moedas_orcamento_diario (dia_ref) values (p_dia) on conflict (dia_ref) do nothing;

  update public.moedas_orcamento_diario
     set usado_centavos = usado_centavos + p_valor_centavos, atualizado_em = now()
   where dia_ref = p_dia and usado_centavos + p_valor_centavos <= p_teto_dia_centavos;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return 'limite_diario';
  end if;

  update public.moedas_orcamento_mensal
     set usado_centavos = usado_centavos + p_valor_centavos, atualizado_em = now()
   where mes_ref = v_mes and usado_centavos + p_valor_centavos <= p_orcamento_mes_centavos;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    update public.moedas_orcamento_diario
       set usado_centavos = usado_centavos - p_valor_centavos, atualizado_em = now()
     where dia_ref = p_dia;
    return 'orcamento_esgotado';
  end if;

  return 'ok';
end;
$$;

create or replace function public.moedas_devolver_orcamento(p_mes date, p_dia date, p_valor_centavos integer)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_usado integer;
begin
  if p_valor_centavos is null or p_valor_centavos < 0 then
    raise exception 'valor inválido para devolução';
  end if;
  update public.moedas_orcamento_diario
     set usado_centavos = greatest(usado_centavos - p_valor_centavos, 0), atualizado_em = now()
   where dia_ref = p_dia;
  update public.moedas_orcamento_mensal
     set usado_centavos = greatest(usado_centavos - p_valor_centavos, 0), atualizado_em = now()
   where mes_ref = date_trunc('month', p_mes)::date
  returning usado_centavos into v_usado;
  return coalesce(v_usado, 0);
end;
$$;

-- Soma de moedas 'uso' por cliente no mês (usuario_id, tipo, criada_em).
create index if not exists moedas_lancamentos_usuario_tipo_idx
  on public.moedas_lancamentos (usuario_id, tipo, criada_em desc);

alter table public.moedas_orcamento_mensal enable row level security;
alter table public.moedas_orcamento_diario enable row level security;
alter table public.moedas_pendentes enable row level security;

revoke all on table public.moedas_orcamento_mensal, public.moedas_orcamento_diario, public.moedas_pendentes
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.moedas_orcamento_mensal to service_role;
grant select, insert, update on table public.moedas_orcamento_diario to service_role;
grant select, insert, update on table public.moedas_pendentes to service_role;

revoke all on function public.moedas_reservar_orcamento(date, date, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.moedas_devolver_orcamento(date, date, integer) from public, anon, authenticated;
grant execute on function public.moedas_reservar_orcamento(date, date, integer, integer, integer) to service_role;
grant execute on function public.moedas_devolver_orcamento(date, date, integer) to service_role;

commit;
