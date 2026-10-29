-- F3.4 — Execução: etapas, aditivos, notas de material, agendamentos e presenças (check-in/out).
-- Fonte: docs/modelo-de-dados.md, seção 6 (aprovado pelo João em 28/10/2026).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Só DDL. RLS ligado e sem policy (F3.8). anon/authenticated sem acesso até a F3.8.
-- Depende da F3.3. Reversão: supabase/rollback/F3.4_rollback.sql

-- ---------------------------------------------------------------------------
-- 6.1 etapas — nascem como proposta do orçamento; congelam no aceite
-- ---------------------------------------------------------------------------
create table public.etapas (
  id             uuid primary key default gen_random_uuid(),
  orcamento_id   uuid not null references public.orcamentos (id) on delete restrict,
  contrato_id    uuid references public.contratos (id) on delete restrict,
  ordem          integer not null check (ordem >= 0),
  descricao      text not null,
  valor_centavos bigint not null check (valor_centavos >= 0),
  status         text not null default 'prevista'
                   check (status in ('prevista', 'em_execucao', 'aguardando_aprovacao', 'aprovada',
                                     'paga', 'liberada')),
  prova_midia_id uuid references public.midias (id) on delete restrict,
  aprovada_em    timestamptz,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (orcamento_id, ordem)
);
create index etapas_contrato_idx on public.etapas (contrato_id) where contrato_id is not null;
create trigger etapas_atualizado_em before update on public.etapas
  for each row execute function public.definir_atualizado_em();
alter table public.etapas enable row level security;

create or replace function public.etapas_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  orc public.orcamentos%rowtype;
  ctr_orcamento uuid;
  midia_pedido uuid;
begin
  select * into orc from public.orcamentos
    where id = case when tg_op = 'DELETE' then old.orcamento_id else new.orcamento_id end;

  if tg_op = 'INSERT' then
    if orc.status <> 'rascunho' then
      raise exception 'Etapas só entram enquanto o orçamento é rascunho' using errcode = 'restrict_violation';
    end if;
  elsif tg_op = 'DELETE' then
    if old.contrato_id is not null or orc.status <> 'rascunho' then
      raise exception 'Etapa congelada não pode ser apagada' using errcode = 'restrict_violation';
    end if;
    return old;
  else
    if old.contrato_id is not null then
      if (new.orcamento_id, new.contrato_id, new.ordem, new.descricao, new.valor_centavos)
         is distinct from (old.orcamento_id, old.contrato_id, old.ordem, old.descricao, old.valor_centavos) then
        raise exception 'Etapa já vinculada ao contrato: descrição e valor estão congelados'
          using errcode = 'restrict_violation';
      end if;
    elsif orc.status <> 'rascunho' then
      if (new.orcamento_id, new.ordem, new.descricao, new.valor_centavos)
         is distinct from (old.orcamento_id, old.ordem, old.descricao, old.valor_centavos) then
        raise exception 'Orçamento já enviado: descrição e valor da etapa estão congelados'
          using errcode = 'restrict_violation';
      end if;
    end if;
  end if;

  if new.contrato_id is not null then
    select orcamento_id into ctr_orcamento from public.contratos where id = new.contrato_id;
    if ctr_orcamento is distinct from new.orcamento_id then
      raise exception 'A etapa pertence a outro orçamento' using errcode = 'check_violation';
    end if;
  end if;
  if new.prova_midia_id is not null then
    select pedido_id into midia_pedido from public.midias where id = new.prova_midia_id;
    if midia_pedido is distinct from orc.pedido_id then
      raise exception 'A prova da etapa é de outro pedido' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
create trigger etapas_validar_trg before insert or update or delete on public.etapas
  for each row execute function public.etapas_validar();

