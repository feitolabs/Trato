-- F3.2 — Identidade, profissional, verificação, catálogo e configuração versionada.
-- Fonte: docs/modelo-de-dados.md, seções 1, 3 e 4 (aprovado pelo João em 28/10/2026).
--
-- APLICADA no Supabase "Trato" em 29/10/2026 (versão 20261029025430), com o OK explícito do João.
-- O nome do arquivo segue a versão registrada no Supabase. Não editar a estrutura: criar nova migration.
-- Só cria estrutura (DDL). Não insere nenhum dado: sem taxa, sem cidade, sem definições
-- de configuração (dependem de P2, P6 e dos limites mínimo/máximo que o João vai definir).
-- Todas as tabelas nascem com RLS ligado e SEM policy: ninguém lê pelo app até a F3.8.
-- Reversão: supabase/rollback/F3.2_rollback.sql

-- Necessária para o EXCLUDE de faixas da taxa (igualdade de uuid/text dentro de índice gist).
create extension if not exists btree_gist with schema extensions;

-- ---------------------------------------------------------------------------
-- Função comum: mantém atualizado_em
-- ---------------------------------------------------------------------------
create or replace function public.definir_atualizado_em()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3.1 usuarios — perfil público básico (1 linha por conta)
-- ---------------------------------------------------------------------------
create table public.usuarios (
  id                   uuid primary key references auth.users (id) on delete restrict,
  nome                 text not null,
  foto_path            text,
  status               text not null default 'ativo'
                         check (status in ('ativo', 'restrito', 'bloqueado', 'anonimizado')),
  aceite_termos_versao text,
  aceite_termos_em     timestamptz,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);
create trigger usuarios_atualizado_em before update on public.usuarios
  for each row execute function public.definir_atualizado_em();
alter table public.usuarios enable row level security;

-- ---------------------------------------------------------------------------
-- 3.2 usuarios_privados — dados pessoais (só o dono e a equipe autorizada)
-- ---------------------------------------------------------------------------
create table public.usuarios_privados (
  usuario_id             uuid primary key references public.usuarios (id) on delete restrict,
  cpf                    text not null unique,
  telefone               text unique,
  telefone_confirmado_em timestamptz,
  email_confirmado_em    timestamptz,
  data_nascimento        date,
  stripe_customer_id     text unique,
  stripe_account_id      text unique,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now()
);
create trigger usuarios_privados_atualizado_em before update on public.usuarios_privados
  for each row execute function public.definir_atualizado_em();
alter table public.usuarios_privados enable row level security;

-- ---------------------------------------------------------------------------
-- 3.3 equipe — papéis da equipe (N1: um papel por usuário; mudar a PK se for mais de um)
-- ---------------------------------------------------------------------------
create table public.equipe (
  usuario_id      uuid primary key references public.usuarios (id) on delete restrict,
  papel           text not null
                    check (papel in ('atendente_n1', 'atendente_n2', 'mediador', 'financeiro',
                                     'seguranca', 'cadastro', 'moderador', 'juridico', 'dpo',
                                     'lider_suporte', 'administrador')),
  ativo           boolean not null default true,
  alcada_centavos bigint check (alcada_centavos is null or alcada_centavos >= 0),
  criado_em       timestamptz not null default now(),
  revogado_em     timestamptz
);
alter table public.equipe enable row level security;

-- ---------------------------------------------------------------------------
-- 3.4 cidades
-- ---------------------------------------------------------------------------
create table public.cidades (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null,
  uf            text not null check (char_length(uf) = 2),
  ativa         boolean not null default false,
  centro_lat    double precision check (centro_lat is null or centro_lat between -90 and 90),
  centro_lng    double precision check (centro_lng is null or centro_lng between -180 and 180),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (nome, uf)
);
create trigger cidades_atualizado_em before update on public.cidades
  for each row execute function public.definir_atualizado_em();
alter table public.cidades enable row level security;

-- ---------------------------------------------------------------------------
-- 3.9 categorias e categoria_perguntas (criadas antes de profissional_categorias)
-- ---------------------------------------------------------------------------
create table public.categorias (
  id                       uuid primary key default gen_random_uuid(),
  pai_id                   uuid references public.categorias (id) on delete restrict,
  nome                     text not null,
  slug                     text not null unique,
  icone                    text,
  ordem                    integer not null default 0,
  ativa                    boolean not null default true,
  -- null = usa o padrão da configuração (garantia_retrabalho_dias_padrao)
  garantia_retrabalho_dias integer check (garantia_retrabalho_dias is null or garantia_retrabalho_dias > 0),
  criado_em                timestamptz not null default now(),
  atualizado_em            timestamptz not null default now(),
  check (pai_id is distinct from id)
);
create index categorias_pai_ordem_idx on public.categorias (pai_id, ordem);
create trigger categorias_atualizado_em before update on public.categorias
  for each row execute function public.definir_atualizado_em();
