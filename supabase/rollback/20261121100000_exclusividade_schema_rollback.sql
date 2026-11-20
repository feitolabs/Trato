-- Desfaz 20261121100000_exclusividade_schema.sql (ordem inversa).
-- ATENÇÃO: apaga a tabela exclusividades e as colunas novas. Só rode com o OK do João.
-- Vai FALHAR (e desfazer tudo, é uma transação) se existirem lançamentos com os tipos novos em moedas_lancamentos
-- ou pedidos com status 'reservado': trate esses registros antes (o livro é imutável; correção é estorno).

begin;

-- 6) restaura a função antiga (corpo da 20261120200000: saldo SEM filtro de carteira)
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

-- 5) exclusividades
drop table if exists public.exclusividades;

-- 4) pedidos e categorias
alter table public.pedidos drop constraint if exists pedidos_status_check;
alter table public.pedidos
  add constraint pedidos_status_check
  check (status in ('aberto', 'orcamento_aceito', 'pago_retido', 'agendado', 'em_andamento',
                    'em_confirmacao', 'concluido', 'cancelado', 'em_disputa', 'retrabalho'));
alter table public.categorias drop column if exists permite_exclusividade;

-- 3) config
alter table public.moedas_config
  drop column if exists exclusividade_bloqueio_recusa_dias,
  drop column if exists exclusividade_prazo_resposta_horas,
  drop column if exists exclusividade_max_simultaneas,
  drop column if exists exclusividade_duracao_horas,
  drop column if exists exclusividade_custo_moedas,
  drop column if exists bonus_avaliacao_profissional_moedas;

-- 2) pendentes
drop index if exists public.moedas_pendentes_prof_cliente_unico;
alter table public.moedas_pendentes drop column if exists tipo_lancamento;

-- 1) lançamentos
drop index if exists public.moedas_lancamentos_usuario_carteira_idx;
drop index if exists public.moedas_lancamentos_prof_cliente_unico;
alter table public.moedas_lancamentos drop constraint if exists moedas_lancamentos_tipo_check;
alter table public.moedas_lancamentos
  add constraint moedas_lancamentos_tipo_check
  check (tipo in ('bonus_avaliacao', 'estorno', 'uso', 'ajuste'));
alter table public.moedas_lancamentos drop column if exists carteira;

commit;
