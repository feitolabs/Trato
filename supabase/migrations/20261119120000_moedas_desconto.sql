-- Gamificação, fase 2: usar moedas como desconto no pagamento.
-- 1) moedas_config: teto do desconto por serviço (percentual do valor).
-- 2) pagamentos: quantas moedas a cobrança usou (para debitar na confirmação e devolver no estorno).
-- O desconto em reais continua em pagamentos.desconto_centavos (mesmo campo do cupom).
-- NÃO APLICADA: precisa do OK do João. Rollback em supabase/rollback/.

begin;

alter table public.moedas_config
  add column if not exists max_desconto_percentual integer not null default 20
    check (max_desconto_percentual between 0 and 100);

alter table public.pagamentos
  add column if not exists moedas_usadas integer not null default 0
    check (moedas_usadas >= 0);

commit;
