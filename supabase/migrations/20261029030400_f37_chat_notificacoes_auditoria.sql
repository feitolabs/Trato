-- F3.7 — Conversas, mensagens (imutáveis), notificações e auditoria imutável com cadeia de hash.
-- Fonte: docs/modelo-de-dados.md, seções 8.5 a 8.7 (aprovado pelo João em 28/10/2026).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Só DDL. RLS ligado e sem policy (F3.8). anon/authenticated sem acesso até a F3.8.
-- Depende da F3.3. Reversão: supabase/rollback/F3.7_rollback.sql
--
-- Decisões provisórias usadas (o João confirma depois):
--   N9  — mensagens guarda `corpo` (original, evidência) e `corpo_exibido` (mascarado); `lida_em` é a
--         única coluna que muda, uma vez só (nulo -> data). O original NÃO é legível pelo app (F3.8).
--   N16 — auditoria com cadeia de hash (hash_anterior/hash), para provar que nada foi removido.

-- ---------------------------------------------------------------------------
-- 8.5 conversas — um chat por pedido e profissional
-- ---------------------------------------------------------------------------
create table public.conversas (
  id              uuid primary key default gen_random_uuid(),
  pedido_id       uuid not null references public.pedidos (id) on delete restrict,
  cliente_id      uuid not null references public.usuarios (id) on delete restrict,
  profissional_id uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  criada_em       timestamptz not null default now(),
  encerrada_em    timestamptz,
  unique (pedido_id, profissional_id),
  check (cliente_id <> profissional_id)
);
create index conversas_cliente_idx on public.conversas (cliente_id);
create index conversas_profissional_idx on public.conversas (profissional_id);
create trigger conversas_proteger before update on public.conversas
  for each row execute function public.proteger_colunas('pedido_id', 'cliente_id', 'profissional_id', 'criada_em');
create trigger conversas_sem_delete before delete on public.conversas
  for each row execute function public.bloquear_alteracao();
alter table public.conversas enable row level security;

create or replace function public.conversas_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ped_cliente uuid;
begin
  select cliente_id into ped_cliente from public.pedidos where id = new.pedido_id;
  if ped_cliente is distinct from new.cliente_id then
    raise exception 'O cliente da conversa não é o cliente do pedido' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger conversas_validar_trg before insert on public.conversas
  for each row execute function public.conversas_validar();

-- ---------------------------------------------------------------------------
-- mensagens — não editáveis nem removíveis (escopo 11.2)
-- ---------------------------------------------------------------------------
create table public.mensagens (
  id            bigint generated always as identity primary key,
  conversa_id   uuid not null references public.conversas (id) on delete restrict,
  autor_id      uuid not null references public.usuarios (id) on delete restrict,
  corpo         text not null check (btrim(corpo) <> ''),   -- original (evidência)
  corpo_exibido text not null,                              -- mascarado antes da contratação
  mascarada     boolean not null default false,
  midia_id      uuid references public.midias (id) on delete restrict,
  enviada_em    timestamptz not null default now(),
  lida_em       timestamptz
);
create index mensagens_conversa_idx on public.mensagens (conversa_id, id);

-- Única mudança permitida: marcar como lida, uma vez (nulo -> data). O resto é imutável.
create or replace function public.mensagens_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op <> 'UPDATE' then
    raise exception 'Mensagem não pode ser removida (% em %.%)', tg_op, tg_table_schema, tg_table_name
      using errcode = 'restrict_violation';
  end if;
  if old.lida_em is not null
     or new.lida_em is null
     or (new.id, new.conversa_id, new.autor_id, new.corpo, new.corpo_exibido, new.mascarada,
         new.midia_id, new.enviada_em)
        is distinct from
        (old.id, old.conversa_id, old.autor_id, old.corpo, old.corpo_exibido, old.mascarada,
         old.midia_id, old.enviada_em) then
    raise exception 'Mensagem não é editável: só lida_em pode ser preenchido, uma vez'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
create trigger mensagens_proteger_trg before update or delete on public.mensagens
  for each row execute function public.mensagens_proteger();
create trigger mensagens_sem_truncate before truncate on public.mensagens
  for each statement execute function public.bloquear_alteracao();
alter table public.mensagens enable row level security;

-- Autor precisa ser uma das duas partes da conversa; anexo precisa ser do mesmo pedido e do autor.
create or replace function public.mensagens_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  conv public.conversas%rowtype;
  m public.midias%rowtype;
