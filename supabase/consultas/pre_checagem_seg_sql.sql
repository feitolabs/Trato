-- PRÉ-CHECAGEM de 20261127190000, 190100 e 190200. SOMENTE LEITURA.
-- Antes de aplicar: todas as linhas com ok = true. esperado_depois = valor de ok depois das três.
with itens (item, ok, esperado_depois) as (
  select '190000 requisito: preservação (122500)',
         to_regprocedure('public.usuario_com_registros_preservados(uuid)') is not null, true
  union all select '190000 ainda não aplicada: fila do expurgo ausente',
         to_regprocedure('public.expurgo_acessos_enfileirar()') is null, false
  union all select '190100 requisito: trava por fraude (001000)',
         to_regprocedure('public.medidas_conta_fraude_validar()') is not null, true
  union all select '190100 ainda não aplicada: reversão sem conferência de papel',
         coalesce(position('new.revertida_por and q.ativo' in pg_get_functiondef(to_regprocedure('public.medidas_conta_fraude_validar()'))), 0) = 0, false
  union all select '190200 requisito: 004000 e 061000',
         to_regprocedure('privado.contrato_conta_no_pedido(uuid)') is not null and to_regprocedure('public.termos_versao_vigente(timestamptz)') is not null, true
  union all select '190200 ainda não aplicada: fuso fixo',
         coalesce(position('dia_em_brasilia' in pg_get_functiondef(to_regprocedure('public.termos_versao_vigente(timestamptz)'))), 0) = 0, false
)
select item, ok, esperado_depois from itens order by ok, item;
