-- Conta do usuário: endereços salvos, profissionais favoritos e contatos de confiança.
--
-- STATUS: APLICADA no Supabase em 05/11/2026 com o OK do João.
-- Só DDL. Depende de public.usuarios e public.perfis_profissional (F3.2).
-- Reversão: supabase/rollback/conta_enderecos_favoritos_contatos_rollback.sql
--
-- Toda escrita é do backend (service_role); o dono só lê os próprios registros.

create table public.enderecos_salvos (
  id          uuid primary key default gen_random_uuid(),
  usuario_id  uuid not null references public.usuarios (id) on delete cascade,
  apelido     text not null check (btrim(apelido) <> '' and char_length(apelido) <= 30),
  cep         text not null check (cep ~ '^[0-9]{8}$'),
  logradouro  text not null check (char_length(logradouro) between 2 and 120),
  numero      text not null check (char_length(numero) between 1 and 12),
  complemento text check (complemento is null or char_length(complemento) <= 60),
  bairro      text not null check (char_length(bairro) between 2 and 80),
  cidade      text not null check (char_length(cidade) between 2 and 80),
  uf          text not null check (uf ~ '^[A-Z]{2}$'),
  principal   boolean not null default false,
  criado_em   timestamptz not null default now()
);
create index enderecos_salvos_usuario_idx on public.enderecos_salvos (usuario_id, criado_em);
-- No máximo um endereço principal por pessoa.
create unique index enderecos_salvos_um_principal_idx
  on public.enderecos_salvos (usuario_id) where principal;
alter table public.enderecos_salvos enable row level security;

create table public.profissionais_favoritos (
  usuario_id      uuid not null references public.usuarios (id) on delete cascade,
  profissional_id uuid not null references public.perfis_profissional (usuario_id) on delete cascade,
  criado_em       timestamptz not null default now(),
  primary key (usuario_id, profissional_id),
  check (usuario_id <> profissional_id)
);
create index profissionais_favoritos_pro_idx on public.profissionais_favoritos (profissional_id);
alter table public.profissionais_favoritos enable row level security;

create table public.contatos_confianca (
  id         uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios (id) on delete cascade,
  nome       text not null check (char_length(nome) between 2 and 80),
  telefone   text not null check (telefone ~ '^[0-9]{10,11}$'),
  parentesco text check (parentesco is null or char_length(parentesco) <= 40),
  criado_em  timestamptz not null default now()
);
create index contatos_confianca_usuario_idx on public.contatos_confianca (usuario_id, criado_em);
alter table public.contatos_confianca enable row level security;

create policy enderecos_salvos_ler_proprio on public.enderecos_salvos
  for select to authenticated using (usuario_id = (select auth.uid()));
create policy profissionais_favoritos_ler_proprio on public.profissionais_favoritos
  for select to authenticated using (usuario_id = (select auth.uid()));
create policy contatos_confianca_ler_proprio on public.contatos_confianca
  for select to authenticated using (usuario_id = (select auth.uid()));

revoke all on table public.enderecos_salvos, public.profissionais_favoritos,
  public.contatos_confianca from public, anon, authenticated, service_role;
grant select on table public.enderecos_salvos, public.profissionais_favoritos,
  public.contatos_confianca to authenticated;
grant select, insert, update, delete on table public.enderecos_salvos,
  public.profissionais_favoritos, public.contatos_confianca to service_role;

-- Dados pessoais: telefone e data_nascimento já são de usuarios_privados (service_role já atualiza).
