-- Etapa B, rodada 1: ESQUEMA da exclusividade de 48h (só tabelas, colunas, índices e a correção do saldo).
-- Plano: docs/etapa-b-plano.md, seção 2. As funções de solicitar/responder/expirar exclusividade ficam para a rodada 2.
-- 1) Carteira separada em moedas_lancamentos: 'cliente' (desconto pago pela empresa) e 'profissional' (nunca vira desconto).
-- 2) Tipos novos de lançamento: bonus_avaliacao_profissional, exclusividade_uso, exclusividade_estorno.
-- 3) moedas_pendentes ganha tipo_lancamento (bônus do cliente x bônus do profissional).
-- 4) moedas_config: 6 colunas novas. categorias.permite_exclusividade. pedidos.status aceita 'reservado'.
-- 5) Tabela exclusividades (RLS ligada, sem policy, grants só service_role).
-- 6) CORREÇÃO: moedas_reservar_desconto passa a contar no saldo só a carteira 'cliente' (mesma assinatura da 20261120200000).
-- Constraints trocadas (nomes reais conferidos no banco): moedas_lancamentos_tipo_check, pedidos_status_check.
-- APLICADA no Supabase Trato em 2026-11-20 com o OK do João. Rollback em supabase/rollback/.
--
-- CONFIGURAÇÃO DE DADOS (não está nesta migration; rodar só com OK do João).
-- Categorias urgentes ficam sem exclusividade. O catálogo seed (seeds/seed_categorias_completas.sql) NÃO tem categorias
-- separadas de emergência ("vazamento", "falta de luz"); só estas, mais próximas:
--   chaveiro  (urgência típica)                 -> recomendado
--   encanador (inclui vazamentos)               -> decisão do João (categoria também atende serviço não urgente)
--   eletricista (inclui falta de luz/tomadas)   -> decisão do João (idem)
--   update public.categorias set permite_exclusividade = false where slug in ('chaveiro');
--   -- se o João quiser as três: where slug in ('chaveiro', 'encanador', 'eletricista');
-- (pedidos.urgente = true já bloqueia a exclusividade em qualquer categoria, regra do backend.)

begin;

-- 1) Carteira e tipos novos no livro de moedas (só acrescenta; o livro continua imutável).
alter table public.moedas_lancamentos
  add column if not exists carteira text not null default 'cliente'
    check (carteira in ('cliente', 'profissional'));

alter table public.moedas_lancamentos drop constraint if exists moedas_lancamentos_tipo_check;
alter table public.moedas_lancamentos
  add constraint moedas_lancamentos_tipo_check
  check (tipo in ('bonus_avaliacao', 'estorno', 'uso', 'ajuste',
                  'bonus_avaliacao_profissional', 'exclusividade_uso', 'exclusividade_estorno'));

-- 1 bônus de profissional por cliente, vitalício.
create unique index if not exists moedas_lancamentos_prof_cliente_unico
  on public.moedas_lancamentos (usuario_id, parceiro_id)
  where tipo = 'bonus_avaliacao_profissional';
create index if not exists moedas_lancamentos_usuario_carteira_idx
  on public.moedas_lancamentos (usuario_id, carteira, criada_em desc);

-- 2) Pendentes: de qual tipo é o bônus que será liberado.
alter table public.moedas_pendentes
  add column if not exists tipo_lancamento text not null default 'bonus_avaliacao'
    check (tipo_lancamento in ('bonus_avaliacao', 'bonus_avaliacao_profissional'));
create unique index if not exists moedas_pendentes_prof_cliente_unico
  on public.moedas_pendentes (usuario_id, parceiro_id)
  where tipo_lancamento = 'bonus_avaliacao_profissional' and status in ('pendente', 'liberado');

-- 3) Configuração.
alter table public.moedas_config
  add column if not exists bonus_avaliacao_profissional_moedas integer not null default 50
    check (bonus_avaliacao_profissional_moedas >= 0),
  add column if not exists exclusividade_custo_moedas integer not null default 100
    check (exclusividade_custo_moedas > 0),
  add column if not exists exclusividade_duracao_horas integer not null default 48
    check (exclusividade_duracao_horas > 0),
  add column if not exists exclusividade_max_simultaneas integer not null default 3
    check (exclusividade_max_simultaneas > 0),
  add column if not exists exclusividade_prazo_resposta_horas integer not null default 6
    check (exclusividade_prazo_resposta_horas > 0),
  add column if not exists exclusividade_bloqueio_recusa_dias integer not null default 30
    check (exclusividade_bloqueio_recusa_dias >= 0);

-- 4) Categorias e pedidos.
alter table public.categorias
  add column if not exists permite_exclusividade boolean not null default true;

alter table public.pedidos drop constraint if exists pedidos_status_check;
alter table public.pedidos
  add constraint pedidos_status_check
  check (status in ('aberto', 'orcamento_aceito', 'pago_retido', 'agendado', 'em_andamento',
                    'em_confirmacao', 'concluido', 'cancelado', 'em_disputa', 'retrabalho', 'reservado'));

-- 5) Exclusividades.
create table public.exclusividades (
  id                 uuid primary key default gen_random_uuid(),
  profissional_id    uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  cliente_id         uuid not null references public.usuarios (id) on delete restrict,
  pedido_id          uuid not null references public.pedidos (id) on delete restrict,
  status             text not null check (status in ('aguardando_cliente', 'ativa', 'recusada',
                       'expirada_sem_resposta', 'concluida', 'expirada_sem_atendimento', 'cancelada')),
  moedas_cobradas    integer not null check (moedas_cobradas > 0),  -- congelado da config no momento do pedido
  chave_idempotencia text not null unique,
  criada_em          timestamptz not null default now(),
  responder_ate      timestamptz not null,
  respondida_em      timestamptz,
  expira_em          timestamptz,  -- preenchido no aceite: respondida_em + duração
  encerrada_em       timestamptz,
  atualizado_em      timestamptz not null default now(),
  check (profissional_id <> cliente_id)
);
-- um pedido só tem uma exclusividade em andamento por vez
create unique index exclusividades_pedido_em_andamento_idx on public.exclusividades (pedido_id)
  where status in ('aguardando_cliente', 'ativa');
create index exclusividades_profissional_status_idx on public.exclusividades (profissional_id, status);
create index exclusividades_status_responder_idx on public.exclusividades (status, responder_ate);
create index exclusividades_status_expira_idx on public.exclusividades (status, expira_em);

alter table public.exclusividades enable row level security;
revoke all on table public.exclusividades from public, anon, authenticated, service_role;
grant select, insert, update on table public.exclusividades to service_role;

-- 6) CORREÇÃO: o saldo de desconto conta só a carteira 'cliente'. Mesma assinatura e mesmos grants da 20261120200000.
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

  -- só a carteira do CLIENTE paga desconto (moeda de profissional nunca vira desconto)
  select coalesce(sum(quantidade), 0) into v_saldo
    from public.moedas_lancamentos
   where usuario_id = p_usuario and carteira = 'cliente' and (expira_em is null or expira_em > now());
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

commit;
