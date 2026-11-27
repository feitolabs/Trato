-- PRÉ-CHECAGEM da migration 20261127001000_trava_saque_fraude. SOMENTE LEITURA.
-- Rodar depois das migrations até 20261126231900 e antes desta.
-- Esperado ANTES de aplicar: todas as linhas com ok = true (as falsas aparecem primeiro).
-- esperado_depois = valor de ok depois de aplicar (false = o objeto passou a existir).
-- Pressupõe public.config_definicoes (F3.2): sem ela a consulta dá erro.
--
-- Informativo (rodar à parte): travas já existentes, que continuam sem segurar valor:
--   select origem, count(*) from public.medidas_conta where tipo = 'trava_saque' group by origem;
with itens (item, ok, esperado_depois) as (
  select 'tabelas medidas_conta, equipe, config_parametros e config_versoes',
         to_regclass('public.medidas_conta') is not null and to_regclass('public.equipe') is not null
         and to_regclass('public.config_parametros') is not null
         and to_regclass('public.config_versoes') is not null, true
  union all select '20261126213500 aplicada: coluna medidas_conta.infracao_grave',
         exists (select 1 from pg_attribute where attrelid = to_regclass('public.medidas_conta')
                  and attname = 'infracao_grave' and not attisdropped), true
  union all select 'função proteger_colunas()', to_regprocedure('public.proteger_colunas()') is not null, true
  union all select 'check das 72 h da medida automática',
         exists (select 1 from pg_constraint where conrelid = to_regclass('public.medidas_conta')
                  and conname = 'medidas_conta_automatica_check'), true
  union all select 'config_definicoes aceita unidade dias',
         exists (select 1 from pg_constraint where conrelid = to_regclass('public.config_definicoes')
                  and conname = 'config_definicoes_unidade_check'
                  and pg_get_constraintdef(oid) like '%''dias''%'), true
  union all select 'ainda não aplicada: colunas motivo_fraude e limite_retencao_centavos ausentes',
         not exists (select 1 from pg_attribute where attrelid = to_regclass('public.medidas_conta')
                      and attname in ('motivo_fraude', 'limite_retencao_centavos')
                      and not attisdropped), false
  union all select 'ainda não aplicada: definição trava_fraude_prazo_maximo_dias ausente',
         not exists (select 1 from public.config_definicoes
                      where chave = 'trava_fraude_prazo_maximo_dias'), false
  union all select 'ainda não aplicada: funções da trava por fraude ausentes',
         to_regprocedure('public.medidas_conta_fraude_validar()') is null
         and to_regprocedure('public.trava_fraude_prazo_maximo_dias_vigente()') is null, false
)
select item, ok, esperado_depois from itens order by ok, item;
