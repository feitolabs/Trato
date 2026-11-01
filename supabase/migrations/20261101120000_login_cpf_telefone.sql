-- Funções internas (service_role) para resolução de login por CPF ou telefone
-- e vínculo imediato de CPF/telefone no momento do cadastro.

create or replace function privado.email_por_cpf(cpf_busca text)
returns text
language sql stable security definer set search_path = ''
as $$
  select u.email
    from public.usuarios_privados p
    join auth.users u on u.id = p.usuario_id
   where p.cpf = cpf_busca
   limit 1;
$$;

create or replace function privado.email_por_telefone(tel_busca text)
returns text
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (
      select u.email
        from public.usuarios_privados p
        join auth.users u on u.id = p.usuario_id
       where p.telefone is not null
         and regexp_replace(p.telefone, '\D', '', 'g') in (tel_busca, '55' || tel_busca)
       limit 1
    ),
    (
      select u.email
        from auth.users u
       where regexp_replace(coalesce(u.raw_user_meta_data->>'celular', ''), '\D', '', 'g')
             in (tel_busca, '55' || tel_busca)
       limit 1
    )
  );
$$;

create or replace function privado.confirmar_email_do_usuario(uid uuid, email_esperado text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
      from auth.users u
     where u.id = uid
       and lower(u.email) = lower(email_esperado)
  );
$$;

revoke all on function
  privado.email_por_cpf(text),
  privado.email_por_telefone(text),
  privado.confirmar_email_do_usuario(uuid, text)
from public, anon, authenticated;

grant execute on function
  privado.email_por_cpf(text),
  privado.email_por_telefone(text),
  privado.confirmar_email_do_usuario(uuid, text)
to service_role;