alter table public.categorias enable row level security;

-- Pergunta nunca é apagada, só ativa = false (o pedido guarda o texto da pergunta).
create table public.categoria_perguntas (
  id            uuid primary key default gen_random_uuid(),
  categoria_id  uuid not null references public.categorias (id) on delete restrict,
  texto         text not null,
  tipo          text not null
                  check (tipo in ('texto', 'numero', 'escolha_unica', 'multipla', 'sim_nao')),
  opcoes        jsonb,
  obrigatoria   boolean not null default false,
  ordem         integer not null default 0,
  ativa         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index categoria_perguntas_categoria_ordem_idx
  on public.categoria_perguntas (categoria_id, ordem);
create trigger categoria_perguntas_atualizado_em before update on public.categoria_perguntas
  for each row execute function public.definir_atualizado_em();
alter table public.categoria_perguntas enable row level security;

-- ---------------------------------------------------------------------------
-- 3.5 perfis_profissional (existir a linha = a conta atua como profissional, N1)
-- ---------------------------------------------------------------------------
create table public.perfis_profissional (
  usuario_id          uuid primary key references public.usuarios (id) on delete restrict,
  status              text not null default 'em_analise'
                        check (status in ('em_analise', 'aprovado', 'recusado', 'suspenso')),
  nivel_verificacao   text not null default 'basico'
                        check (nivel_verificacao in ('basico', 'verificado', 'verificado_plus')),
  bio                 text,
  cnpj                text,
  servicos_concluidos integer not null default 0 check (servicos_concluidos >= 0),
  nota_publica        numeric(3, 2) check (nota_publica is null or nota_publica between 0 and 5),
  reverificar_em      timestamptz,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now()
);
create index perfis_profissional_status_nivel_idx
  on public.perfis_profissional (status, nivel_verificacao);
create trigger perfis_profissional_atualizado_em before update on public.perfis_profissional
  for each row execute function public.definir_atualizado_em();
alter table public.perfis_profissional enable row level security;

-- ---------------------------------------------------------------------------
-- 3.6 profissional_categorias e profissional_regioes
-- ---------------------------------------------------------------------------
create table public.profissional_categorias (
  profissional_id uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  categoria_id    uuid not null references public.categorias (id) on delete restrict,
  suspensa_em     timestamptz,  -- credencial vencida suspende a categoria
  criado_em       timestamptz not null default now(),
  primary key (profissional_id, categoria_id)
);
create index profissional_categorias_categoria_idx on public.profissional_categorias (categoria_id);
alter table public.profissional_categorias enable row level security;

-- N8: granularidade da região em aberto; começa por cidade com bairro opcional.
-- PK não aceita expressão (coalesce), então a unicidade vai num índice.
create table public.profissional_regioes (
  id              uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  cidade_id       uuid not null references public.cidades (id) on delete restrict,
  bairro          text,
  criado_em       timestamptz not null default now()
);
create unique index profissional_regioes_unica_idx
  on public.profissional_regioes (profissional_id, cidade_id, (coalesce(bairro, '')));
create index profissional_regioes_cidade_idx on public.profissional_regioes (cidade_id);
alter table public.profissional_regioes enable row level security;

-- ---------------------------------------------------------------------------
-- 3.7 verificacoes
-- ---------------------------------------------------------------------------
create table public.verificacoes (
  id                    uuid primary key default gen_random_uuid(),
  profissional_id       uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  nivel_solicitado      text not null check (nivel_solicitado in ('verificado', 'verificado_plus')),
  status                text not null default 'enviada'
                          check (status in ('enviada', 'em_analise', 'aprovada', 'recusada')),
  analista_id           uuid references public.equipe (usuario_id) on delete restrict,
  motivo_recusa         text,
  fornecedor_ref        text,  -- P10: fornecedor de identidade ainda não escolhido
  consentimento_lgpd_em timestamptz not null,
  enviada_em            timestamptz not null default now(),
  decidida_em           timestamptz,
  check (status <> 'recusada' or motivo_recusa is not null)
);
create index verificacoes_profissional_idx on public.verificacoes (profissional_id, enviada_em desc);
create index verificacoes_status_idx on public.verificacoes (status);
alter table public.verificacoes enable row level security;

-- ---------------------------------------------------------------------------
-- 3.8 verificacao_documentos — acesso só da equipe de cadastro (policy na F3.8)
-- ---------------------------------------------------------------------------
create table public.verificacao_documentos (
  id             uuid primary key default gen_random_uuid(),
  verificacao_id uuid not null references public.verificacoes (id) on delete restrict,
  tipo           text not null
                   check (tipo in ('documento_frente', 'documento_verso', 'selfie', 'antecedentes',
                                   'comprovante_endereco', 'registro_profissional', 'curso_nr10',
                                   'seguro', 'outro')),
  storage_path   text not null,  -- bucket privado dedicado; nunca URL pública
  sha256         text,
  validade_em    date,
  excluir_em     timestamptz,    -- retenção limitada (LGPD); prazo em aberto (N10)
  criado_em      timestamptz not null default now()
);
create index verificacao_documentos_verificacao_idx on public.verificacao_documentos (verificacao_id);
create index verificacao_documentos_validade_idx
  on public.verificacao_documentos (validade_em) where validade_em is not null;
alter table public.verificacao_documentos enable row level security;

-- ---------------------------------------------------------------------------
-- 4.1 config_definicoes — catálogo do que pode ser configurado (sem seed nesta migration)
-- ---------------------------------------------------------------------------
create table public.config_definicoes (
  chave                text primary key,
  descricao            text not null,
  unidade              text not null
                         check (unidade in ('centavos', 'bps', 'horas', 'dias', 'dias_uteis', 'quantidade')),
  minimo               bigint,
  maximo               bigint,
  escopos_permitidos   text[] not null default array['global']
                         check (escopos_permitidos <@ array['global', 'cidade', 'categoria', 'nivel']),
  exige_dupla_aprovacao boolean not null default false,
  check (minimo is null or maximo is null or minimo <= maximo)
);
alter table public.config_definicoes enable row level security;

-- ---------------------------------------------------------------------------
-- 4.2 config_versoes
-- ---------------------------------------------------------------------------
create table public.config_versoes (
  id            uuid primary key default gen_random_uuid(),
  numero        integer generated always as identity unique,
  status        text not null default 'rascunho'
                  check (status in ('rascunho', 'aguardando_aprovacao', 'aprovada', 'vigente',
                                    'substituida', 'revertida')),
  vigente_desde timestamptz,
  criada_por    uuid not null references public.equipe (usuario_id) on delete restrict,
  aprovada_por  uuid references public.equipe (usuario_id) on delete restrict,
  motivo        text not null,
  revertida_de  uuid references public.config_versoes (id) on delete restrict,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (criada_por <> aprovada_por),
  check (status not in ('aprovada', 'vigente', 'substituida') or aprovada_por is not null)
);
-- Só uma versão vigente por vez.
create unique index config_versoes_uma_vigente_idx
  on public.config_versoes ((true)) where status = 'vigente';
create trigger config_versoes_atualizado_em before update on public.config_versoes
  for each row execute function public.definir_atualizado_em();
alter table public.config_versoes enable row level security;

-- Depois de aprovada, a versão fica imutável: só o status pode avançar
-- (aprovada -> vigente -> substituida) e nunca se apaga.
create or replace function public.config_versoes_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status not in ('rascunho', 'aguardando_aprovacao') then
      raise exception 'Versão de configuração % já aprovada não pode ser apagada', old.numero;
    end if;
    return old;
  end if;

  if old.status not in ('rascunho', 'aguardando_aprovacao') then
    if (new.id, new.numero, new.vigente_desde, new.criada_por, new.aprovada_por,
        new.motivo, new.revertida_de, new.criado_em)
       is distinct from
       (old.id, old.numero, old.vigente_desde, old.criada_por, old.aprovada_por,
        old.motivo, old.revertida_de, old.criado_em) then
      raise exception 'Versão de configuração % já aprovada: só o status pode mudar', old.numero;
    end if;
  end if;
  return new;
end;
$$;
create trigger config_versoes_proteger_trg before update or delete on public.config_versoes
  for each row execute function public.config_versoes_proteger();

-- ---------------------------------------------------------------------------
-- 4.3 config_parametros
-- ---------------------------------------------------------------------------
create table public.config_parametros (
  id           uuid primary key default gen_random_uuid(),
  versao_id    uuid not null references public.config_versoes (id) on delete restrict,
  chave        text not null references public.config_definicoes (chave) on delete restrict,
  valor        bigint not null,
  escopo_tipo  text not null default 'global'
                 check (escopo_tipo in ('global', 'cidade', 'categoria', 'nivel')),
  escopo_id    uuid,
  escopo_texto text,
  check (
    (escopo_tipo = 'global'    and escopo_id is null     and escopo_texto is null) or
    (escopo_tipo in ('cidade', 'categoria') and escopo_id is not null and escopo_texto is null) or
    (escopo_tipo = 'nivel'     and escopo_id is null     and escopo_texto is not null)
  )
);
create unique index config_parametros_unico_idx
  on public.config_parametros (
    versao_id, chave, escopo_tipo,
    (coalesce(escopo_id, '00000000-0000-0000-0000-000000000000'::uuid)),
    (coalesce(escopo_texto, ''))
  );
alter table public.config_parametros enable row level security;

-- ---------------------------------------------------------------------------
-- 4.4 config_faixas_taxa — taxa progressiva (D2). Quais faixas: P2 (tabela fica vazia).
-- ---------------------------------------------------------------------------
create table public.config_faixas_taxa (
  id           uuid primary key default gen_random_uuid(),
  versao_id    uuid not null references public.config_versoes (id) on delete restrict,
  de_centavos  bigint not null check (de_centavos >= 0),
  ate_centavos bigint,  -- exclusivo; null = sem teto
  taxa_bps     integer not null check (taxa_bps between 0 and 10000),
  escopo_tipo  text not null default 'global'
                 check (escopo_tipo in ('global', 'cidade', 'categoria', 'nivel')),
  escopo_id    uuid,
  escopo_texto text,
  check (ate_centavos is null or ate_centavos > de_centavos),
  check (
    (escopo_tipo = 'global'    and escopo_id is null     and escopo_texto is null) or
    (escopo_tipo in ('cidade', 'categoria') and escopo_id is not null and escopo_texto is null) or
    (escopo_tipo = 'nivel'     and escopo_id is null     and escopo_texto is not null)
  ),
  -- Faixas da mesma versão e escopo não podem se sobrepor.
  -- "Sem buraco" não dá para garantir com constraint: o backend valida ao publicar a versão.
  exclude using gist (
    versao_id with =,
    escopo_tipo with =,
    (coalesce(escopo_id, '00000000-0000-0000-0000-000000000000'::uuid)) with =,
    (coalesce(escopo_texto, '')) with =,
    int8range(de_centavos, ate_centavos) with &&
  )
);
alter table public.config_faixas_taxa enable row level security;

-- ---------------------------------------------------------------------------
-- Validação dos parâmetros e imutabilidade das linhas de versão já aprovada
-- ---------------------------------------------------------------------------
create or replace function public.config_parametros_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  def public.config_definicoes%rowtype;
  status_versao text;
begin
  if tg_op = 'DELETE' then
    select status into status_versao from public.config_versoes where id = old.versao_id;
  else
    select status into status_versao from public.config_versoes where id = new.versao_id;
  end if;
  if status_versao not in ('rascunho', 'aguardando_aprovacao') then
    raise exception 'Versão de configuração já aprovada: parâmetros não podem mudar';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  select * into def from public.config_definicoes where chave = new.chave;
  if def.minimo is not null and new.valor < def.minimo then
    raise exception 'Parâmetro %: valor % abaixo do mínimo %', new.chave, new.valor, def.minimo;
  end if;
  if def.maximo is not null and new.valor > def.maximo then
    raise exception 'Parâmetro %: valor % acima do máximo %', new.chave, new.valor, def.maximo;
  end if;
  if not (new.escopo_tipo = any (def.escopos_permitidos)) then
    raise exception 'Parâmetro %: escopo % não permitido', new.chave, new.escopo_tipo;
  end if;
  return new;
end;
$$;
create trigger config_parametros_validar_trg
  before insert or update or delete on public.config_parametros
  for each row execute function public.config_parametros_validar();

create or replace function public.config_faixas_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  status_versao text;
begin
  if tg_op = 'DELETE' then
    select status into status_versao from public.config_versoes where id = old.versao_id;
  else
    select status into status_versao from public.config_versoes where id = new.versao_id;
  end if;
  if status_versao not in ('rascunho', 'aguardando_aprovacao') then
    raise exception 'Versão de configuração já aprovada: faixas de taxa não podem mudar';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
create trigger config_faixas_proteger_trg
  before insert or update or delete on public.config_faixas_taxa
  for each row execute function public.config_faixas_proteger();
