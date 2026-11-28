-- ===========================================================================
-- 20261127201500_usuarios_status_inativo.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Objetivo (Termos v1.2, cláusula 4.9 — Conta inativa):
-- ampliar a constraint `usuarios_status_check` em `public.usuarios` para aceitar
-- `'inativo'`, mantendo todos os 4 estados existentes:
--   'ativo' | 'restrito' | 'bloqueado' | 'inativo' | 'anonimizado'
--
-- Mudança aditiva e idempotente (`drop constraint if exists` + `add constraint`),
-- em transação única, sem UPDATE de dados e sem alterar RLS, grants ou triggers.
-- Depende apenas de: 20261029025430_f32_identidade_catalogo_config.sql (public.usuarios).
--
-- Rollback: supabase/rollback/20261127201500_usuarios_status_inativo_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.usuarios') is null then
    raise exception 'Pré-requisito ausente: tabela public.usuarios não existe (aplicar F3.2 primeiro).';
  end if;
end $$;

alter table public.usuarios
  drop constraint if exists usuarios_status_check;

alter table public.usuarios
  add constraint usuarios_status_check
  check (status in ('ativo', 'restrito', 'bloqueado', 'inativo', 'anonimizado'));

commit;