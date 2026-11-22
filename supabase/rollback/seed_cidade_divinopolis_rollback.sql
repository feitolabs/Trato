-- =============================================================================
-- Rollback de supabase/seeds/seed_cidade_divinopolis.sql
-- ATENÇÃO: só com OK do João.
--
-- Remove apenas a linha ('Divinópolis', 'MG') que o seed pode ter inserido.
-- Não apaga 'Divinopolis' (sem acento) pré-existente em produção.
-- Falha de propósito (nada é apagado) se já houver pedido ou profissional ligado
-- à cidade (chaves estrangeiras com ON DELETE RESTRICT). Nesse caso, desative em
-- vez de apagar:
--   update public.cidades set ativa = false where nome = 'Divinópolis' and uf = 'MG';
-- =============================================================================

begin;

delete from public.cidades
 where nome = 'Divinópolis'
   and uf = 'MG';

commit;