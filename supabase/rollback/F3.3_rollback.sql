-- Desfaz a migration F3.3 (supabase/migrations/20261029030000_f33_pedidos_orcamentos_contratos.sql).
-- ATENÇÃO: apaga as tabelas e todos os dados delas. Só rodar com OK do João.
-- Rodar ANTES os rollbacks F3.4 a F3.8 (ordem inversa das dependências).

drop table if exists public.contratos;
drop table if exists public.orcamento_itens;
drop table if exists public.orcamentos;
drop table if exists public.midias;
drop table if exists public.pedido_historico;
drop table if exists public.pedido_respostas;
drop table if exists public.pedidos_endereco;
drop table if exists public.pedidos;

drop function if exists public.contratos_validar();
drop function if exists public.orcamento_conferir_total();
drop function if exists public.orcamento_itens_validar();
drop function if exists public.orcamentos_validar();
drop function if exists public.proteger_colunas();
drop function if exists public.bloquear_alteracao();
