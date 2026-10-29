-- F3.3 — Pedido, endereço, respostas, histórico, mídias, orçamento e contrato.
-- Fonte: docs/modelo-de-dados.md, seção 5 (aprovado pelo João em 28/10/2026).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Só DDL: nenhum INSERT de dados. RLS ligado em toda tabela nova, sem policy
-- (as policies entram na F3.8). Acesso de anon/authenticated revogado na criação:
-- a F3.8 concede só SELECT (e só nas colunas permitidas). Escrita: só o backend (N11).
-- Reversão: supabase/rollback/F3.3_rollback.sql

-- ---------------------------------------------------------------------------
-- Funções genéricas de proteção (usadas por várias migrations)
-- ---------------------------------------------------------------------------

-- Registro imutável: qualquer UPDATE, DELETE ou TRUNCATE falha, para qualquer papel.
create or replace function public.bloquear_alteracao()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Registro imutável: % não é permitido em %.%',
    tg_op, tg_table_schema, tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

-- Colunas congeladas: o trigger recebe os nomes das colunas nos argumentos.
create or replace function public.proteger_colunas()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  coluna text;
begin
  foreach coluna in array tg_argv loop
    if (to_jsonb(new) -> coluna) is distinct from (to_jsonb(old) -> coluna) then
      raise exception 'A coluna %.% não pode ser alterada', tg_table_name, coluna
        using errcode = 'restrict_violation';
    end if;
  end loop;
  return new;
end;
$$;

revoke execute on function public.bloquear_alteracao() from public, anon, authenticated;
revoke execute on function public.proteger_colunas() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5.1 pedidos
-- ---------------------------------------------------------------------------
create table public.pedidos (
  id                       uuid primary key default gen_random_uuid(),
  cliente_id               uuid not null references public.usuarios (id) on delete restrict,
  categoria_id             uuid not null references public.categorias (id) on delete restrict,
  cidade_id                uuid not null references public.cidades (id) on delete restrict,
  bairro                   text,
  -- Coordenadas arredondadas (~500 m). O endereço exato fica em pedidos_endereco.
  local_aprox_lat          double precision check (local_aprox_lat is null or local_aprox_lat between -90 and 90),
  local_aprox_lng          double precision check (local_aprox_lng is null or local_aprox_lng between -180 and 180),
  titulo                   text not null check (btrim(titulo) <> ''),
  descricao                text not null check (btrim(descricao) <> ''),
  prazo_desejado           date,
  faixa_preco_min_centavos bigint check (faixa_preco_min_centavos is null or faixa_preco_min_centavos >= 0),
  faixa_preco_max_centavos bigint check (faixa_preco_max_centavos is null or faixa_preco_max_centavos >= 0),
  urgente                  boolean not null default false,
  status                   text not null default 'aberto'
                             check (status in ('aberto', 'orcamento_aceito', 'pago_retido', 'agendado',
                                               'em_andamento', 'em_confirmacao', 'concluido',
                                               'cancelado', 'em_disputa', 'retrabalho')),
  orcamentos_ate           timestamptz,
  expira_em                timestamptz,
  criado_em                timestamptz not null default now(),
  atualizado_em            timestamptz not null default now(),
  check (faixa_preco_min_centavos is null or faixa_preco_max_centavos is null
         or faixa_preco_min_centavos <= faixa_preco_max_centavos)
);
create index pedidos_cliente_idx on public.pedidos (cliente_id, criado_em desc);
create index pedidos_abertos_idx on public.pedidos (categoria_id, cidade_id, criado_em desc)
  where status = 'aberto';
create index pedidos_status_idx on public.pedidos (status);
create trigger pedidos_atualizado_em before update on public.pedidos
  for each row execute function public.definir_atualizado_em();
create trigger pedidos_proteger before update on public.pedidos
  for each row execute function public.proteger_colunas('cliente_id', 'categoria_id', 'cidade_id', 'criado_em');
alter table public.pedidos enable row level security;

