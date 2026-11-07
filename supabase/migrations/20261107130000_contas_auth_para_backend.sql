-- ===========================================================================
-- 20261107130000_contas_auth_para_backend.sql
-- O service_role (papel do backend) não lê auth.users. Painel quebrava com
-- "permission denied for table users" em:
--   * Busca e suporte > Usuários (e-mail mascarado de cada usuário);
--   * Equipe (e-mail e último acesso de cada membro; adicionar membro pelo e-mail);
--   * Perfil (e-mail da própria conta: hoje some em silêncio).
--
-- Em vez de dar SELECT na tabela inteira do Auth (senha criptografada, tokens, metadados), duas
-- funções que devolvem só id, e-mail e último acesso. Mesmo padrão de
-- privado.confirmar_email_do_usuario (20261101120000): security definer, search_path vazio,
-- EXECUTE só para o service_role.
--
-- Rollback: supabase/rollback/contas_auth_para_backend_rollback.sql
-- ===========================================================================

create or replace function privado.contas_auth(ids uuid[])
returns table (id uuid, email text, ultimo_acesso timestamptz)
language sql stable security definer set search_path = ''
as $$
  select u.id, u.email::text, u.last_sign_in_at
    from auth.users u
   where u.id = any(ids);
$$;

create or replace function privado.conta_auth_por_email(email_busca text)
returns table (id uuid, email text)
language sql stable security definer set search_path = ''
as $$
  select u.id, u.email::text
    from auth.users u
   where lower(u.email) = lower(trim(email_busca))
   limit 1;
$$;

revoke all on function
  privado.contas_auth(uuid[]),
  privado.conta_auth_por_email(text)
from public, anon, authenticated;

grant execute on function
  privado.contas_auth(uuid[]),
  privado.conta_auth_por_email(text)
to service_role;
