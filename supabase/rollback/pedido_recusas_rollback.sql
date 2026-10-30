-- Desfaz a migration 20261030130000_pedido_recusas.sql.
-- ATENÇÃO: apaga a tabela de recusas e os dados dela. Só rodar com OK do João.

drop table if exists public.pedido_recusas;
