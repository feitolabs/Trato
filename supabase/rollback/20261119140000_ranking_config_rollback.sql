-- Desfaz 20261119140000_ranking_config.sql.
-- ATENÇÃO: sem a tabela, o backend que lê `ranking_config` falha na busca. Só rode depois de
-- voltar o backend e com o OK do João.

begin;
drop table if exists public.ranking_config;
commit;