-- ---------------------------------------------------------------------------
-- 6.2 aditivos — valem só com a aprovação do cliente no app (D9)
-- ---------------------------------------------------------------------------
create table public.aditivos (
  id                  uuid primary key default gen_random_uuid(),
  contrato_id         uuid not null references public.contratos (id) on delete restrict,
  criado_por          uuid not null references public.usuarios (id) on delete restrict,
  motivo              text not null check (btrim(motivo) <> ''),
  valor_centavos      bigint not null check (valor_centavos > 0),
  taxa_bps_aplicada   integer check (taxa_bps_aplicada is null or taxa_bps_aplicada between 0 and 10000),  -- N3
  taxa_trato_centavos bigint check (taxa_trato_centavos is null or taxa_trato_centavos >= 0),
  status              text not null default 'pendente'
                        check (status in ('pendente', 'aprovado', 'recusado', 'expirado', 'cancelado')),
  decidido_por        uuid references public.usuarios (id) on delete restrict,
  decidido_em         timestamptz,
  criado_em           timestamptz not null default now(),
  check (status not in ('aprovado', 'recusado') or (decidido_por is not null and decidido_em is not null))
);
create index aditivos_contrato_status_idx on public.aditivos (contrato_id, status);
alter table public.aditivos enable row level security;

create or replace function public.aditivos_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ctr public.contratos%rowtype;
begin
  select * into ctr from public.contratos where id = new.contrato_id;
  if tg_op = 'INSERT' then
    if new.criado_por is distinct from ctr.profissional_id then
      raise exception 'Só o profissional do contrato propõe aditivo' using errcode = 'check_violation';
    end if;
  else
    if old.status <> 'pendente' then
      raise exception 'Aditivo %: decisão já registrada, não pode mudar', old.status
        using errcode = 'restrict_violation';
    end if;
    if (new.contrato_id, new.criado_por, new.motivo, new.valor_centavos, new.criado_em)
       is distinct from (old.contrato_id, old.criado_por, old.motivo, old.valor_centavos, old.criado_em) then
      raise exception 'O conteúdo do aditivo não pode ser alterado' using errcode = 'restrict_violation';
    end if;
  end if;
  if new.status = 'aprovado' and new.decidido_por is distinct from ctr.cliente_id then
    raise exception 'Só o cliente do contrato aprova o aditivo' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger aditivos_validar_trg before insert or update on public.aditivos
  for each row execute function public.aditivos_validar();
create trigger aditivos_sem_delete before delete on public.aditivos
  for each row execute function public.bloquear_alteracao();

-- ---------------------------------------------------------------------------
-- 6.3 notas_material e nota_material_itens (D8) — a notinha é prova de custo
-- ---------------------------------------------------------------------------
create table public.notas_material (
  id             uuid primary key default gen_random_uuid(),
  contrato_id    uuid not null references public.contratos (id) on delete restrict,
  aditivo_id     uuid references public.aditivos (id) on delete restrict,
  etapa_id       uuid references public.etapas (id) on delete restrict,
  enviada_por    uuid not null references public.usuarios (id) on delete restrict,
  midia_id       uuid not null references public.midias (id) on delete restrict,  -- foto da notinha
  total_centavos bigint not null check (total_centavos >= 0),
  status         text not null default 'enviada' check (status in ('enviada', 'vista', 'contestada')),
  enviada_em     timestamptz not null default now(),
  vista_em       timestamptz
);
create index notas_material_contrato_idx on public.notas_material (contrato_id);
create trigger notas_material_proteger before update on public.notas_material
  for each row execute function public.proteger_colunas(
    'contrato_id', 'aditivo_id', 'etapa_id', 'enviada_por', 'midia_id', 'total_centavos', 'enviada_em');
create trigger notas_material_sem_delete before delete on public.notas_material
  for each row execute function public.bloquear_alteracao();
alter table public.notas_material enable row level security;

create table public.nota_material_itens (
  id                      uuid primary key default gen_random_uuid(),
  nota_id                 uuid not null references public.notas_material (id) on delete restrict,
  descricao               text not null,
  quantidade              numeric(10, 2) not null check (quantidade > 0),
  valor_unitario_centavos bigint not null check (valor_unitario_centavos >= 0),
  total_centavos          bigint not null check (total_centavos >= 0),
  ordem                   integer not null default 0
);
create index nota_material_itens_nota_idx on public.nota_material_itens (nota_id, ordem);
create trigger nota_material_itens_imutavel before update or delete on public.nota_material_itens
  for each row execute function public.bloquear_alteracao();