-- ---------------------------------------------------------------------------
-- 5.2 pedidos_endereco — endereço completo, liberado só após a contratação
-- ---------------------------------------------------------------------------
create table public.pedidos_endereco (
  pedido_id   uuid primary key references public.pedidos (id) on delete restrict,
  cep         text,
  logradouro  text not null,
  numero      text,
  complemento text,
  bairro      text,
  referencia  text,
  lat         double precision check (lat is null or lat between -90 and 90),
  lng         double precision check (lng is null or lng between -180 and 180),
  -- N12: preenchido pelo backend quando o contrato é aceito/pago.
  liberado_em timestamptz
);
alter table public.pedidos_endereco enable row level security;

-- ---------------------------------------------------------------------------
-- 5.3 pedido_respostas — perguntas guiadas (texto da pergunta copiado)
-- ---------------------------------------------------------------------------
create table public.pedido_respostas (
  pedido_id      uuid not null references public.pedidos (id) on delete restrict,
  pergunta_id    uuid not null references public.categoria_perguntas (id) on delete restrict,
  pergunta_texto text not null,
  resposta       jsonb not null,
  primary key (pedido_id, pergunta_id)
);
alter table public.pedido_respostas enable row level security;

-- ---------------------------------------------------------------------------
-- 5.4 pedido_historico — toda transição de estado (append-only)
-- ---------------------------------------------------------------------------
create table public.pedido_historico (
  id          bigint generated always as identity primary key,
  pedido_id   uuid not null references public.pedidos (id) on delete restrict,
  de_status   text,
  para_status text not null,
  ator_id     uuid references public.usuarios (id) on delete restrict,  -- null = rotina automática
  motivo      text,
  prova       jsonb,
  ocorrida_em timestamptz not null default now()
);
create index pedido_historico_pedido_idx on public.pedido_historico (pedido_id, ocorrida_em);
create trigger pedido_historico_imutavel before update or delete on public.pedido_historico
  for each row execute function public.bloquear_alteracao();
create trigger pedido_historico_sem_truncate before truncate on public.pedido_historico
  for each statement execute function public.bloquear_alteracao();
alter table public.pedido_historico enable row level security;

-- ---------------------------------------------------------------------------
-- 5.5 midias — fotos e anexos de um pedido (imutável após o envio: é prova)
-- ---------------------------------------------------------------------------
create table public.midias (
  id             uuid primary key default gen_random_uuid(),
  pedido_id      uuid not null references public.pedidos (id) on delete restrict,
  enviada_por    uuid not null references public.usuarios (id) on delete restrict,
  finalidade     text not null
                   check (finalidade in ('pedido', 'antes', 'durante', 'depois', 'checkin', 'checkout',
                                         'nota_material', 'aditivo', 'disputa', 'retrabalho', 'chat')),
  -- Diferença do modelo aprovado: o bucket é explícito (a policy do Storage precisa dele).
  bucket         text not null default 'pedido-midias'
                   check (bucket in ('pedido-midias', 'chat-anexos')),
  storage_path   text not null check (btrim(storage_path) <> ''),  -- caminho dentro do bucket
  mime           text,
  tamanho_bytes  bigint check (tamanho_bytes is null or tamanho_bytes > 0),
  sha256         text,
  capturada_em   timestamptz,
  lat            double precision check (lat is null or lat between -90 and 90),
  lng            double precision check (lng is null or lng between -180 and 180),
  criado_em      timestamptz not null default now(),
  unique (bucket, storage_path),
  check ((finalidade = 'chat') = (bucket = 'chat-anexos'))
);
create index midias_pedido_finalidade_idx on public.midias (pedido_id, finalidade);
create index midias_sha256_idx on public.midias (sha256) where sha256 is not null;
create trigger midias_imutavel before update or delete on public.midias
  for each row execute function public.bloquear_alteracao();
create trigger midias_sem_truncate before truncate on public.midias
  for each statement execute function public.bloquear_alteracao();
alter table public.midias enable row level security;

