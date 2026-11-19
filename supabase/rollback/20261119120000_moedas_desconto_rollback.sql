-- Desfaz 20261119120000_moedas_desconto.sql.
-- ATENÇÃO: apaga o registro de quantas moedas cada pagamento usou. Só rode com o OK do João.

begin;
alter table public.pagamentos drop column if exists moedas_usadas;
alter table public.moedas_config drop column if exists max_desconto_percentual;
commit;
