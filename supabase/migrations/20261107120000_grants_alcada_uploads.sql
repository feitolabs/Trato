-- ===========================================================================
-- 20261107120000_grants_alcada_uploads.sql
-- Duas permissões que faltavam ao service_role (papel do backend):
--
-- 1. public.papeis_alcada (criada em 20261103120000 sem grant). O login do painel chama
--    GET /v1/admin/eu, que lê o teto de alçada do papel: o Postgres recusava com
--    "permission denied for table papeis_alcada" e a tela mostrava
--    "O backend não tem permissão para essa operação no banco". Só leitura: o teto muda por
--    migration, não pela API.
--
-- 2. public.upload_solicitacoes: o backend apaga a tentativa PENDENTE anterior no mesmo
--    caminho antes de gravar a nova. Sem DELETE, a transação inteira falhava e a solicitação
--    ficava só na memória do processo (some no restart ou em outro worker).
--
-- Pedidos, ledger, auditoria e usuários continuam sem DELETE.
-- Rollback:
--   revoke select on public.papeis_alcada from service_role;
--   revoke delete on public.upload_solicitacoes from service_role;
-- ===========================================================================

grant select on public.papeis_alcada to service_role;
grant delete on public.upload_solicitacoes to service_role;
