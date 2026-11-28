-- Rollback de 20261127122600_bloquear_conta_anonimizada.sql
-- RASCUNHO (DB-LOTE-A). NÃO aplicado no Supabase de produção. Só tira gatilhos; não toca em dados.

begin;

drop trigger if exists pedidos_conta_anonimizada_trg on public.pedidos;
drop trigger if exists contratos_conta_anonimizada_trg on public.contratos;
drop function if exists public.recusar_conta_anonimizada();

commit;
