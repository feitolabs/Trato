-- Risco e antifraude (painel v2, RF-RIS-01 a RF-RIS-03): o alerta ganha pedido, responsável, status
-- (em aberto, em análise, resolvido) e resultado (procedente ou improcedente).
-- Só acrescenta colunas; não apaga nem altera dado existente. Autorizado pelo João (03/11/2026).

alter table public.alertas_risco add column if not exists pedido_id uuid references public.pedidos (id);
alter table public.alertas_risco add column if not exists responsavel_id uuid references public.usuarios (id);
alter table public.alertas_risco add column if not exists status text not null default 'em_aberto'
  check (status in ('em_aberto', 'em_analise', 'resolvido'));
alter table public.alertas_risco add column if not exists resultado text
  check (resultado is null or resultado in ('procedente', 'improcedente'));

update public.alertas_risco set status = 'resolvido' where resolvido and status = 'em_aberto';

-- Um alerta automático por pedido e tipo (a detecção roda várias vezes sem duplicar).
create unique index if not exists alertas_risco_pedido_tipo_uq
  on public.alertas_risco (pedido_id, tipo) where pedido_id is not null;
