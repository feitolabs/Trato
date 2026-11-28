-- Rollback de 20261127185000_aditivo_pago_uma_vez.sql
-- RASCUNHO (DB-SEG-A1). NÃO aplicado no Supabase de produção. Só remove o índice; não toca em dados.

begin;

drop index if exists public.pagamentos_aditivo_pago_uidx;

commit;
