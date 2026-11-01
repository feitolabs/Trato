-- Guarda a instrução de pagamento (Pix copia e cola ou segredo do cartão) junto da cobrança.
-- Por quê: repetir o POST /v1/pedidos/{id}/cobranca devolve a cobrança pendente; sem a coluna o app
-- perderia o código Pix na segunda chamada. Fonte: docs/teste-real-banco.md (achado 7).
--
-- STATUS: APLICADA no Supabase em 31/10/2026 pelo João (SQL Editor). Não reaplicar.
-- Só DDL. Reversão: supabase/rollback/pagamentos_instrucao_rollback.sql
--
-- Sem privilégio novo: o `authenticated` só lê as colunas listadas na F3.8b, então a coluna nova
-- nasce fechada para o app e aberta só para o `service_role` (backend), que já escreve na tabela.

alter table public.pagamentos add column instrucao text;
