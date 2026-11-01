-- =============================================================================
-- Trato — PARÂMETROS DOS SEEDS (único arquivo que o João preenche)
-- =============================================================================
-- Nenhuma taxa, prazo, limite, cidade ou categoria fica escondido dentro dos seeds:
-- tudo está aqui. O que é NULL e está marcado "A DEFINIR PELO JOÃO" faz o seed ABORTAR
-- com uma mensagem clara (nada é gravado). Isso é de propósito.
--
-- Como usar (tudo na MESMA sessão, porque as tabelas abaixo são temporárias):
--   cat supabase/seeds/parametros.sql supabase/seeds/seed_cidades_categorias.sql \
--       supabase/seeds/seed_config_taxa.sql supabase/seeds/seed_contas_ledger.sql | psql "$URL_DO_BANCO"
-- Ou cole o conteúdo, na ordem, numa única execução do editor SQL. Só com o OK do João.
-- Esta sessão de trabalho NUNCA aplicou nada em banco real.
--
-- Legenda:
--   A DEFINIR PELO JOÃO     = sem valor; o seed não roda enquanto estiver NULL.
--   SUGESTÃO DO ESCOPO      = valor que vem do escopo/decisões (D3, 3.5, 3.6…); o João confirma ou troca.
--   SUGESTÃO DO AGENTE      = limite de segurança inventado para o rascunho; o João confirma ou troca.
-- =============================================================================

drop table if exists pg_temp.seed_param;
drop table if exists pg_temp.seed_config;
drop table if exists pg_temp.seed_faixa;

create temp table seed_param (chave text primary key, valor text);
-- valor/minimo/maximo na unidade da definição (centavos, bps, horas, dias…).
create temp table seed_config (
  chave       text primary key,
  valor       bigint,
  minimo      bigint,
  maximo      bigint,
  obrigatorio boolean not null
);
create temp table seed_faixa (
  ordem        integer primary key,
  de_centavos  bigint,
  ate_centavos bigint,  -- exclusivo; NULL = sem teto
  taxa_bps     integer
);

-- ---------------------------------------------------------------------------
-- 1) seed_cidades_categorias
-- ---------------------------------------------------------------------------
insert into seed_param (chave, valor) values
  -- Cidade do piloto (P6/P15: Belo Horizonte - MG, inativa até abertura do piloto).
  ('cidade_nome',   'Belo Horizonte'),
  ('cidade_uf',     'MG'),
  ('cidade_ativa',  'false'),-- 'true' abre a cidade para pedidos. Fica 'false' até o João decidir abrir o piloto
  ('cidade_lat',    '-19.9167'),   -- centro de BH
  ('cidade_lng',    '-43.9345'),

  -- Categorias de baixo risco (P15: 2 ou 3).
  -- NUNCA: obra estrutural, gás, elétrica de quadro, atividade regulada. O seed recusa esses nomes.
  ('cat1_incluir',  'true'),
  ('cat1_nome',     'Limpeza residencial'),
  ('cat1_slug',     'limpeza-residencial'),
  ('cat1_garantia_dias', '30'),   -- prazo de garantia/retrabalho da categoria (dias)
  ('cat2_incluir',  'true'),
  ('cat2_nome',     'Montagem de móveis'),
  ('cat2_slug',     'montagem-de-moveis'),
  ('cat2_garantia_dias', '30'),
  ('cat3_incluir',  'false'),     -- terceira categoria desativada no piloto inicial
  ('cat3_nome',     'Pintura de interiores'),
  ('cat3_slug',     'pintura-interna'),
  ('cat3_garantia_dias', null);

-- ---------------------------------------------------------------------------
-- 2) seed_config_taxa
-- ---------------------------------------------------------------------------
insert into seed_param (chave, valor) values
  -- Criador do rascunho em public.equipe (administrador)
  ('config_criada_por', '65be99cc-6ac3-4a75-842f-4af14a14680f');

-- ---------------------------------------------------------------------------
-- 3) seed_contas_ledger
-- ---------------------------------------------------------------------------
insert into seed_param (chave, valor) values
  -- Caminho A (D15): confirmado pelo João.
  ('ledger_p7_confirmado', 'true');

-- chave, valor, minimo, maximo, obrigatorio
insert into seed_config (chave, valor, minimo, maximo, obrigatorio) values
  -- Regra ÚNICA de taxa (V2/D13; P2: 7,5% = 750 bps; mínimo R$ 3,00 = 300 centavos)
  ('taxa_bps',                          750,  0,    2000, true),
  ('taxa_minima_centavos',              300,  0,    5000, true),
  -- Tabela progressiva (D2): em ESPERA. O seed só aceita 0 (desligada).
  ('taxa_progressiva_ativa',            0,    0,    1,    true),
  -- Prazo de liberação: liberar assim que o cliente confirma = 0 dias
  ('prazo_liberacao_dias',              0,    0,    30,   true),
  ('prazo_confirmacao_cliente_horas',   48,   12,   168,  false),
  -- Disputa e retrabalho
  ('janela_chargeback_dias',            7,    1,    30,   true),
  ('prazo_congelar_disputa_horas',      null, 24,   168,  false),
  ('prazo_resposta_disputa_horas',      48,   12,   168,  true),
  ('prazo_decisao_disputa_dias_uteis',  5,    1,    15,   true),
  ('prazo_retrabalho_atendimento_dias', 7,    1,    30,   true),
  ('garantia_retrabalho_dias_padrao',   30,   7,    365,  true),
  -- Limites de operação
  ('valor_minimo_servico_centavos',     3000, 1000, 100000, true),
  ('limite_orcamentos_por_pedido',      5,    1,    20,   true);

-- Faixas da tabela progressiva (D2). Ficam vazias: só entram se o João preencher as três colunas
-- de uma linha. Mesmo preenchidas, a tabela continua DESLIGADA (taxa_progressiva_ativa = 0).
insert into seed_faixa (ordem, de_centavos, ate_centavos, taxa_bps) values
  (1, null, null, null),  -- A DEFINIR PELO JOÃO (D2 em espera)
  (2, null, null, null),
  (3, null, null, null);