alter table public.nota_material_itens enable row level security;

create or replace function public.notas_material_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ctr public.contratos%rowtype;
  midia public.midias%rowtype;
begin
  select * into ctr from public.contratos where id = new.contrato_id;
  if new.enviada_por is distinct from ctr.profissional_id then
    raise exception 'Só o profissional do contrato envia nota de material' using errcode = 'check_violation';
  end if;
  select * into midia from public.midias where id = new.midia_id;
  if midia.pedido_id is distinct from ctr.pedido_id or midia.finalidade <> 'nota_material' then
    raise exception 'A foto da nota deve ser uma mídia nota_material deste pedido' using errcode = 'check_violation';
  end if;
  if new.aditivo_id is not null
     and not exists (select 1 from public.aditivos where id = new.aditivo_id and contrato_id = new.contrato_id) then
    raise exception 'O aditivo é de outro contrato' using errcode = 'check_violation';
  end if;
  if new.etapa_id is not null
     and not exists (select 1 from public.etapas where id = new.etapa_id and contrato_id = new.contrato_id) then
    raise exception 'A etapa é de outro contrato' using errcode = 'check_violation';
  end if;
  new.enviada_em := now();  -- hora do servidor; o item só entra na mesma transação
  return new;
end;
$$;
create trigger notas_material_validar_trg before insert on public.notas_material
  for each row execute function public.notas_material_validar();

-- Item só entra na mesma transação da nota (a nota fecha ao ser gravada).
create or replace function public.nota_material_itens_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from public.notas_material where id = new.nota_id and enviada_em = now()) then
    raise exception 'Itens só entram junto com a nota, na mesma transação' using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
create trigger nota_material_itens_validar_trg before insert on public.nota_material_itens
  for each row execute function public.nota_material_itens_validar();

create or replace function public.nota_material_conferir_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  nota uuid;
  esperado bigint;
  total bigint;
begin
  if tg_table_name = 'notas_material' then
    nota := new.id;
  else
    nota := new.nota_id;
  end if;
  select total_centavos into esperado from public.notas_material where id = nota;
  select coalesce(sum(total_centavos), 0) into total from public.nota_material_itens where nota_id = nota;
  if total <> esperado then
    raise exception 'Nota %: total (%) difere da soma dos itens (%)', nota, esperado, total
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;
revoke execute on function public.nota_material_conferir_total() from public, anon, authenticated;
create constraint trigger notas_material_total_conferir after insert on public.notas_material
  deferrable initially deferred for each row execute function public.nota_material_conferir_total();
create constraint trigger nota_material_itens_total_conferir after insert on public.nota_material_itens
  deferrable initially deferred for each row execute function public.nota_material_conferir_total();

-- ---------------------------------------------------------------------------
-- 6.4 agendamentos
-- ---------------------------------------------------------------------------
create table public.agendamentos (
  id                    uuid primary key default gen_random_uuid(),
  contrato_id           uuid not null references public.contratos (id) on delete restrict,
  etapa_id              uuid references public.etapas (id) on delete restrict,
  data                  date not null,
  janela_inicio         timestamptz not null,
  janela_fim            timestamptz not null,
  status                text not null default 'proposto'
                          check (status in ('proposto', 'confirmado', 'remarcado', 'realizado',
                                            'nao_compareceu', 'cancelado')),
  remarcado_de          uuid references public.agendamentos (id) on delete restrict,
  -- Códigos de 4 dígitos do cliente: só o HASH (com segredo do servidor). Nunca legível pelo app.
  codigo_inicio_hash    text,
  codigo_conclusao_hash text,
  codigo_expira_em      timestamptz,
  endereco_liberado_em  timestamptz,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now(),
  check (janela_fim > janela_inicio),
  check (remarcado_de is distinct from id)
);
create index agendamentos_contrato_data_idx on public.agendamentos (contrato_id, data);
create index agendamentos_status_janela_idx on public.agendamentos (status, janela_inicio);
create trigger agendamentos_atualizado_em before update on public.agendamentos
  for each row execute function public.definir_atualizado_em();
