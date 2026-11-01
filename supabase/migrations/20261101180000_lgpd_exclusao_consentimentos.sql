-- LGPD: pedidos de exclusão, histórico de consentimentos e a anonimização da conta.
--
-- Nenhuma tabela de dinheiro, auditoria, mensagens ou contratos é tocada (imutáveis, retenção
-- legal). As chaves para `usuarios` são `on delete restrict`: por isso a conta é ANONIMIZADA, não
-- apagada. A função roda como dono (security definer) e só o `service_role` executa.

create table if not exists public.lgpd_pedidos_exclusao (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references public.usuarios (id) on delete restrict,
  status          text not null check (status in
                    ('aguardando_confirmacao', 'agendada', 'concluida', 'cancelada', 'expirada')),
  criado_em       timestamptz not null default now(),
  token_hash      text,
  token_expira_em timestamptz,
  executar_apos   timestamptz,
  concluido_em    timestamptz,
  resumo          jsonb
);

-- No máximo um pedido ativo por pessoa.
create unique index if not exists lgpd_pedidos_exclusao_ativo_idx
  on public.lgpd_pedidos_exclusao (usuario_id)
  where status in ('aguardando_confirmacao', 'agendada');

create table if not exists public.lgpd_consentimentos (
  id            bigint generated always as identity primary key,
  usuario_id    uuid not null references public.usuarios (id) on delete restrict,
  finalidade    text not null,
  aceito        boolean not null,
  versao_texto  text not null,
  registrado_em timestamptz not null default now(),
  ip            text
);

create index if not exists lgpd_consentimentos_usuario_idx
  on public.lgpd_consentimentos (usuario_id, registrado_em);

alter table public.lgpd_pedidos_exclusao enable row level security;
alter table public.lgpd_consentimentos enable row level security;

revoke all on public.lgpd_pedidos_exclusao from public, anon, authenticated;
revoke all on public.lgpd_consentimentos from public, anon, authenticated;
grant select, insert, update on public.lgpd_pedidos_exclusao to service_role;
grant select, insert on public.lgpd_consentimentos to service_role;

create schema if not exists privado;

create or replace function privado.anonimizar_usuario(p_usuario uuid)
returns text[]
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_caminhos text[];
begin
  -- Fotos de documento e selfie: o app apaga os arquivos do Storage com estes caminhos.
  select coalesce(array_agg(d.storage_path), '{}'::text[]) into v_caminhos
    from public.verificacao_documentos d
    join public.verificacoes v on v.id = d.verificacao_id
   where v.profissional_id = p_usuario;

  delete from public.verificacao_documentos d
   using public.verificacoes v
   where v.id = d.verificacao_id and v.profissional_id = p_usuario;

  -- CPF é obrigatório e único: vira um valor que não é CPF (e libera o CPF real para novo cadastro).
  update public.usuarios_privados
     set cpf = 'anon' || replace(p_usuario::text, '-', ''),
         telefone = null,
         telefone_confirmado_em = null,
         email_confirmado_em = null,
         data_nascimento = null,
         atualizado_em = now()
   where usuario_id = p_usuario;

  update public.usuarios
     set nome = 'Usuário anonimizado',
         foto_path = null,
         status = 'anonimizado',
         atualizado_em = now()
   where id = p_usuario;

  delete from public.dispositivos_push where usuario_id = p_usuario;
  delete from public.notificacao_preferencias where usuario_id = p_usuario;

  -- Some das buscas e do catálogo.
  delete from public.profissional_categorias where profissional_id = p_usuario;
  delete from public.profissional_regioes where profissional_id = p_usuario;
  update public.perfis_profissional
     set bio = null,
         portfolio = '[]'::jsonb,
         disponibilidade = '[]'::jsonb,
         atualizado_em = now()
   where usuario_id = p_usuario;

  return v_caminhos;
end;
$$;

revoke all on function privado.anonimizar_usuario(uuid) from public, anon, authenticated;
grant execute on function privado.anonimizar_usuario(uuid) to service_role;

