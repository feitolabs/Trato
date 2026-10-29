-- Desfaz a migration F3.8a (supabase/migrations/20261029030500_f38a_funcoes_auxiliares.sql).
-- Rodar DEPOIS dos rollbacks F3.8c e F3.8b (as policies dependem das funções).

drop schema if exists privado cascade;

-- Devolve os privilégios padrão do Supabase para objetos novos em public.
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
alter default privileges in schema public grant all on functions to anon, authenticated;
