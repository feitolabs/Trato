-- PRÉ-CHECAGEM das migrations 20261126061000 e 20261126061100. SOMENTE LEITURA.
-- Rodar depois das migrations 20261125* e antes destas duas.
-- Esperado: todas as linhas com ok = true (as falsas aparecem primeiro).
with itens (item, ok) as (
  select 'lancamentos e partidas', to_regclass('public.lancamentos') is not null
                                   and to_regclass('public.partidas') is not null
  union all select 'contas_ledger', to_regclass('public.contas_ledger') is not null
  union all select 'eventos_webhook', to_regclass('public.eventos_webhook') is not null
  union all select 'lancamentos.disputa_id', exists (select 1 from pg_attribute
      where attrelid = to_regclass('public.lancamentos') and attname = 'disputa_id' and not attisdropped)
  union all select 'tipo reembolso aceito no livro', exists (select 1 from pg_constraint
      where conrelid = to_regclass('public.lancamentos') and contype = 'c'
        and pg_get_constraintdef(oid) like '%reembolso%')
  union all select 'disputas', to_regclass('public.disputas') is not null
  union all select 'contestacoes de cartão (20261108120000)', to_regclass('public.contestacoes') is not null
  union all select 'disputa_contestacoes (20261125224700)', to_regclass('public.disputa_contestacoes') is not null
  union all select 'registrar_auditoria',
      to_regprocedure('public.registrar_auditoria(uuid,text,text,text,uuid,jsonb,jsonb,text,text,text,text)') is not null
  union all select 'ausencias_cliente (20261125141500)', to_regclass('public.ausencias_cliente') is not null
  union all select 'midias', to_regclass('public.midias') is not null
  union all select 'ninguém usa ainda o código a_compensar ou a migration já está aplicada',
      to_regclass('public.compensacoes_dividas') is not null
      or not exists (select 1 from public.contas_ledger where codigo = 'a_compensar')
)
select item, ok from itens order by ok, item;
