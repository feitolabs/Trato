-- Desfaz 20261107120000_grants_alcada_uploads.sql (só permissões; dados intactos). Só com OK do João.
-- Atenção: sem o SELECT, o login do painel admin volta a falhar (GET /v1/admin/eu).
revoke select on public.papeis_alcada from service_role;
revoke delete on public.upload_solicitacoes from service_role;
