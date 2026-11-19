-- ===========================================================================
-- 20261118150000_remove_faixas_taxa.sql
-- PREPARADA, NÃO APLICADA no Supabase real (CLAUDE.md: precisa do OK do João).
--
-- O Trato é 100% gratuito (decisão do João, 18/11/2026): não há mais taxa nem tabela
-- progressiva. O backend não lê mais `config_faixas_taxa`. Esta migration remove a tabela.
--
-- DESTRUTIVA: apaga as faixas de taxa já gravadas (histórico de configuração). Não afeta:
--   * contratos antigos (`contratos.taxa_*` e `regras_aplicadas` ficam como estão: histórico);
--   * ledger, repasses e fechamento mensal (receita de taxas dos pedidos antigos);
--   * `config_parametros` com chaves `taxa_*` (versões aprovadas são imutáveis; o painel as esconde).
-- NÃO mexe nas colunas legadas de `contratos`, `aditivos` e `repasses`: o backend ainda grava
-- 0 nelas e os repasses antigos dependem delas.
-- Rollback: supabase/rollback/20261118150000_remove_faixas_taxa_rollback.sql (recria a tabela
-- VAZIA; os dados não voltam). Faça backup antes (ver o select abaixo).
-- ===========================================================================

do $$
declare
  v_linhas bigint;
begin
  select count(*) into v_linhas from public.config_faixas_taxa;
  raise notice 'config_faixas_taxa: % linha(s) serão apagadas', v_linhas;
end
$$;

drop trigger if exists config_faixas_proteger_trg on public.config_faixas_taxa;
drop table if exists public.config_faixas_taxa;
drop function if exists public.config_faixas_proteger();
