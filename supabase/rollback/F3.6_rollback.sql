-- Desfaz a migration F3.6 (supabase/migrations/20261029030300_f36_disputas_garantias_avaliacoes.sql).
-- ATENÇÃO: apaga as tabelas e todos os dados delas. Só rodar com OK do João.
-- Rodar ANTES os rollbacks F3.7 e F3.8.

alter table public.lancamentos drop constraint if exists lancamentos_disputa_fk;
alter table public.repasses drop constraint if exists repasses_disputa_fk;

drop table if exists public.avaliacao_criterios;
drop table if exists public.avaliacoes;
drop table if exists public.retrabalhos;
drop table if exists public.garantias;
drop table if exists public.disputa_evidencias;
drop table if exists public.disputas;

drop function if exists public.avaliacao_criterios_validar();
drop function if exists public.avaliacoes_validar();
drop function if exists public.retrabalhos_validar();
drop function if exists public.disputa_evidencias_validar();
drop function if exists public.disputas_validar();
