-- Moedas, fase 3b: RESERVA de moedas por cobrança (corrige 4 falhas da revisão de segurança).
--   1) saldo gasto 2x            -> saldo disponível desconta as reservas abertas, com lock por usuário;
--   2) reserva presa (Pix não pago) -> reserva tem prazo (expira_em) e é expirada por rotina;
--   3) devolução em dobro (webhook repetido) -> devolução idempotente por status;
--   4) valor da devolução ao mudar o valor da moeda -> o desconto em centavos fica GRAVADO na reserva.
-- Depende de 20261120100000_moedas_orcamento.sql (tabelas moedas_orcamento_mensal e moedas_orcamento_diario).
-- Só o backend (service_role) lê e escreve; RLS ligada e sem policy para o app. Valores em centavos inteiros.
-- APLICADA no Supabase Trato em 2026-11-20 com o OK do João. Rollback em supabase/rollback/.
--
-- CONFIG (valores propostos): max_reservas_abertas = 2, reserva_minutos = 30 (ajustáveis por UPDATE de configuração, com OK).
--
-- CONTRATO (todas SECURITY DEFINER, search_path = '', execute só service_role):
--   public.moedas_reservar_desconto(p_cobranca uuid, p_usuario uuid, p_mes date, p_dia date, p_moedas integer,
--       p_desconto_centavos integer, p_orcamento_mes_centavos integer, p_teto_dia_centavos integer,
--       p_teto_cliente_mes_centavos integer, p_max_reservas_abertas integer, p_expira_em timestamptz) returns text
--     Atômica, com lock por usuário. Retorna, nesta ordem de checagem:
--       'ja_reservada'       = já existe reserva para a cobrança (nada muda);
--       'saldo_insuficiente' = moedas válidas (não vencidas) menos as reservadas < p_moedas;
--       'reservas_abertas'   = usuário já tem p_max_reservas_abertas reservas 'reservada';
--       'teto_cliente'       = descontos 'reservada'+'confirmada' do usuário no mês + novo > teto do cliente;
--       'limite_diario'      = estouraria o teto do dia;
--       'orcamento_esgotado' = estouraria o orçamento do mês (o dia é desfeito);
--       'ok'                 = reservou (cria a linha 'reservada' e soma no mês e no dia).
--     Nada muda se o retorno for diferente de 'ok'. Parâmetros nulos, moedas <= 0 ou desconto <= 0 geram erro.
--   public.moedas_confirmar_reserva(p_cobranca uuid) returns boolean
--     'reservada' -> 'confirmada'. false se não achar ou se já estiver 'devolvida' (ou já 'confirmada').
--   public.moedas_devolver_reserva(p_cobranca uuid) returns integer
--     Idempotente: só age se status in ('reservada','confirmada'); marca 'devolvida' e subtrai EXATAMENTE o
--     desconto_centavos gravado do mês e do dia (nunca abaixo de 0). Devolve esse valor; 0 se nada a devolver.
--   public.moedas_expirar_reservas(p_agora timestamptz) returns setof uuid
--     Devolve (como acima) as 'reservada' com expira_em < p_agora e retorna os cobranca_id, para o backend cancelar as cobranças.

begin;

alter table public.moedas_config
  add column if not exists max_reservas_abertas integer not null default 2
    check (max_reservas_abertas >= 0),
  add column if not exists reserva_minutos integer not null default 30
    check (reserva_minutos > 0);