-- ---------------------------------------------------------------------------
-- 5.6 orcamentos
-- ---------------------------------------------------------------------------
create table public.orcamentos (
  id                      uuid primary key default gen_random_uuid(),
  pedido_id               uuid not null references public.pedidos (id) on delete restrict,
  profissional_id         uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  versao                  integer not null default 1 check (versao >= 1),
  status                  text not null default 'rascunho'
                            check (status in ('rascunho', 'enviado', 'aceito', 'recusado', 'substituido',
                                              'expirado', 'retirado')),
  valor_total_centavos    bigint not null check (valor_total_centavos >= 0),
  prazo_execucao_dias     integer check (prazo_execucao_dias is null or prazo_execucao_dias > 0),
  validade_ate            timestamptz,
  garantia_dias           integer check (garantia_dias is null or garantia_dias >= 0),
  fora_do_escopo          text,
  sinal_material_centavos bigint check (sinal_material_centavos is null or sinal_material_centavos >= 0),  -- P4
  observacoes             text,
  criado_em               timestamptz not null default now(),
  atualizado_em           timestamptz not null default now(),
  enviado_em              timestamptz,
  unique (pedido_id, profissional_id, versao),
  check (status = 'rascunho' or enviado_em is not null)
);
create index orcamentos_pedido_status_idx on public.orcamentos (pedido_id, status);
create index orcamentos_profissional_status_idx on public.orcamentos (profissional_id, status);
-- Só um orçamento aceito por pedido.
create unique index orcamentos_um_aceito_idx on public.orcamentos (pedido_id) where status = 'aceito';
create trigger orcamentos_atualizado_em before update on public.orcamentos
  for each row execute function public.definir_atualizado_em();
create trigger orcamentos_proteger before update on public.orcamentos
  for each row execute function public.proteger_colunas('pedido_id', 'profissional_id', 'versao', 'criado_em');
alter table public.orcamentos enable row level security;

-- ---------------------------------------------------------------------------
-- 5.7 orcamento_itens
-- ---------------------------------------------------------------------------
create table public.orcamento_itens (
  id                      uuid primary key default gen_random_uuid(),
  orcamento_id            uuid not null references public.orcamentos (id) on delete restrict,
  tipo                    text not null check (tipo in ('deslocamento', 'horas', 'material', 'outro')),
  descricao               text not null,
  quantidade              numeric(10, 2) not null check (quantidade > 0),
  valor_unitario_centavos bigint not null check (valor_unitario_centavos >= 0),
  total_centavos          bigint not null check (total_centavos >= 0),  -- arredondamento: backend
  ordem                   integer not null default 0
);
create index orcamento_itens_orcamento_idx on public.orcamento_itens (orcamento_id, ordem);
alter table public.orcamento_itens enable row level security;

-- Regras do orçamento: quem pode orçar e congelamento depois de enviado.
create or replace function public.orcamentos_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  cliente uuid;
  perfil public.perfis_profissional%rowtype;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'rascunho' then
      raise exception 'Orçamento já enviado não pode ser apagado' using errcode = 'restrict_violation';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.status <> 'rascunho' then
    if (new.valor_total_centavos, new.prazo_execucao_dias, new.validade_ate, new.garantia_dias,
        new.fora_do_escopo, new.sinal_material_centavos, new.observacoes, new.enviado_em)
       is distinct from
       (old.valor_total_centavos, old.prazo_execucao_dias, old.validade_ate, old.garantia_dias,
        old.fora_do_escopo, old.sinal_material_centavos, old.observacoes, old.enviado_em) then
      raise exception 'Orçamento já enviado: só o status pode mudar (crie uma nova versão)'
        using errcode = 'restrict_violation';
    end if;
  end if;

  select cliente_id into cliente from public.pedidos where id = new.pedido_id;
  if cliente = new.profissional_id then
    raise exception 'O profissional não pode orçar o próprio pedido' using errcode = 'check_violation';
  end if;

  if new.status <> 'rascunho' and (tg_op = 'INSERT' or old.status = 'rascunho') then
    select * into perfil from public.perfis_profissional where usuario_id = new.profissional_id;
    if perfil.status is distinct from 'aprovado'
       or perfil.nivel_verificacao not in ('verificado', 'verificado_plus') then
      raise exception 'Só profissional aprovado e verificado envia orçamento' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
