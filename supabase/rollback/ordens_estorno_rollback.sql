-- Desfaz a migration 20261030120000_ordens_estorno.sql.
-- ATENÇÃO: apaga a tabela de ordens de estorno e os dados dela. Só rodar com OK do João.

drop table if exists public.ordens_estorno;
drop function if exists public.ordens_estorno_validar();

alter table public.pagamentos drop constraint if exists pagamentos_estornado_ate_valor;
alter table public.pagamentos drop column if exists estornado_centavos;