create table public.moedas_reservas (
  id                uuid primary key default gen_random_uuid(),
  cobranca_id       uuid not null unique,
  usuario_id        uuid not null references public.usuarios (id) on delete restrict,
  mes_ref           date not null check (mes_ref = date_trunc('month', mes_ref)::date),  -- sempre o dia 1
  dia_ref           date not null,
  moedas            integer not null check (moedas > 0),
  desconto_centavos integer not null check (desconto_centavos > 0),  -- valor gravado na reserva: é o que devolve
  status            text not null default 'reservada' check (status in ('reservada', 'confirmada', 'devolvida')),
  expira_em         timestamptz not null,
  criada_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
create index moedas_reservas_usuario_mes_status_idx on public.moedas_reservas (usuario_id, mes_ref, status);
create index moedas_reservas_status_expira_idx on public.moedas_reservas (status, expira_em);

create or replace function public.moedas_reservar_desconto(
  p_cobranca uuid, p_usuario uuid, p_mes date, p_dia date, p_moedas integer,
  p_desconto_centavos integer, p_orcamento_mes_centavos integer, p_teto_dia_centavos integer,
  p_teto_cliente_mes_centavos integer, p_max_reservas_abertas integer, p_expira_em timestamptz)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_mes     date;
  v_rows    integer;
  v_saldo   bigint;
  v_abertas integer;
  v_no_mes  bigint;
begin
  if p_cobranca is null or p_usuario is null or p_mes is null or p_dia is null
     or p_moedas is null or p_moedas <= 0 or p_desconto_centavos is null or p_desconto_centavos <= 0
     or p_orcamento_mes_centavos is null or p_teto_dia_centavos is null
     or p_teto_cliente_mes_centavos is null or p_max_reservas_abertas is null or p_expira_em is null then
    raise exception 'parâmetros inválidos para reserva de desconto';
  end if;
  v_mes := date_trunc('month', p_mes)::date;

  -- serializa as reservas do mesmo usuário (evita gastar o mesmo saldo 2x)
  perform pg_advisory_xact_lock(hashtextextended(p_usuario::text, 0));

  if exists (select 1 from public.moedas_reservas where cobranca_id = p_cobranca) then
    return 'ja_reservada';
  end if;

  select coalesce(sum(quantidade), 0) into v_saldo
    from public.moedas_lancamentos
   where usuario_id = p_usuario and (expira_em is null or expira_em > now());
  v_saldo := v_saldo - coalesce((select sum(moedas) from public.moedas_reservas
                                  where usuario_id = p_usuario and status = 'reservada'), 0);
  if v_saldo < p_moedas then
    return 'saldo_insuficiente';
  end if;

  select count(*) into v_abertas from public.moedas_reservas
   where usuario_id = p_usuario and status = 'reservada';
  if v_abertas >= p_max_reservas_abertas then
    return 'reservas_abertas';
  end if;

  select coalesce(sum(desconto_centavos), 0) into v_no_mes from public.moedas_reservas
   where usuario_id = p_usuario and mes_ref = v_mes and status in ('reservada', 'confirmada');
  if v_no_mes + p_desconto_centavos > p_teto_cliente_mes_centavos then
    return 'teto_cliente';
  end if;

  -- orçamento: garante as linhas, reserva o DIA e depois o MÊS; se o mês falhar, desfaz o dia.
  insert into public.moedas_orcamento_mensal (mes_ref) values (v_mes) on conflict (mes_ref) do nothing;
  insert into public.moedas_orcamento_diario (dia_ref) values (p_dia) on conflict (dia_ref) do nothing;

  update public.moedas_orcamento_diario
     set usado_centavos = usado_centavos + p_desconto_centavos, atualizado_em = now()
   where dia_ref = p_dia and usado_centavos + p_desconto_centavos <= p_teto_dia_centavos;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return 'limite_diario';
  end if;

  update public.moedas_orcamento_mensal
     set usado_centavos = usado_centavos + p_desconto_centavos, atualizado_em = now()
   where mes_ref = v_mes and usado_centavos + p_desconto_centavos <= p_orcamento_mes_centavos;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    update public.moedas_orcamento_diario
       set usado_centavos = usado_centavos - p_desconto_centavos, atualizado_em = now()
     where dia_ref = p_dia;
    return 'orcamento_esgotado';
  end if;

  insert into public.moedas_reservas
    (cobranca_id, usuario_id, mes_ref, dia_ref, moedas, desconto_centavos, expira_em)
  values (p_cobranca, p_usuario, v_mes, p_dia, p_moedas, p_desconto_centavos, p_expira_em);
  return 'ok';
end;
$$;

create or replace function public.moedas_confirmar_reserva(p_cobranca uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_rows integer;
begin
  update public.moedas_reservas set status = 'confirmada', atualizado_em = now()
   where cobranca_id = p_cobranca and status = 'reservada';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

create or replace function public.moedas_devolver_reserva(p_cobranca uuid)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_desconto integer;
  v_dia      date;
  v_mes      date;
begin
  update public.moedas_reservas set status = 'devolvida', atualizado_em = now()
   where cobranca_id = p_cobranca and status in ('reservada', 'confirmada')
  returning desconto_centavos, dia_ref, mes_ref into v_desconto, v_dia, v_mes;
  if not found then
    return 0;
  end if;

  update public.moedas_orcamento_diario
     set usado_centavos = greatest(usado_centavos - v_desconto, 0), atualizado_em = now()
   where dia_ref = v_dia;
  update public.moedas_orcamento_mensal
     set usado_centavos = greatest(usado_centavos - v_desconto, 0), atualizado_em = now()
   where mes_ref = v_mes;
  return v_desconto;
end;
$$;

create or replace function public.moedas_expirar_reservas(p_agora timestamptz)
returns setof uuid
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
begin
  for r in select cobranca_id from public.moedas_reservas
            where status = 'reservada' and expira_em < p_agora
            order by expira_em
              for update skip locked
  loop
    if public.moedas_devolver_reserva(r.cobranca_id) > 0 then
      return next r.cobranca_id;
    end if;
  end loop;
  return;
end;
$$;

alter table public.moedas_reservas enable row level security;

revoke all on table public.moedas_reservas from public, anon, authenticated, service_role;
grant select, insert, update on table public.moedas_reservas to service_role;

revoke all on function public.moedas_reservar_desconto(uuid, uuid, date, date, integer, integer, integer, integer, integer, integer, timestamptz) from public, anon, authenticated;
revoke all on function public.moedas_confirmar_reserva(uuid) from public, anon, authenticated;
revoke all on function public.moedas_devolver_reserva(uuid) from public, anon, authenticated;
revoke all on function public.moedas_expirar_reservas(timestamptz) from public, anon, authenticated;
grant execute on function public.moedas_reservar_desconto(uuid, uuid, date, date, integer, integer, integer, integer, integer, integer, timestamptz) to service_role;
grant execute on function public.moedas_confirmar_reserva(uuid) to service_role;
grant execute on function public.moedas_devolver_reserva(uuid) to service_role;
grant execute on function public.moedas_expirar_reservas(timestamptz) to service_role;

commit;
