-- Desfaz a migration F3.8a (supabase/migrations/20261029030500_f38a_funcoes_auxiliares.sql).
-- Rodar DEPOIS dos rollbacks F3.8c e F3.8b (as policies dependem das funções).
-- Só rodar com OK do João.

drop schema if exists privado cascade;

-- Devolve o privilégio padrão observado no projeto antes da F3.8a (tabelas novas do schema public
-- nascem com TRUNCATE, REFERENCES e TRIGGER para anon e authenticated). É um padrão FRACO: só
-- restaure se for mesmo preciso desfazer. MAINTAIN (Postgres 17) não é restaurado.
alter default privileges in schema public grant truncate, references, trigger on tables to anon, authenticated;