begin
  select * into conv from public.conversas where id = new.conversa_id;
  if new.autor_id not in (conv.cliente_id, conv.profissional_id) then
    raise exception 'Só as partes da conversa escrevem nela' using errcode = 'check_violation';
  end if;
  if new.midia_id is not null then
    select * into m from public.midias where id = new.midia_id;
    if m.pedido_id is distinct from conv.pedido_id or m.finalidade <> 'chat' or m.enviada_por <> new.autor_id then
      raise exception 'O anexo deve ser uma mídia de chat deste pedido, enviada pelo autor'
        using errcode = 'check_violation';
    end if;
  end if;
  new.enviada_em := now();  -- hora do servidor
  new.lida_em := null;
  return new;
end;
$$;
create trigger mensagens_validar_trg before insert on public.mensagens
  for each row execute function public.mensagens_validar();

-- ---------------------------------------------------------------------------
-- 8.6 notificacoes e notificacao_preferencias
-- ---------------------------------------------------------------------------
create table public.notificacoes (
  id          uuid primary key default gen_random_uuid(),
  usuario_id  uuid not null references public.usuarios (id) on delete restrict,
  tipo        text not null check (btrim(tipo) <> ''),
  canal       text not null check (canal in ('push', 'sms', 'whatsapp', 'email', 'app')),  -- P11
  titulo      text not null,
  corpo       text,
  dados       jsonb not null default '{}'::jsonb,  -- deep link
  criada_em   timestamptz not null default now(),
  enviada_em  timestamptz,
  lida_em     timestamptz
);
create index notificacoes_usuario_idx on public.notificacoes (usuario_id, criada_em desc);
create index notificacoes_nao_lidas_idx on public.notificacoes (usuario_id) where lida_em is null;
create trigger notificacoes_proteger before update on public.notificacoes
  for each row execute function public.proteger_colunas('usuario_id', 'tipo', 'canal', 'titulo', 'corpo', 'dados', 'criada_em');
alter table public.notificacoes enable row level security;

-- Diferença mínima do modelo: a coluna se chama atualizado_em (como no resto do banco).
create table public.notificacao_preferencias (
  usuario_id    uuid primary key references public.usuarios (id) on delete restrict,
  preferencias  jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);
create trigger notificacao_preferencias_atualizado_em before update on public.notificacao_preferencias
  for each row execute function public.definir_atualizado_em();
alter table public.notificacao_preferencias enable row level security;

-- ---------------------------------------------------------------------------
-- 8.7 auditoria — imutável, escrita só por registrar_auditoria()
-- ---------------------------------------------------------------------------
create sequence public.auditoria_id_seq;

create table public.auditoria (
  id            bigint primary key,   -- preenchido pelo trigger, depois do lock da cadeia
  ocorrida_em   timestamptz not null,
  ator_id       uuid,                 -- sem FK de propósito: a trilha sobrevive a qualquer mudança de conta
  ator_tipo     text not null check (ator_tipo in ('cliente', 'profissional', 'equipe', 'sistema')),
  acao          text not null check (btrim(acao) <> ''),
  entidade      text,
  entidade_id   uuid,
  antes         jsonb,
  depois        jsonb,
  motivo        text,
  ip            text,
  dispositivo   text,
  request_id    text,
  hash_anterior text,
  hash          text not null,
  -- Motivo obrigatório em ação financeira, bloqueio e revelação de dado pessoal (escopo 18.5 e 22.4).
  -- A convenção de nomes (prefixo da ação) é PROVISÓRIA: confirmar com o João.
  check (acao !~ '^(financeiro|pagamento|repasse|saque|estorno|reembolso|bloqueio|dado_pessoal)\.'
         or nullif(btrim(coalesce(motivo, '')), '') is not null)
);
alter sequence public.auditoria_id_seq owned by public.auditoria.id;
create index auditoria_entidade_idx on public.auditoria (entidade, entidade_id, ocorrida_em);
create index auditoria_ator_idx on public.auditoria (ator_id, ocorrida_em);
create index auditoria_acao_idx on public.auditoria (acao, ocorrida_em);
create trigger auditoria_imutavel before update or delete on public.auditoria
  for each row execute function public.bloquear_alteracao();
create trigger auditoria_sem_truncate before truncate on public.auditoria
  for each statement execute function public.bloquear_alteracao();
