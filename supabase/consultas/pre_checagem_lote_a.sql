-- PRÉ-CHECAGEM de 20261127061000, 061100, 061200, 092000, 122500, 122600 e 133600. SOMENTE LEITURA.
-- Antes de aplicar cada uma, as linhas do prefixo dela devem ter ok = true. Rodando tudo antes
-- das sete, os requisitos criados por uma delas (061200 para a 122500; 092000 para a 133600) aparecem false.
-- esperado_depois = valor de ok depois de aplicar as sete.
-- A linha "dados" da 092000 pressupõe moedas_lancamentos (sem ela a consulta dá erro).
with itens (item, ok, esperado_depois) as (
  select '061000 requisito: contratos, pagamentos e bloquear_alteracao()',
         to_regclass('public.contratos') is not null and to_regclass('public.pagamentos') is not null and to_regprocedure('public.bloquear_alteracao()') is not null, true
  union all select '061000 ainda não aplicada: termos_versoes ausente',
         to_regclass('public.termos_versoes') is null, false
  union all select '061000 ainda não aplicada: contratos.termos_versao ausente',
         not exists (select 1 from pg_attribute where attrelid = to_regclass('public.contratos') and attname = 'termos_versao' and not attisdropped), false
  union all select '061100 requisito: avaliacao_ocultacoes (225600)',
         to_regclass('public.avaliacao_ocultacoes') is not null, true
  union all select '061100 requisito: recalcular_perfil_profissional ainda filtra publicada',
         coalesce(position('a.status = ''publicada''' in pg_get_functiondef(to_regprocedure('public.recalcular_perfil_profissional(uuid)'))) > 0, false), false
  union all select '061100 ainda não aplicada: nota_publica_profissional ausente',
         to_regprocedure('public.nota_publica_profissional(uuid)') is null, false
  union all select '061200 requisito: usuarios, equipe, disputas e proteger_colunas()',
         to_regclass('public.usuarios') is not null and to_regclass('public.equipe') is not null and to_regclass('public.disputas') is not null and to_regprocedure('public.proteger_colunas()') is not null, true
  union all select '061200 ainda não aplicada: acessos_conta ausente',
         to_regclass('public.acessos_conta') is null, false
  union all select '092000 requisito: moedas_saldo (150000)',
         to_regprocedure('public.moedas_saldo(uuid,text,timestamptz)') is not null, true
  union all select '092000 requisito: medidas_conta.infracao_grave e conta_pedidos_retorno (213500)',
         exists (select 1 from pg_attribute where attrelid = to_regclass('public.medidas_conta') and attname = 'infracao_grave' and not attisdropped) and to_regclass('public.conta_pedidos_retorno') is not null, true
  union all select '092000 dados: nenhuma chave começando com restauracao: no livro',
         not exists (select 1 from public.moedas_lancamentos where chave_idempotencia like 'restauracao:%'), true
  union all select '092000 ainda não aplicada: medidas_conta.sem_falta ausente',
         not exists (select 1 from pg_attribute where attrelid = to_regclass('public.medidas_conta') and attname = 'sem_falta' and not attisdropped), false
  union all select '122500 requisito: incidentes (225500), chamados (224500) e pedidos do titular (225700)',
         to_regclass('public.incidente_medidas') is not null and to_regclass('public.chamado_mensagens') is not null and to_regclass('public.lgpd_pedidos_titular') is not null, true
  union all select '122500 requisito: anonimização de contestação (195100)',
         to_regprocedure('public.anonimizar_contestacao_medida(uuid,uuid,text)') is not null, true
  union all select '122500 requisito: acessos_conta (061200)',
         to_regclass('public.acessos_conta') is not null, true
  union all select '122500 ainda não aplicada: função de preservação ausente',
         to_regprocedure('public.usuario_com_registros_preservados(uuid)') is null, false
  union all select '122600 requisito: pedidos, contratos e usuarios',
         to_regclass('public.pedidos') is not null and to_regclass('public.contratos') is not null and to_regclass('public.usuarios') is not null, true
  union all select '122600 ainda não aplicada: gatilhos ausentes',
         not exists (select 1 from pg_trigger where tgrelid = to_regclass('public.pedidos') and tgname = 'pedidos_conta_anonimizada_trg' and not tgisinternal) and not exists (select 1 from pg_trigger where tgrelid = to_regclass('public.contratos') and tgname = 'contratos_conta_anonimizada_trg' and not tgisinternal), false
  union all select '133600 requisito: moedas_restauracao_devida (092000)',
         to_regprocedure('public.moedas_restauracao_devida(uuid,text,timestamptz)') is not null, true
  union all select '133600 ainda não aplicada: restauração ainda sem o rastreio dos lotes do encerramento',
         coalesce(position('v_eleg[v_idx]' in pg_get_functiondef(to_regprocedure('public.moedas_restauracao_devida(uuid,text,timestamptz)'))), 0) = 0, false
)
select item, ok, esperado_depois from itens order by ok, item;
