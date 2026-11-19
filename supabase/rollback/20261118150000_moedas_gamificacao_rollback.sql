-- Desfaz 20261118150000_moedas_gamificacao.sql.
-- ATENÇÃO: apaga o livro de moedas. Só rode com o OK do João e depois de exportar a tabela.

begin;
drop table if exists public.moedas_lancamentos;
drop table if exists public.moedas_config;
commit;