alter table public.auditoria enable row level security;

-- Hash de uma linha: dependente do hash da linha anterior (cadeia).
create or replace function public.auditoria_calcular_hash(linha public.auditoria, anterior text)
returns text
language sql
stable
set search_path = ''
as $$
  select encode(
    sha256(convert_to(concat_ws('|',
      linha.id::text, coalesce(anterior, ''), extract(epoch from linha.ocorrida_em)::text,
      coalesce(linha.ator_id::text, ''), linha.ator_tipo, linha.acao, coalesce(linha.entidade, ''),
      coalesce(linha.entidade_id::text, ''), coalesce(linha.antes::text, ''), coalesce(linha.depois::text, ''),
      coalesce(linha.motivo, ''), coalesce(linha.ip, ''), coalesce(linha.dispositivo, ''),
      coalesce(linha.request_id, '')), 'UTF8')),
    'hex');
$$;

-- Serializa as gravações (lock da transação), numera e encadeia. O horário é sempre o do servidor.
create or replace function public.auditoria_encadear()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  anterior text;
begin
  perform pg_advisory_xact_lock(hashtextextended('trato.auditoria', 0));
  select hash into anterior from public.auditoria order by id desc limit 1;
  new.id := nextval('public.auditoria_id_seq');
  new.ocorrida_em := clock_timestamp();
  new.hash_anterior := anterior;
  new.hash := public.auditoria_calcular_hash(new, anterior);
  return new;
end;
$$;
create trigger auditoria_encadear_trg before insert on public.auditoria
  for each row execute function public.auditoria_encadear();

-- Única porta de entrada. Chamada pelo backend (service_role).
create or replace function public.registrar_auditoria(
  p_ator_id     uuid,
  p_ator_tipo   text,
  p_acao        text,
  p_entidade    text default null,
  p_entidade_id uuid default null,
  p_antes       jsonb default null,
  p_depois      jsonb default null,
  p_motivo      text default null,
  p_ip          text default null,
  p_dispositivo text default null,
  p_request_id  text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  novo bigint;
begin
  insert into public.auditoria (ator_id, ator_tipo, acao, entidade, entidade_id, antes, depois, motivo,
                                ip, dispositivo, request_id, ocorrida_em, hash)
  values (p_ator_id, p_ator_tipo, p_acao, p_entidade, p_entidade_id, p_antes, p_depois, p_motivo,
          p_ip, p_dispositivo, p_request_id, clock_timestamp(), '')
  returning id into novo;
  return novo;
end;
$$;
revoke execute on function public.registrar_auditoria(uuid, text, text, text, uuid, jsonb, jsonb, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.registrar_auditoria(uuid, text, text, text, uuid, jsonb, jsonb, text, text, text, text)
  to service_role;
revoke execute on function public.auditoria_encadear() from public, anon, authenticated;
revoke execute on function public.auditoria_calcular_hash(public.auditoria, text) from public, anon, authenticated;

-- Confere a cadeia inteira. Devolve o id da primeira linha adulterada ou removida (nulo = íntegra).
create or replace function public.verificar_cadeia_auditoria()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  linha public.auditoria%rowtype;
  anterior text := null;
begin
  for linha in select * from public.auditoria order by id loop
    if linha.hash_anterior is distinct from anterior
       or linha.hash is distinct from public.auditoria_calcular_hash(linha, anterior) then
      return linha.id;
    end if;
    anterior := linha.hash;
  end loop;
  return null;
end;
$$;
revoke execute on function public.verificar_cadeia_auditoria() from public, anon, authenticated;
grant execute on function public.verificar_cadeia_auditoria() to service_role;

-- ---------------------------------------------------------------------------
-- Acesso: sem app até a F3.8. Mensagens e auditoria não aceitam DELETE/TRUNCATE nem do service_role;
-- auditoria também não aceita INSERT/UPDATE direto (só por registrar_auditoria).
-- ---------------------------------------------------------------------------
revoke all on table public.conversas, public.mensagens, public.notificacoes,
  public.notificacao_preferencias, public.auditoria from public, anon, authenticated;
revoke delete, truncate on table public.conversas, public.mensagens from service_role;
revoke insert, update, delete, truncate on table public.auditoria from service_role;
revoke all on sequence public.auditoria_id_seq from public, anon, authenticated, service_role;
