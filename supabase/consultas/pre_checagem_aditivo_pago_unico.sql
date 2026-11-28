-- PRÉ-CHECAGEM de 20261127185000_aditivo_pago_uma_vez. SOMENTE LEITURA (dois SELECT).
-- [1] Antes de aplicar: todas as linhas com ok = true. esperado_depois = valor de ok depois.
-- [2] Antes de aplicar: nenhuma linha. Cada linha é um aditivo pago mais de uma vez: a migration
--     falha até resolver. Não apagar linha de pagamento; estorno é decisão à parte, com OK.

-- [1]
with itens (item, ok, esperado_depois) as (
  select 'requisito: tabela pagamentos com aditivo_id',
         exists (select 1 from pg_attribute where attrelid = to_regclass('public.pagamentos')
                  and attname = 'aditivo_id' and not attisdropped), true
  union all select 'dados: nenhum aditivo pago mais de uma vez',
         not exists (select 1 from public.pagamentos
                      where aditivo_id is not null and status in ('confirmado', 'reembolsado_parcial', 'contestado')
                      group by aditivo_id having count(*) > 1), true
  union all select 'ainda não aplicada: índice pagamentos_aditivo_pago_uidx ausente',
         to_regclass('public.pagamentos_aditivo_pago_uidx') is null, false
)
select item, ok, esperado_depois from itens order by ok, item;

-- [2]
select aditivo_id,
       count(*) as pagamentos,
       sum(valor_centavos) as cobrado_centavos,
       sum(estornado_centavos) as estornado_centavos,
       array_agg(id order by criado_em) as pagamento_ids,
       array_agg(status order by criado_em) as estados
  from public.pagamentos
 where aditivo_id is not null and status in ('confirmado', 'reembolsado_parcial', 'contestado')
 group by aditivo_id
having count(*) > 1
 order by aditivo_id;
