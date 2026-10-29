-- Desfaz supabase/migrations/20261029025741_revogar_execute_rls_auto_enable.sql.
-- Devolve o EXECUTE público (estado original da plataforma). Só rodar com OK do João.

grant execute on function public.rls_auto_enable() to public, anon, authenticated;
