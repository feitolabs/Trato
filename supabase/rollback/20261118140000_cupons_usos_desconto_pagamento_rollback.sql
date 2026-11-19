drop table if exists public.cupom_usos;

alter table public.pagamentos
  drop column if exists desconto_centavos,
  drop column if exists cupom_codigo;
