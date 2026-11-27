-- PRÉ-CHECAGEM das migrations 20261126195000 a 20261126231900 (itens 14 a 19 do DB-ORDEM-PUB).
-- SOMENTE LEITURA. Rodar depois das migrations até 20261126061100 (itens 1 a 13) e antes destas.
-- Esperado ANTES de aplicar: todas as linhas com ok = true (as falsas aparecem primeiro).
-- Qualquer falsa: não aplicar a migration daquela linha sem entender o motivo.
-- A coluna esperado_depois diz o valor de ok depois de aplicar as seis (false = a linha vira
-- false de propósito: o objeto passou a existir ou o corpo antigo foi trocado).
-- Pressupõe as tabelas de base public.config_definicoes (F3.2) e storage.buckets (F3.8c):
-- sem elas a consulta dá erro, o que também impede a aplicação.
-- Não confere grants nem dados pessoais.
--
-- Informativo (rodar à parte; guardar o resultado para conferir o rollback da 231800):
--   select id, allowed_mime_types, file_size_limit, public from storage.buckets where id = 'pedido-midias';
with tabelas (mig, objeto) as (values
  ('14 195000', 'public.compensacoes_dividas'),
  ('14 195000', 'public.compensacoes_aplicadas'),
  ('14 195000', 'public.contratos'),
  ('14 195000', 'public.pedidos'),
  ('14 195000', 'public.perfis_profissional'),
  ('14 195000', 'public.equipe'),
  ('14 195000', 'public.lancamentos'),
  ('15 195100', 'public.medida_contestacoes'),
  ('17 213500', 'public.medidas_conta'),
  ('17 213500', 'public.usuarios'),
  ('17 213500', 'public.config_parametros'),
  ('17 213500', 'public.config_versoes'),
  ('19 231900', 'public.midias'),
  ('19 231900', 'public.notas_material'),
  ('19 231900', 'public.nota_material_contestacoes'),
  ('19 231900', 'public.disputa_evidencias')
),
colunas (mig, tabela, coluna) as (values
  ('15 195100', 'public.medida_contestacoes', 'versao_usuario'),
  ('15 195100', 'public.medida_contestacoes', 'anexos'),
  ('15 195100', 'public.medida_contestacoes', 'resposta'),
  ('15 195100', 'public.medida_contestacoes', 'mesmo_analista_justificativa'),
  ('15 195100', 'public.medida_contestacoes', 'decidida_em'),
  ('17 213500', 'public.medidas_conta', 'usuario_id'),
  ('17 213500', 'public.medidas_conta', 'tipo'),
  ('17 213500', 'public.medidas_conta', 'inicio_em'),
  ('17 213500', 'public.medidas_conta', 'revertida_em'),
  ('19 231900', 'public.notas_material', 'midia_id'),
  ('19 231900', 'public.nota_material_contestacoes', 'nota_id'),
  ('19 231900', 'public.nota_material_contestacoes', 'anexos')
),
funcoes (mig, assinatura) as (values
  ('14 195000', 'public.compensacao_criar_divida(text,uuid,uuid,uuid,bigint,bigint,text,uuid,uuid,uuid)'),
  ('14 195000', 'public.compensacao_conta(text,uuid)'),
  ('14 195000', 'public.compensacao_lancar(uuid,text,uuid,uuid,bigint,text,text,uuid,uuid,uuid)'),
  ('14 195000', 'public.registrar_auditoria(uuid,text,text,text,uuid,jsonb,jsonb,text,text,text,text)'),
  ('14 195000', 'public.proteger_colunas()'),
  ('14 195000', 'public.bloquear_alteracao()'),
  ('15 195100', 'public.medida_contestacoes_validar()'),
  ('17 213500', 'public.sac_gerar_protocolo()'),
  ('19 231900', 'privado.pode_ver_midia(uuid)'),
  ('19 231900', 'privado.pode_ver_pedido(uuid)'),
  ('19 231900', 'privado.eh_participante_da_conversa(uuid)'),
  ('19 231900', 'privado.mediador_com_disputa_no_pedido(uuid)'),
  ('19 231900', 'privado.eh_parte_da_disputa(uuid)'),
  ('19 231900', 'privado.eh_parte_do_pedido(uuid)'),
  ('19 231900', 'privado.eh_equipe(text[])')
),
itens (mig, item, ok, esperado_depois) as (
  -- requisitos: continuam true depois de aplicar
  select mig, 'tabela ' || objeto, to_regclass(objeto) is not null, true from tabelas
  union all
  select mig, 'coluna ' || tabela || '.' || coluna,
         exists (select 1 from pg_attribute a
                  where a.attrelid = to_regclass(tabela) and a.attname = coluna and not a.attisdropped),
         true
    from colunas
  union all
  select mig, 'função ' || assinatura, to_regprocedure(assinatura) is not null, true from funcoes

  -- 14: a assinatura antiga do aviso existe e as duas funções recriadas têm o mesmo retorno
  union all select '14 195000', 'compensacao_avisar(uuid) antiga existe (a migration remove)',
         to_regprocedure('public.compensacao_avisar(uuid)') is not null, false
  union all select '14 195000', 'retorno de compensacao_registrar_regresso igual ao esperado',
         coalesce(pg_get_function_result(to_regprocedure(
           'public.compensacao_registrar_regresso(uuid,uuid,bigint,text,uuid,uuid)'))
           = 'TABLE(resultado text, divida_id uuid, maximo_centavos bigint)', false), true
  union all select '14 195000', 'retorno de compensacao_cancelar igual ao esperado',
         coalesce(pg_get_function_result(to_regprocedure('public.compensacao_cancelar(uuid,uuid,text)'))
           = 'TABLE(resultado text, devolvido_centavos bigint)', false), true
  union all select '14 195000', 'ainda não aplicada: tabela compensacao_propostas_regresso ausente',
         to_regclass('public.compensacao_propostas_regresso') is null, false

  -- 15
  union all select '15 195100', 'gatilhos medida_contestacoes_proteger e _validar_trg existem',
         (select count(*) = 2 from pg_trigger t
           where t.tgrelid = to_regclass('public.medida_contestacoes')
             and t.tgname in ('medida_contestacoes_proteger', 'medida_contestacoes_validar_trg')), true
  union all select '15 195100', 'ainda não aplicada: anonimizar_contestacao_medida ausente',
         to_regprocedure('public.anonimizar_contestacao_medida(uuid,uuid,text)') is null, false

  -- 16
  union all select '16 204500', 'config_definicoes aceita unidade horas',
         exists (select 1 from pg_constraint k
                  where k.conrelid = to_regclass('public.config_definicoes')
                    and k.conname = 'config_definicoes_unidade_check'
                    and pg_get_constraintdef(k.oid) like '%''horas''%'), true
  union all select '16 204500', 'ainda não aplicada: nenhuma das 2 definições de lembrete existe',
         not exists (select 1 from public.config_definicoes
                      where chave in ('lembrete_confirmacao_antecedencia_horas',
                                      'lembrete_resposta_disputa_antecedencia_horas')), false

  -- 17
  union all select '17 213500', 'config_definicoes aceita unidade dias',
         exists (select 1 from pg_constraint k
                  where k.conrelid = to_regclass('public.config_definicoes')
                    and k.conname = 'config_definicoes_unidade_check'
                    and pg_get_constraintdef(k.oid) like '%''dias''%'), true
  union all select '17 213500', 'ainda não aplicada: definição conta_retorno_prazo_dias ausente',
         not exists (select 1 from public.config_definicoes where chave = 'conta_retorno_prazo_dias'), false
  union all select '17 213500', 'ainda não aplicada: medidas_conta sem infracao_grave e impedir_nova_conta',
         not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.medidas_conta') and not a.attisdropped
                        and a.attname in ('infracao_grave', 'impedir_nova_conta')), false
  union all select '17 213500', 'ainda não aplicada: tabela conta_impedimentos_cadastro ausente',
         to_regclass('public.conta_impedimentos_cadastro') is null, false
  union all select '17 213500', 'ainda não aplicada: tabela conta_pedidos_retorno ausente',
         to_regclass('public.conta_pedidos_retorno') is null, false

  -- 18
  union all select '18 231800', 'bucket pedido-midias existe e é privado',
         exists (select 1 from storage.buckets where id = 'pedido-midias' and not public), true
  union all select '18 231800', 'lista de tipos preenchida (se for nula, a migration não muda nada)',
         exists (select 1 from storage.buckets
                  where id = 'pedido-midias' and allowed_mime_types is not null), true
  union all select '18 231800', 'ainda não aplicada: lista sem application/pdf',
         not exists (select 1 from storage.buckets
                      where id = 'pedido-midias' and 'application/pdf' = any (allowed_mime_types)), false

  -- 19: o corpo atual precisa ser o da F3.8a, senão a migration e o rollback apagam outra mudança.
  -- md5 do corpo sem espaços nem quebras de linha.
  union all select '19 231900', 'corpo de pode_ver_midia é o original da F3.8a',
         coalesce((select md5(regexp_replace(p.prosrc, '\s+', '', 'g')) = 'bcbdf02a6649d384078bb9964abc6c7a'
                     from pg_proc p where p.oid = to_regprocedure('privado.pode_ver_midia(uuid)')), false), false
  union all select '19 231900', 'ainda não aplicada: midia_de_nota_contestada ausente',
         to_regprocedure('privado.midia_de_nota_contestada(uuid)') is null, false
)
select mig, item, ok, esperado_depois from itens order by ok, mig, item;
