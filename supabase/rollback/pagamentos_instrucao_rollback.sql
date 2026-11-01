-- Desfaz a migration 20261031000000_pagamentos_instrucao.sql.
-- ATENÇÃO: apaga a coluna e os valores dela. Só rodar com OK do João.

alter table public.pagamentos drop column if exists instrucao;
