-- Upload: novo destino `portfolio` em upload_solicitacoes.
--
-- STATUS: APLICADA no Supabase em 30/10/2026 com o OK do João.
-- Reversão: supabase/rollback/upload_destino_portfolio_rollback.sql
--
-- O backend já aceita `POST /v1/uploads` com destino `portfolio` (foto do portfólio do
-- profissional; imagem apenas, EXIF/GPS removidos). Hoje as solicitações ainda ficam em memória;
-- quando o adaptador Postgres de `upload_solicitacoes` entrar, a CHECK abaixo precisa conhecer o
-- destino novo. O bucket continua `avatar` (pasta `<dono>/portfolio/`), então só `destino` muda.

alter table public.upload_solicitacoes
  drop constraint upload_solicitacoes_destino_check;
alter table public.upload_solicitacoes
  add constraint upload_solicitacoes_destino_check
  check (destino in ('pedido', 'antes', 'durante', 'depois', 'checkin', 'checkout',
                     'nota_material', 'disputa', 'retrabalho', 'chat', 'avatar',
                     'verificacao', 'portfolio'));
