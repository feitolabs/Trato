-- PRÉ-CHECAGEM de supabase/seeds/seed_config_definicoes_termos.sql. SOMENTE LEITURA.
-- Rodar depois das migrations dos Termos v1.2 e antes do seed.
-- Esperado ANTES: todas as linhas com ok = true (as falsas aparecem primeiro).
-- esperado_depois = valor de ok depois do seed (false = a definição passou a existir).
-- Chave "ausente" falsa antes do seed: já existe; o seed não a altera e o rollback do seed não
-- deve ser usado sem conferir essa linha.
--
-- Informativo (rodar à parte): valores da versão vigente, base da nova versão no painel.
--   select p.chave, p.valor, p.escopo_tipo from public.config_parametros p
--     join public.config_versoes v on v.id = p.versao_id where v.status = 'vigente' order by 1, 3;
with chaves (chave) as (values
  ('arrependimento_dias'), ('ausencia_espera_minutos'), ('ausencia_justificativa_horas'),
  ('ausencia_retencao_max_bps'), ('sac_resposta_dias_uteis'), ('sac_dados_pessoais_dias'),
  ('incidente_seguranca_cautela_horas'), ('disputa_contestacao_prazo_dias_uteis'),
  ('disputa_contestacao_resposta_dias_uteis'), ('avaliacao_revisao_resposta_dias_uteis'),
  ('lgpd_pedido_resposta_dias')
),
itens (item, ok, esperado_depois) as (
  select 'config_definicoes aceita as unidades minutos e dias_uteis (20261125141500)',
         exists (select 1 from pg_constraint
                  where conrelid = to_regclass('public.config_definicoes')
                    and conname = 'config_definicoes_unidade_check'
                    and pg_get_constraintdef(oid) like '%''minutos''%'
                    and pg_get_constraintdef(oid) like '%''dias_uteis''%'), true
  union all select 'existe uma versão vigente (base para o painel)',
         exists (select 1 from public.config_versoes where status = 'vigente'), true
  union all select 'há ao menos 2 pessoas ativas na equipe (propor e aprovar)',
         (select count(*) >= 2 from public.equipe where ativo and revogado_em is null), true
  union all select 'nenhuma das 3 chaves sem leitor foi criada',
         not exists (select 1 from public.config_definicoes
                      where chave in ('cancelamento_sem_retencao_horas', 'medida_contestacao_prazo_dias',
                                      'medida_contestacao_resposta_dias_uteis')), true
  union all select 'nenhum nome antigo (dos comentários) foi criado',
         not exists (select 1 from public.config_definicoes
                      where chave in ('espera_cliente_ausente_minutos', 'justificativa_cliente_ausente_horas',
                                      'retencao_cancelamento_max_bps', 'chamado_resposta_dias_uteis',
                                      'chamado_dados_pessoais_resposta_dias')), true
  union all select 'ausente: ' || c.chave,
         not exists (select 1 from public.config_definicoes d where d.chave = c.chave), false
    from chaves c
)
select item, ok, esperado_depois from itens order by ok, item;
