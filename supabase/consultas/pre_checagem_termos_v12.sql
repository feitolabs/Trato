-- ===========================================================================
-- PRÉ-CHECAGEM das migrations dos Termos v1.2 (20261125141500 a 20261125225700).
-- SOMENTE LEITURA. Rodar ANTES de aplicar. Esperado: todas as linhas com presente = true
-- (as falsas aparecem primeiro; qualquer uma impede a aplicação).
-- Confere o que o BANCO tem, não o que o cabeçalho das migrations antigas diz.
--
-- Registro das aplicações (rodar à parte; só existe no Supabase):
--   select version, name from supabase_migrations.schema_migrations
--    where version in ('20261113120000','20261121100000','20261121200000','20261122100000',
--                      '20261124002000','20261124214500','20261124234500') order by 1;
-- ===========================================================================
with exigido (origem, tipo, objeto, detalhe) as (values
  ('F3.2 base',      'tabela',  'public.config_definicoes', null),
  ('F3.2 base',      'tabela',  'public.config_versoes', null),
  ('F3.2 base',      'tabela',  'public.equipe', null),
  ('F3.2 base',      'tabela',  'public.config_parametros', null),
  ('F3.5 dinheiro',  'coluna',  'public.pagamentos', 'confirmado_em'),
  ('F3.2 base',      'coluna',  'public.usuarios', 'status'),
  ('F3.2 base',      'coluna',  'public.profissional_categorias', 'suspensa_em'),
  ('F3.2 base',      'coluna',  'public.profissional_regioes', 'bairro'),
  ('F3.3 pedidos',   'tabela',  'public.contratos', null),
  ('F3.3 pedidos',   'tabela',  'public.orcamentos', null),
  ('F3.3 pedidos',   'tabela',  'public.pedido_historico', null),
  ('F3.3 pedidos',   'funcao',  'public.proteger_colunas()', null),
  ('F3.3 pedidos',   'funcao',  'public.bloquear_alteracao()', null),
  ('F3.4 execucao',  'tabela',  'public.agendamentos', null),
  ('F3.4 execucao',  'tabela',  'public.presencas', null),
  ('F3.4 execucao',  'tabela',  'public.aditivos', null),
  ('F3.4 execucao',  'tabela',  'public.notas_material', null),
  ('F3.4 execucao',  'tabela',  'public.nota_material_itens', null),
  ('F3.6 disputas',  'coluna',  'public.disputas', 'valor_congelado_centavos'),
  ('F3.6 disputas',  'tabela',  'public.avaliacoes', null),
  ('F3.7 auditoria', 'funcao',  'public.registrar_auditoria(uuid,text,text,text,uuid,jsonb,jsonb,text,text,text,text)', null),
  ('LGPD',           'tabela',  'public.lgpd_consentimentos', null),
  ('LGPD',           'tabela',  'public.lgpd_pedidos_exclusao', null),
  ('nota do perfil', 'funcao',  'public.recalcular_perfil_profissional(uuid)', null),
  ('nota do perfil', 'funcao',  'public.avaliacao_recalcula_perfil()', null),
  ('20261113120000 modalidade', 'coluna', 'public.pedidos', 'modalidade'),
  ('20261113120000 modalidade', 'coluna', 'public.perfis_profissional', 'atende_presencial'),
  ('20261113120000 modalidade', 'coluna', 'public.perfis_profissional', 'atende_remoto'),
  ('moedas',         'tabela',  'public.moedas_lancamentos', null),
  ('moedas',         'tabela',  'public.moedas_reservas', null),
  ('moedas',         'tabela',  'public.moedas_orcamento_mensal', null),
  ('moedas',         'tabela',  'public.moedas_orcamento_diario', null),
  ('20261121100000 exclusividade', 'tabela', 'public.exclusividades', null),
  ('20261121100000 exclusividade', 'coluna', 'public.moedas_lancamentos', 'carteira'),
  ('20261121100000 exclusividade', 'coluna', 'public.moedas_config', 'exclusividade_custo_moedas'),
  ('20261121100000 exclusividade', 'coluna', 'public.moedas_config', 'exclusividade_duracao_horas'),
  ('20261121100000 exclusividade', 'coluna', 'public.categorias', 'permite_exclusividade'),
  ('20261121100000 exclusividade', 'check',  'public.pedidos', 'reservado'),
  ('20261121100000 exclusividade', 'check',  'public.moedas_lancamentos', 'exclusividade_estorno'),
  ('20261121200000 funcoes', 'funcao', 'public.exclusividade_solicitar(uuid,uuid,text,timestamptz,integer,integer,integer,integer)', null),
  ('20261121200000 funcoes', 'funcao', 'public.exclusividade_encerrar_por_pedido(uuid,uuid,timestamptz)', null),
  ('20261122100000 nota_decimal', 'coluna', 'public.avaliacoes', 'nota_decimal'),
  ('20261124002000 recorrencias', 'coluna', 'public.recorrencias', 'profissional_id'),
  ('20261124002000 recorrencias', 'coluna', 'public.recorrencia_visitas', 'pedido_id'),
  ('20261124214500 mei',          'coluna', 'public.perfis_profissional', 'mei_status'),
  ('20261124234500 tipo_cnpj',    'coluna', 'public.perfis_profissional', 'tipo_cnpj')
)
select origem, tipo, objeto, detalhe,
       case tipo
         when 'tabela' then to_regclass(objeto) is not null
         when 'funcao' then to_regprocedure(objeto) is not null
         when 'coluna' then exists (select 1 from pg_attribute a
                                     where a.attrelid = to_regclass(objeto) and a.attname = detalhe
                                       and not a.attisdropped)
         when 'check'  then exists (select 1 from pg_constraint k
                                     where k.conrelid = to_regclass(objeto) and k.contype = 'c'
                                       and pg_get_constraintdef(k.oid) like '%' || detalhe || '%')
       end as presente
  from exigido
 order by presente, origem, objeto, detalhe;
