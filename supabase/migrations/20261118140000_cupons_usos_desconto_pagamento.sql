-- ===========================================================================
-- 20261118140000_cupons_usos_desconto_pagamento.sql
-- PREPARADA, NÃO APLICADA no Supabase real (CLAUDE.md).
--
-- 1. Guarda cupom_codigo e desconto_centavos diretamente em public.pagamentos
--    para consulta consistente de pagamento e custo real de cupons no mês.
-- 2. Cria public.cupom_usos para contabilizar usos confirmados no webhook
--    (com unicidade por cobranca_id) e aplicar limite_por_usuario.
-- ===========================================================================

alter table public.pagamentos
  add column if not exists cupom_codigo text,
  add column if not exists desconto_centavos bigint not null default 0
    check (desconto_centavos >= 0);

create table if not exists public.cupom_usos (
  id                uuid primary key default gen_random_uuid(),
  cupom_codigo      text not null references public.cupons (codigo) on delete cascade,
  usuario_id        uuid not null references public.usuarios (id) on delete restrict,
  cobranca_id       text not null unique check (btrim(cobranca_id) <> ''),
  pedido_id         uuid not null references public.pedidos (id) on delete cascade,
  desconto_centavos bigint not null default 0 check (desconto_centavos >= 0),
  confirmado_em     timestamptz not null default now()
);

create index if not exists cupom_usos_codigo_usuario_idx
  on public.cupom_usos (cupom_codigo, usuario_id);

create index if not exists cupom_usos_confirmado_em_idx
  on public.cupom_usos (confirmado_em);

alter table public.cupom_usos enable row level security;

grant select, insert, update, delete on public.cupom_usos to service_role;