create trigger orcamentos_validar_trg before insert or update or delete on public.orcamentos
  for each row execute function public.orcamentos_validar();

-- Itens só mudam enquanto o orçamento é rascunho.
create or replace function public.orcamento_itens_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  status_orc text;
begin
  select status into status_orc from public.orcamentos
    where id = case when tg_op = 'DELETE' then old.orcamento_id else new.orcamento_id end;
  if status_orc is distinct from 'rascunho' then
    raise exception 'Itens só mudam enquanto o orçamento é rascunho' using errcode = 'restrict_violation';
  end if;
  if tg_op = 'UPDATE' and new.orcamento_id is distinct from old.orcamento_id then
    raise exception 'O item não pode trocar de orçamento' using errcode = 'restrict_violation';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
create trigger orcamento_itens_validar_trg before insert or update or delete on public.orcamento_itens
  for each row execute function public.orcamento_itens_validar();

-- Total do orçamento = soma dos itens, conferido no fim da transação.
create or replace function public.orcamento_conferir_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  orc uuid;
  total bigint;
  esperado bigint;
begin
  if tg_table_name = 'orcamentos' then
    orc := case when tg_op = 'DELETE' then old.id else new.id end;
  else
    orc := case when tg_op = 'DELETE' then old.orcamento_id else new.orcamento_id end;
  end if;
  select valor_total_centavos into esperado from public.orcamentos where id = orc;
  if not found then
    return null;  -- orçamento (rascunho) apagado na mesma transação
  end if;
  select coalesce(sum(total_centavos), 0) into total from public.orcamento_itens where orcamento_id = orc;
  if total <> esperado then
    raise exception 'Orçamento %: valor_total (%) difere da soma dos itens (%)', orc, esperado, total
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;
revoke execute on function public.orcamento_conferir_total() from public, anon, authenticated;
create constraint trigger orcamentos_total_conferir after insert or update on public.orcamentos
  deferrable initially deferred for each row execute function public.orcamento_conferir_total();
create constraint trigger orcamento_itens_total_conferir after insert or update or delete on public.orcamento_itens
  deferrable initially deferred for each row execute function public.orcamento_conferir_total();

-- ---------------------------------------------------------------------------
-- 5.8 contratos — gerado no aceite; escopo e regras congelados
-- ---------------------------------------------------------------------------
create table public.contratos (
  id                             uuid primary key default gen_random_uuid(),
  pedido_id                      uuid not null unique references public.pedidos (id) on delete restrict,
  orcamento_id                   uuid not null unique references public.orcamentos (id) on delete restrict,
  cliente_id                     uuid not null references public.usuarios (id) on delete restrict,
  profissional_id                uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  status                         text not null default 'aguardando_pagamento'
                                   check (status in ('aguardando_pagamento', 'ativo', 'concluido',
                                                     'cancelado', 'em_disputa')),
  escopo_texto                   text not null,
  fora_do_escopo                 text,
  itens                          jsonb not null default '[]'::jsonb check (jsonb_typeof(itens) = 'array'),
  prazo_execucao_dias            integer check (prazo_execucao_dias is null or prazo_execucao_dias > 0),
  garantia_dias                  integer check (garantia_dias is null or garantia_dias >= 0),
  valor_total_centavos           bigint not null check (valor_total_centavos >= 0),
  taxa_bps_aplicada              integer not null check (taxa_bps_aplicada between 0 and 10000),
  taxa_trato_centavos            bigint not null check (taxa_trato_centavos >= 0),
  liquido_profissional_centavos  bigint not null check (liquido_profissional_centavos >= 0),  -- P3
  adiantamento_centavos          bigint not null check (adiantamento_centavos >= 0),
  custo_stripe_estimado_centavos bigint check (custo_stripe_estimado_centavos is null
                                               or custo_stripe_estimado_centavos >= 0),
  -- Regras congeladas no aceite (seção 4.5): nunca recalcular a partir da configuração atual.
  config_versao_id               uuid not null references public.config_versoes (id) on delete restrict,
  regras_aplicadas               jsonb not null check (jsonb_typeof(regras_aplicadas) = 'object'),
  hash_documento                 text not null,
  aceito_em                      timestamptz not null,
  aceite_ip                      text,
  aceite_dispositivo             text,
  criado_em                      timestamptz not null default now(),
  check (cliente_id <> profissional_id),
  check (taxa_trato_centavos <= valor_total_centavos),
  check (liquido_profissional_centavos <= valor_total_centavos),
  check (adiantamento_centavos <= valor_total_centavos)
);
create index contratos_cliente_idx on public.contratos (cliente_id);
create index contratos_profissional_status_idx on public.contratos (profissional_id, status);
create index contratos_config_versao_idx on public.contratos (config_versao_id);

