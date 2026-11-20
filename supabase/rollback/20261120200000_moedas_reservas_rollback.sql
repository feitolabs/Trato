-- Desfaz 20261120200000_moedas_reservas.sql.
-- ATENÇÃO: apaga o registro das reservas de moedas por cobrança e as 2 colunas da config. Só rode com o OK do João.
-- Antes, confirme que não há reserva 'reservada'/'confirmada' que ainda conte no orçamento.

begin;
drop function if exists public.moedas_expirar_reservas(timestamptz);
drop function if exists public.moedas_devolver_reserva(uuid);
drop function if exists public.moedas_confirmar_reserva(uuid);
drop function if exists public.moedas_reservar_desconto(uuid, uuid, date, date, integer, integer, integer, integer, integer, integer, timestamptz);
drop table if exists public.moedas_reservas;
alter table public.moedas_config
  drop column if exists reserva_minutos,
  drop column if exists max_reservas_abertas;
commit;
