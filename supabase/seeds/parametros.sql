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
  -- Cidade do piloto (P6/P15). O harness sugere Belo Horizonte, mas NÃO está confirmada.
  ('cidade_nome',   null),   -- A DEFINIR PELO JOÃO (sugestão não confirmada: Belo Horizonte)
  ('cidade_uf',     null),   -- A DEFINIR PELO JOÃO (sugestão não confirmada: MG)
  ('cidade_ativa',  'false'),-- 'true' abre a cidade para pedidos. Fica 'false' até o João decidir abrir o piloto
  ('cidade_lat',    null),   -- opcional (centro do mapa)
  ('cidade_lng',    null),   -- opcional

  -- Categorias de baixo risco (P15: 2 ou 3). Nomes são SUGESTÃO DO AGENTE; o João troca à vontade.
  -- NUNCA: obra estrutural, gás, elétrica de quadro, atividade regulada. O seed recusa esses nomes.
  -- As perguntas guiadas de cada vaga estão em seed_cidades_categorias.sql (vaga 1 = limpeza,
  -- vaga 2 = montagem de móveis, vaga 3 = pintura interna). Se trocar a categoria, troque as perguntas.
  ('cat1_incluir',  'true'),
  ('cat1_nome',     'Limpeza residencial'),
  ('cat1_slug',     'limpeza-residencial'),
  ('cat1_garantia_dias', null),   -- A DEFINIR PELO JOÃO: prazo de garantia/retrabalho da categoria (dias)
  ('cat2_incluir',  'true'),
  ('cat2_nome',     'Montagem de móveis'),
  ('cat2_slug',     'montagem-de-moveis'),
  ('cat2_garantia_dias', null),   -- A DEFINIR PELO JOÃO
  ('cat3_incluir',  'false'),     -- terceira categoria é opcional; 'true' para incluir
  ('cat3_nome',     'Pintura de interiores'),
  ('cat3_slug',     'pintura-interna'),
  ('cat3_garantia_dias', null);   -- A DEFINIR PELO JOÃO (só se cat3_incluir = 'true')

-- ---------------------------------------------------------------------------
-- 2) seed_config_taxa
-- ---------------------------------------------------------------------------
insert into seed_param (chave, valor) values
  -- Quem cria o rascunho: id (uuid) de uma pessoa JÁ cadastrada em public.equipe (o primeiro
  -- administrador, criado pelo João; ver seed_equipe_admin.sql). Quem APROVA tem de ser OUTRA pessoa.
  ('config_criada_por', null);    -- A DEFINIR PELO JOÃO (uuid em equipe)

-- ---------------------------------------------------------------------------
-- 3) seed_contas_ledger
-- ---------------------------------------------------------------------------
insert into seed_param (chave, valor) values
  -- Só vira 'true' depois que o João responder o P7 (parceiro de pagamento e custódia, caminho A).
  ('ledger_p7_confirmado', 'false');   -- A DEFINIR PELO JOÃO

-- chave, valor, minimo, maximo, obrigatorio
insert into seed_config (chave, valor, minimo, maximo, obrigatorio) values
  -- Regra ÚNICA de taxa (V2/D13; P2). Limites minimo/maximo = trava de segurança que o João escolhe.
  ('taxa_bps',                          null, null, null, true),   -- A DEFINIR PELO JOÃO (P2). Ex.: 750 = 7,5%. Limites também A DEFINIR
  ('taxa_minima_centavos',              null, null, null, true),   -- A DEFINIR PELO JOÃO (P2). 0 = sem mínimo. Limites também A DEFINIR
  -- Tabela progressiva (D2): em ESPERA. O seed só aceita 0 (desligada).
  ('taxa_progressiva_ativa',            0,    0,    1,    true),   -- 0 = desligada. Não mude sem aprovar P2/D2
  -- Prazo de liberação (P1: 48 h ou 7 dias?). Preencha SÓ o que o João escolher; o outro fica NULL.
  ('prazo_liberacao_dias',              null, 1,    30,   true),   -- A DEFINIR PELO JOÃO (P1). Limites: SUGESTÃO DO AGENTE
  ('prazo_confirmacao_cliente_horas',   null, 12,   168,  false),  -- A DEFINIR PELO JOÃO (P1), opcional. Limites: SUGESTÃO DO AGENTE
  -- Disputa e retrabalho
  ('janela_chargeback_dias',            7,    1,    30,   true),   -- SUGESTÃO DO ESCOPO (D3: 7 dias). Limites: SUGESTÃO DO AGENTE
  ('prazo_congelar_disputa_horas',      null, 24,   168,  false),  -- A DEFINIR PELO JOÃO (escopo 3.5 diz 72; conflito N17/P17), opcional
  ('prazo_resposta_disputa_horas',      48,   12,   168,  true),   -- SUGESTÃO DO ESCOPO (resposta em 48 h)
  ('prazo_decisao_disputa_dias_uteis',  5,    1,    15,   true),   -- SUGESTÃO DO ESCOPO (decisão em 5 dias úteis)
  ('prazo_retrabalho_atendimento_dias', 7,    1,    30,   true),   -- SUGESTÃO DO ESCOPO (retrabalho em 7 dias)
  ('garantia_retrabalho_dias_padrao',   30,   7,    365,  true),   -- SUGESTÃO DO ESCOPO (30 dias); cada categoria pode ter o seu
  -- Limites de operação
  ('valor_minimo_servico_centavos',     3000, 1000, 100000, true), -- SUGESTÃO DO ESCOPO (R$ 30,00). Limites: SUGESTÃO DO AGENTE
  ('limite_orcamentos_por_pedido',      5,    1,    20,   true);   -- SUGESTÃO DO ESCOPO (5 orçamentos). Limites: SUGESTÃO DO AGENTE

-- Faixas da tabela progressiva (D2). Ficam vazias: só entram se o João preencher as três colunas
-- de uma linha. Mesmo preenchidas, a tabela continua DESLIGADA (taxa_progressiva_ativa = 0).
insert into seed_faixa (ordem, de_centavos, ate_centavos, taxa_bps) values
  (1, null, null, null),  -- A DEFINIR PELO JOÃO (D2 em espera)
  (2, null, null, null),
  (3, null, null, null);
