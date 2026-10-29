-- Desfaz a migration F3.4 (supabase/migrations/20261029030100_f34_execucao.sql).
-- ATENÇÃO: apaga as tabelas e todos os dados delas. Só rodar com OK do João.
-- Rodar ANTES os rollbacks F3.5 a F3.8.

drop table if exists public.presencas;
drop table if exists public.agendamentos;
drop table if exists public.nota_material_itens;
drop table if exists public.notas_material;
drop table if exists public.aditivos;
drop table if exists public.etapas;

drop function if exists public.presencas_validar();
drop function if exists public.agendamentos_validar();
drop function if exists public.nota_material_conferir_total();
drop function if exists public.nota_material_itens_validar();
drop function if exists public.notas_material_validar();
drop function if exists public.aditivos_validar();
drop function if exists public.etapas_validar();
