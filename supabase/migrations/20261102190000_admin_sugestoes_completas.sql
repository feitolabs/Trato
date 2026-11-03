-- ===========================================================================
-- 20261102190000_admin_sugestoes_completas.sql
-- Tabelas para os novos módulos administrativos:
-- 1. cupons (Gestão de Cupons de Desconto & Campanhas)
-- 2. campanhas_notificacao (Disparo de Mensagens & Push em Massa)
-- 3. alertas_risco (Central Antifraude & Gestão de Risco)
-- ===========================================================================

-- 1. cupons
create table if not exists public.cupons (
  id                    uuid primary key default gen_random_uuid(),
  codigo                text not null unique check (btrim(codigo) <> ''),
  tipo                  text not null check (tipo in ('percentual', 'fixo')),
  valor                 bigint not null check (valor > 0),
  valor_minimo_centavos bigint not null default 0 check (valor_minimo_centavos >= 0),
  limite_usos           integer check (limite_usos is null or limite_usos > 0),
  usos_atuais           integer not null default 0 check (usos_atuais >= 0),
  valido_ate            timestamptz,
  ativo                 boolean not null default true,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now()
);

create trigger cupons_atualizado_em before update on public.cupons
  for each row execute function public.definir_atualizado_em();

alter table public.cupons enable row level security;

-- 2. campanhas_notificacao
create table if not exists public.campanhas_notificacao (
  id                  uuid primary key default gen_random_uuid(),
  titulo              text not null check (btrim(titulo) <> ''),
  mensagem            text not null check (btrim(mensagem) <> ''),
  segmento            text not null check (segmento in ('todos', 'clientes', 'profissionais', 'categoria', 'cidade')),
  categoria_id        uuid references public.categorias (id) on delete set null,
  cidade_id           uuid references public.cidades (id) on delete set null,
  total_destinatarios integer not null default 0,
  criado_por          uuid references public.equipe (usuario_id) on delete set null,
  criado_em           timestamptz not null default now()
);

alter table public.campanhas_notificacao enable row level security;

-- 3. alertas_risco
create table if not exists public.alertas_risco (
  id             uuid primary key default gen_random_uuid(),
  usuario_id     uuid references public.usuarios (id) on delete cascade,
  tipo           text not null,
  severidade     text not null check (severidade in ('baixa', 'media', 'alta', 'critica')),
  detalhes       text not null,
  resolvido      boolean not null default false,
  resolvido_por  uuid references public.equipe (usuario_id) on delete set null,
  resolvido_em   timestamptz,
  criado_em      timestamptz not null default now()
);

alter table public.alertas_risco enable row level security;

