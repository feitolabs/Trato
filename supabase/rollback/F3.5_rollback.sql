-- Desfaz a migration F3.5 (supabase/migrations/20261029030200_f35_dinheiro_ledger.sql), versão do caminho A (D15).
-- ATENÇÃO: apaga as tabelas e todos os dados delas, INCLUSIVE O LEDGER. Só rodar com OK do João
-- e nunca depois que houver dinheiro real registrado (o ledger é imutável de propósito).
-- Rodar ANTES os rollbacks F3.6 a F3.8.

drop table if exists public.partidas;
-- lancamentos e repasses se referenciam: CASCADE só derruba as FKs entre eles.
drop table if exists public.repasses cascade;
drop table if exists public.lancamentos cascade;
drop table if exists public.contas_ledger;
drop table if exists public.eventos_webhook;
drop table if exists public.pagamentos;

drop function if exists public.repasses_validar();
drop function if exists public.ledger_conferir_equilibrio();
drop function if exists public.partidas_validar();
drop function if exists public.lancamentos_preparar();
drop function if exists public.pagamentos_validar();
