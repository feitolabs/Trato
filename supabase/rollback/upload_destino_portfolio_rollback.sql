-- Desfaz 20261030140000_upload_destino_portfolio.sql.
-- Antes: confira que não há solicitações com destino 'portfolio'
--   select count(*) from public.upload_solicitacoes where destino = 'portfolio';
alter table public.upload_solicitacoes
  drop constraint upload_solicitacoes_destino_check;
alter table public.upload_solicitacoes
  add constraint upload_solicitacoes_destino_check
  check (destino in ('pedido', 'antes', 'durante', 'depois', 'checkin', 'checkout',
                     'nota_material', 'disputa', 'retrabalho', 'chat', 'avatar',
                     'verificacao'));
