-- ===========================================================================
-- 20261104120000_admin_catalogo_delete.sql
-- O painel exclui categorias sem pedidos nem profissionais vinculados
-- (DELETE /v1/admin/categorias/{id}), mas o service_role não tinha DELETE nessas duas tabelas:
-- a rota respondia 500 "O backend não tem permissão para essa operação no banco".
--
-- Só catálogo. Pedidos, ledger, auditoria e usuários continuam sem DELETE.
-- A rota já barra categoria com pedido ou profissional (409) e grava a auditoria.
-- Rollback: revoke delete on public.categorias, public.categoria_perguntas from service_role;
-- ===========================================================================

grant delete on public.categorias, public.categoria_perguntas to service_role;
