-- Painel admin: design system e requisitos v2 (02/11/2026).
-- Autorizado pelo João (03/11/2026). Idempotente: pode rodar de novo sem duplicar nada.
--
--   1. Nomes legíveis e faixas permitidas dos parâmetros (RF-CFG-01); some o prefixo "teste_".
--   2. Duas definições novas: teto de valor do pedido (RN-07) e limite de valor atípico (RF-RIS-04).
--   3. Cupom: campanha, limite por usuário e início de validade (RF-CUP-01).
--   4. Pedido: número curto legível (PED-10482) em vez de só o UUID (RF-BUS-04).
--   5. Teto de alçada por papel (RP-02). Valores PROVISÓRIOS: a decisão 3 do documento está em aberto.
--
-- Não apaga nada e não muda a alçada de ninguém que já exista.

begin;

-- 1. Nomes legíveis e faixas ---------------------------------------------------------------------
update public.config_definicoes as d
set descricao = v.descricao, minimo = v.minimo, maximo = v.maximo
from (values
  ('adiantamento_bps',                  'Adiantamento ao iniciar o serviço',            0,    10000),
  ('garantia_retrabalho_dias_padrao',   'Garantia de retrabalho (padrão)',              0,    365),
  ('janela_chargeback_dias',            'Janela de reclamação do cliente',              1,    30),
  ('limite_orcamentos_por_pedido',      'Máximo de orçamentos por pedido',              1,    20),
  ('prazo_confirmacao_cliente_horas',   'Prazo para o cliente confirmar o serviço',     1,    720),
  ('prazo_congelar_disputa_horas',      'Prazo para congelar o repasse na disputa',     1,    720),
  ('prazo_decisao_disputa_dias_uteis',  'Prazo de decisão da disputa',                  1,    30),
  ('prazo_liberacao_dias',              'Prazo para liberar o repasse ao profissional', 0,    30),
  ('prazo_pagamento_pendente_horas',    'Prazo do pagamento pendente',                  1,    72),
  ('prazo_resposta_disputa_horas',      'Prazo de resposta da disputa',                 1,    720),
  ('prazo_retrabalho_atendimento_dias', 'Prazo para atender o retrabalho',              1,    60),
  ('taxa_bps',                          'Taxa do Trato por serviço',                    0,    2000),
  ('taxa_minima_centavos',              'Taxa mínima por pedido',                       0,    5000),
  ('taxa_progressiva_ativa',            'Tabela progressiva de taxa',                   0,    1),
  ('tolerancia_comparecimento_horas',   'Tolerância de comparecimento',                 0,    24),
  ('validade_pedido_horas',             'Validade do pedido aberto',                    1,    720),
  ('valor_minimo_servico_centavos',     'Valor mínimo do pedido',                       1000, 100000)
) as v(chave, descricao, minimo, maximo)
where d.chave = v.chave;

-- 2. Definições novas ----------------------------------------------------------------------------
insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values
  ('valor_maximo_servico_centavos', 'Teto de valor do pedido', 'centavos', 10000, 1000000, array['global'], true),
  ('limite_valor_atipico_centavos', 'Limite de valor atípico', 'centavos', 10000, 1000000, array['global'], true)
on conflict (chave) do nothing;

-- 3. Cupons -------------------------------------------------------------------------------------
alter table public.cupons add column if not exists campanha text;
alter table public.cupons add column if not exists limite_por_usuario integer check (limite_por_usuario is null or limite_por_usuario >= 1);
alter table public.cupons add column if not exists valido_desde timestamptz;

-- 4. Número curto do pedido ---------------------------------------------------------------------
alter table public.pedidos add column if not exists numero bigint generated always as identity (start with 10001);
create unique index if not exists pedidos_numero_uq on public.pedidos (numero);

-- 5. Teto de alçada por papel -------------------------------------------------------------------
create table if not exists public.papeis_alcada (
  papel         text primary key,
  teto_centavos bigint not null check (teto_centavos >= 0)
);
alter table public.papeis_alcada enable row level security;
comment on table public.papeis_alcada is
  'Teto de alçada financeira por papel da equipe (RP-02). Valores iniciais provisórios.';
insert into public.papeis_alcada (papel, teto_centavos) values
  ('administrador', 500000),
  ('financeiro',    200000),
  ('lider_suporte', 200000),
  ('mediador',       50000),
  ('atendente_n2',   50000),
  ('atendente_n1',   30000),
  ('cadastro',           0),
  ('moderador',          0),
  ('seguranca',          0),
  ('juridico',           0),
  ('dpo',                0)
on conflict (papel) do nothing;

-- Os dois limites novos (teto de valor do pedido e limite de valor atípico) entram em vigor pelo
-- fluxo normal do painel: Configurações > propor > outra pessoa aprova (dupla aprovação, RN-08).
-- Valores sugeridos pelo documento: teto R$ 1.000,00 e limite atípico R$ 800,00.
-- Enquanto não forem aprovados, o backend não aplica o teto.

commit;