-- Só o status muda. Valores, escopo e regras são congelados.
create trigger contratos_proteger before update on public.contratos
  for each row execute function public.proteger_colunas(
    'id', 'pedido_id', 'orcamento_id', 'cliente_id', 'profissional_id', 'escopo_texto', 'fora_do_escopo',
    'itens', 'prazo_execucao_dias', 'garantia_dias', 'valor_total_centavos', 'taxa_bps_aplicada',
    'taxa_trato_centavos', 'liquido_profissional_centavos', 'adiantamento_centavos',
    'custo_stripe_estimado_centavos', 'config_versao_id', 'regras_aplicadas', 'hash_documento',
    'aceito_em', 'aceite_ip', 'aceite_dispositivo', 'criado_em');
create trigger contratos_sem_delete before delete on public.contratos
  for each row execute function public.bloquear_alteracao();
create trigger contratos_sem_truncate before truncate on public.contratos
  for each statement execute function public.bloquear_alteracao();
alter table public.contratos enable row level security;

-- O contrato precisa bater com o pedido e com o orçamento aceito.
create or replace function public.contratos_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ped public.pedidos%rowtype;
  orc public.orcamentos%rowtype;
begin
  select * into ped from public.pedidos where id = new.pedido_id;
  select * into orc from public.orcamentos where id = new.orcamento_id;
  if ped.cliente_id is distinct from new.cliente_id then
    raise exception 'O cliente do contrato não é o cliente do pedido' using errcode = 'check_violation';
  end if;
  if orc.pedido_id is distinct from new.pedido_id or orc.profissional_id is distinct from new.profissional_id then
    raise exception 'O orçamento não pertence a este pedido e profissional' using errcode = 'check_violation';
  end if;
  if orc.status <> 'aceito' then
    raise exception 'O contrato só nasce de um orçamento aceito' using errcode = 'check_violation';
  end if;
  if orc.valor_total_centavos is distinct from new.valor_total_centavos then
    raise exception 'O valor do contrato deve ser o valor do orçamento aceito' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger contratos_validar_trg before insert on public.contratos
  for each row execute function public.contratos_validar();

-- ---------------------------------------------------------------------------
-- Acesso. Privilégios EXPLÍCITOS, iguais em qualquer padrão da plataforma:
--  * anon e authenticated: nada (a F3.8b concede só SELECT, por coluna);
--  * service_role (backend): só o que a tabela precisa. Nunca TRUNCATE.
--    Tabela imutável recebe apenas SELECT e INSERT.
-- ---------------------------------------------------------------------------
revoke all on table public.pedidos, public.pedidos_endereco, public.pedido_respostas,
  public.pedido_historico, public.midias, public.orcamentos, public.orcamento_itens, public.contratos
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.pedidos, public.pedidos_endereco, public.pedido_respostas,
  public.contratos to service_role;
grant select, insert, update, delete on table public.orcamentos, public.orcamento_itens to service_role;
grant select, insert on table public.pedido_historico, public.midias to service_role;
revoke execute on function public.orcamentos_validar(), public.orcamento_itens_validar(),
  public.contratos_validar() from public, anon, authenticated;
