-- Desfaz a migration F3.2 (supabase/migrations/20261028000100_f32_identidade_catalogo_config.sql).
-- ATENÇÃO: apaga as tabelas e todos os dados delas. Só rodar com OK do João.
-- Ordem inversa das dependências.

drop table if exists public.config_faixas_taxa;
drop table if exists public.config_parametros;
drop table if exists public.config_versoes;
drop table if exists public.config_definicoes;
drop table if exists public.verificacao_documentos;
drop table if exists public.verificacoes;
drop table if exists public.profissional_regioes;
drop table if exists public.profissional_categorias;
drop table if exists public.perfis_profissional;
drop table if exists public.categoria_perguntas;
drop table if exists public.categorias;
drop table if exists public.cidades;
drop table if exists public.equipe;
drop table if exists public.usuarios_privados;
drop table if exists public.usuarios;

drop function if exists public.config_faixas_proteger();
drop function if exists public.config_parametros_validar();
drop function if exists public.config_versoes_proteger();
drop function if exists public.definir_atualizado_em();

-- A extensão btree_gist é deixada instalada de propósito (inofensiva e usada por outras migrations).
