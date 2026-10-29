-- APLICADA no Supabase "Trato" em 29/10/2026 (versão 20261029025741), com o OK do João.
-- A função public.rls_auto_enable() é da plataforma (usada pelo gatilho de evento ensure_rls).
-- O verificador de segurança avisava que anon e authenticated podiam chamá-la pela API (RPC).
-- Revogar o EXECUTE não afeta o gatilho: ele continua ligando o RLS em tabelas novas
-- (testado depois com uma tabela criada e desfeita na mesma transação).
-- Reversão: supabase/rollback/rls_auto_enable_rollback.sql

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