create trigger agendamentos_proteger before update on public.agendamentos
  for each row execute function public.proteger_colunas('contrato_id', 'criado_em');
alter table public.agendamentos enable row level security;

create or replace function public.agendamentos_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.etapa_id is not null
     and not exists (select 1 from public.etapas where id = new.etapa_id and contrato_id = new.contrato_id) then
    raise exception 'A etapa é de outro contrato' using errcode = 'check_violation';
  end if;
  if new.remarcado_de is not null
     and not exists (select 1 from public.agendamentos where id = new.remarcado_de and contrato_id = new.contrato_id) then
    raise exception 'A remarcação é de outro contrato' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger agendamentos_validar_trg before insert or update on public.agendamentos
  for each row execute function public.agendamentos_validar();

-- ---------------------------------------------------------------------------
-- 6.5 presencas — check-in e check-out (imutável; hora do servidor)
-- ---------------------------------------------------------------------------
create table public.presencas (
  id                       uuid primary key default gen_random_uuid(),
  agendamento_id           uuid not null references public.agendamentos (id) on delete restrict,
  tipo                     text not null check (tipo in ('check_in', 'check_out')),
  registrada_por           uuid not null references public.usuarios (id) on delete restrict,
  lat                      double precision check (lat is null or lat between -90 and 90),
  lng                      double precision check (lng is null or lng between -180 and 180),
  precisao_m               double precision check (precisao_m is null or precisao_m >= 0),
  distancia_do_endereco_m  integer check (distancia_do_endereco_m is null or distancia_do_endereco_m >= 0),
  foto_midia_id            uuid references public.midias (id) on delete restrict,
  codigo_validado          boolean not null default false,
  registrada_em            timestamptz not null default now(),
  offline_capturada_em     timestamptz,
  unique (agendamento_id, tipo)
);
create trigger presencas_imutavel before update or delete on public.presencas
  for each row execute function public.bloquear_alteracao();
create trigger presencas_sem_truncate before truncate on public.presencas
  for each statement execute function public.bloquear_alteracao();
alter table public.presencas enable row level security;

create or replace function public.presencas_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ctr public.contratos%rowtype;
  midia_pedido uuid;
begin
  select c.* into ctr from public.contratos c
    join public.agendamentos a on a.contrato_id = c.id where a.id = new.agendamento_id;
  if new.registrada_por is distinct from ctr.profissional_id then
    raise exception 'Só o profissional do contrato registra presença' using errcode = 'check_violation';
  end if;
  if new.tipo = 'check_out' and not exists (
       select 1 from public.presencas where agendamento_id = new.agendamento_id and tipo = 'check_in') then
    raise exception 'Check-out exige check-in antes' using errcode = 'check_violation';
  end if;
  if new.foto_midia_id is not null then
    select pedido_id into midia_pedido from public.midias where id = new.foto_midia_id;
    if midia_pedido is distinct from ctr.pedido_id then
      raise exception 'A foto é de outro pedido' using errcode = 'check_violation';
    end if;
  end if;
  new.registrada_em := now();  -- hora do servidor, nunca a do aparelho
  return new;
end;
$$;
create trigger presencas_validar_trg before insert on public.presencas
  for each row execute function public.presencas_validar();

-- ---------------------------------------------------------------------------
-- Acesso. Privilégios EXPLÍCITOS, iguais em qualquer padrão da plataforma:
--  * anon e authenticated: nada (a F3.8b concede só SELECT, por coluna);
--  * service_role (backend): só o que a tabela precisa. Nunca TRUNCATE.
--    Tabela imutável recebe apenas SELECT e INSERT.
-- ---------------------------------------------------------------------------
revoke all on table public.etapas, public.aditivos, public.notas_material, public.nota_material_itens,
  public.agendamentos, public.presencas from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.etapas to service_role;
grant select, insert, update on table public.aditivos, public.notas_material, public.agendamentos to service_role;
grant select, insert on table public.nota_material_itens, public.presencas to service_role;
revoke execute on function public.etapas_validar(), public.aditivos_validar(), public.notas_material_validar(),
  public.nota_material_itens_validar(), public.agendamentos_validar(), public.presencas_validar()
  from public, anon, authenticated;
