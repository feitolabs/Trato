-- F6 — CPF opcional no cadastro inicial (coletado antes do primeiro pagamento via POST /v1/me/cpf).
-- APLICADA no Supabase Trato em 2026-11-20 com o OK do João. Rollback em supabase/rollback/.
--
-- Mantém a constraint UNIQUE existente em public.usuarios_privados(cpf):
-- em PostgreSQL, NULL não conflita em UNIQUE, então CPFs preenchidos continuam únicos.

begin;

alter table public.usuarios_privados
  alter column cpf drop not null;

commit;
