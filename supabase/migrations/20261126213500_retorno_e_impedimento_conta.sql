-- ===========================================================================
-- 20261126213500_retorno_e_impedimento_conta.sql
-- RASCUNHO (TERMOS-DB-209). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2, cláusula 20.9 (Reincidência e retorno).
-- Depende de 20261125224500_sac_chamados e 20261125224600_medidas_conta.
--
-- O que acrescenta (sem alterar dados existentes):
--   1. public.medidas_conta: colunas `infracao_grave` e `impedir_nova_conta`
--      (só em tipo = 'encerramento'; impedir_nova_conta exige infracao_grave; imutáveis).
--   2. public.config_definicoes: chave `conta_retorno_prazo_dias` (dias, 1..365, global).
--      Nenhum valor é gravado em config_parametros aqui; sem valor publicado, vale 90.
--      Para publicar/alterar: nova versão pelo painel (criar, aprovar por outra pessoa, publicar).
--   3. public.conta_impedimentos_cadastro: bloqueio de novo cadastro após encerramento por
--      infração grave, guardando SÓ o HMAC-SHA256 em hex (64 caracteres) do identificador
--      normalizado (cpf, email ou telefone) calculado no backend com segredo do ambiente.
--      Nenhum dado pessoal em claro é salvo; sobrevive à anonimização LGPD.
--   4. public.conta_pedidos_retorno: pedidos de retorno após encerramento sem infração grave,
--      respeitando o prazo vigente em configuração (`conta_retorno_prazo_dias`, padrão 90 dias),
--      com análise caso a caso e registro de risco a outras pessoas.
--
-- Papéis conferidos no banco (equipe ativa e não revogada):
--   registrar impedimento / assumir ou recusar retorno: mediador, lider_suporte, seguranca, administrador
--   aprovar retorno / revogar impedimento:              lider_suporte, administrador
--
-- RLS ligada em todas as tabelas novas, sem policy para o app; grants só para service_role;
-- sem delete nem truncate.
-- Rollback: supabase/rollback/20261126213500_retorno_e_impedimento_conta_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.medidas_conta') is null then
    raise exception 'Aplique antes a migration 20261125224600_medidas_conta';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1) Marca de infração grave e impedimento de nova conta em medidas_conta
-- ---------------------------------------------------------------------------
alter table public.medidas_conta
  add column if not exists infracao_grave boolean not null default false,
  add column if not exists impedir_nova_conta boolean not null default false;

alter table public.medidas_conta drop constraint if exists medidas_conta_infracao_grave_check;
alter table public.medidas_conta add constraint medidas_conta_infracao_grave_check
  check (not infracao_grave or tipo = 'encerramento');

alter table public.medidas_conta drop constraint if exists medidas_conta_impedir_nova_conta_check;
alter table public.medidas_conta add constraint medidas_conta_impedir_nova_conta_check
  check (not impedir_nova_conta or infracao_grave);

drop trigger if exists medidas_conta_retorno_proteger on public.medidas_conta;
create trigger medidas_conta_retorno_proteger before update on public.medidas_conta
  for each row execute function public.proteger_colunas('infracao_grave', 'impedir_nova_conta');

-- ---------------------------------------------------------------------------
-- 2) Definição de configuração do prazo mínimo de retorno (padrão 90 dias)
-- ---------------------------------------------------------------------------
insert into public.config_definicoes (
  chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao
)
values (
  'conta_retorno_prazo_dias',
  'Prazo mínimo após encerramento sem infração grave para pedir retorno da conta (20.9)',
  'dias', 1, 365, array['global'], false
)
on conflict (chave) do nothing;

create or replace function public.conta_retorno_prazo_dias_vigente()
returns integer
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select p.valor::integer
       from public.config_parametros p
       join public.config_versoes v on v.id = p.versao_id
      where v.status = 'vigente'
        and p.chave = 'conta_retorno_prazo_dias'
        and p.escopo_tipo = 'global'
      limit 1),
    90
  );
$$;
revoke all on function public.conta_retorno_prazo_dias_vigente() from public, anon, authenticated;
grant execute on function public.conta_retorno_prazo_dias_vigente() to service_role;

-- ---------------------------------------------------------------------------
-- 3) Impedimento de novo cadastro (só HMAC-SHA256, sem dado pessoal em claro)
-- ---------------------------------------------------------------------------
create table if not exists public.conta_impedimentos_cadastro (
  id                 uuid primary key default gen_random_uuid(),
  medida_id          uuid not null references public.medidas_conta (id) on delete restrict,
  tipo_identificador text not null check (tipo_identificador in ('cpf', 'email', 'telefone')),
  identificador_hmac text not null check (identificador_hmac ~ '^[0-9a-f]{64}$'),
  criado_por         uuid not null references public.equipe (usuario_id) on delete restrict,
  criado_em          timestamptz not null default now(),
  revogado_em        timestamptz,
  revogado_por       uuid references public.equipe (usuario_id) on delete restrict,
  motivo_revogacao   text,
  constraint conta_impedimentos_revogacao_check check (
    (revogado_em is null and revogado_por is null and motivo_revogacao is null)
    or (revogado_em is not null and revogado_por is not null
        and btrim(coalesce(motivo_revogacao, '')) <> ''
        and revogado_em >= criado_em))
);

create unique index if not exists ux_conta_impedimentos_ativo
  on public.conta_impedimentos_cadastro (tipo_identificador, identificador_hmac)
  where revogado_em is null;
create index if not exists ix_conta_impedimentos_medida
  on public.conta_impedimentos_cadastro (medida_id);

create or replace function public.conta_impedimentos_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_medida record;
begin
  if tg_op = 'INSERT' then
    if new.revogado_em is not null or new.revogado_por is not null or new.motivo_revogacao is not null then
      raise exception 'Impedimento de cadastro deve nascer ativo'
        using errcode = 'check_violation';
    end if;

    select m.tipo, m.infracao_grave, m.impedir_nova_conta, m.revertida_em
      into v_medida
      from public.medidas_conta m
     where m.id = new.medida_id;

    if not found or v_medida.tipo <> 'encerramento' or not v_medida.infracao_grave
       or not v_medida.impedir_nova_conta or v_medida.revertida_em is not null then
      raise exception 'Impedimento exige encerramento vigente por infração grave com impedimento ativo'
        using errcode = 'check_violation';
    end if;

    if not exists (
      select 1 from public.equipe q
       where q.usuario_id = new.criado_por and q.ativo and q.revogado_em is null
         and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')
    ) then
      raise exception 'Operador precisa ser da equipe ativa com papel de análise'
        using errcode = 'check_violation';
    end if;

    return new;
  end if;

  if old.revogado_em is not null then
    raise exception 'Impedimento já revogado não pode mudar'
      using errcode = 'restrict_violation';
  end if;

  if new.revogado_em is not null then
    if not exists (
      select 1 from public.equipe q
       where q.usuario_id = new.revogado_por and q.ativo and q.revogado_em is null
         and q.papel in ('lider_suporte', 'administrador')
    ) then
      raise exception 'Revogação exige líder de suporte ou administrador ativo'
        using errcode = 'check_violation';
    end if;
    if new.revogado_em > now() + interval '5 minutes' then
      raise exception 'Data de revogação no futuro não é permitida'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.conta_impedimentos_validar() from public, anon, authenticated, service_role;

drop trigger if exists conta_impedimentos_proteger on public.conta_impedimentos_cadastro;
create trigger conta_impedimentos_proteger before update on public.conta_impedimentos_cadastro
  for each row execute function public.proteger_colunas(
    'id', 'medida_id', 'tipo_identificador', 'identificador_hmac', 'criado_por', 'criado_em');
drop trigger if exists conta_impedimentos_validar_trg on public.conta_impedimentos_cadastro;
create trigger conta_impedimentos_validar_trg before insert or update on public.conta_impedimentos_cadastro
  for each row execute function public.conta_impedimentos_validar();
drop trigger if exists conta_impedimentos_sem_delete on public.conta_impedimentos_cadastro;
create trigger conta_impedimentos_sem_delete before delete on public.conta_impedimentos_cadastro
  for each row execute function public.bloquear_alteracao();
drop trigger if exists conta_impedimentos_sem_truncate on public.conta_impedimentos_cadastro;
create trigger conta_impedimentos_sem_truncate before truncate on public.conta_impedimentos_cadastro
  for each statement execute function public.bloquear_alteracao();

-- ---------------------------------------------------------------------------
-- 4) Pedidos de retorno de conta (encerramento sem infração grave)
-- ---------------------------------------------------------------------------
create sequence if not exists public.conta_pedidos_retorno_protocolo_seq;
revoke all on sequence public.conta_pedidos_retorno_protocolo_seq
  from public, anon, authenticated, service_role;

create table if not exists public.conta_pedidos_retorno (
  id                    uuid primary key default gen_random_uuid(),
  protocolo             text not null unique check (protocolo ~ '^RET-[0-9]{4}-[0-9]{6,}$'),
  usuario_id            uuid not null references public.usuarios (id) on delete restrict,
  medida_id             uuid not null references public.medidas_conta (id) on delete restrict,
  justificativa_usuario text not null check (btrim(justificativa_usuario) <> '' and char_length(justificativa_usuario) <= 4000),
  canal                 text not null check (canal in ('app', 'sac', 'email')),
  status                text not null default 'aberto'
                          check (status in ('aberto', 'em_analise', 'aprovado', 'recusado')),
  solicitado_em         timestamptz not null default now(),
  prazo_dias_aplicado   integer not null check (prazo_dias_aplicado between 1 and 365),
  elegivel_a_partir_de  timestamptz not null,
  analista_id           uuid references public.equipe (usuario_id) on delete restrict,
  decisao_motivo        text,
  risco_identificado    boolean not null default false,
  decidido_em           timestamptz,
  criado_em             timestamptz not null default now(),
  constraint conta_pedidos_retorno_decisao_check check (
    case status
      when 'aberto' then
        analista_id is null and decisao_motivo is null and decidido_em is null and not risco_identificado
      when 'em_analise' then
        analista_id is not null and decisao_motivo is null and decidido_em is null and not risco_identificado
      when 'aprovado' then
        analista_id is not null and btrim(coalesce(decisao_motivo, '')) <> ''
        and decidido_em is not null and not risco_identificado
      else
        analista_id is not null and btrim(coalesce(decisao_motivo, '')) <> ''
        and decidido_em is not null
    end),
  constraint conta_pedidos_retorno_datas_check check (
    solicitado_em >= elegivel_a_partir_de
    and (decidido_em is null or decidido_em >= solicitado_em))
);

create unique index if not exists ux_conta_pedidos_retorno_aberto
  on public.conta_pedidos_retorno (usuario_id)
  where status in ('aberto', 'em_analise');
create index if not exists ix_conta_pedidos_retorno_status
  on public.conta_pedidos_retorno (status, solicitado_em);
create index if not exists ix_conta_pedidos_retorno_medida
  on public.conta_pedidos_retorno (medida_id);

create or replace function public.conta_pedidos_retorno_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_medida   record;
  v_prazo    integer;
  v_elegivel timestamptz;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'aberto' or new.analista_id is not null or new.decisao_motivo is not null
       or new.decidido_em is not null or new.risco_identificado then
      raise exception 'Pedido de retorno deve nascer aberto e sem decisão'
        using errcode = 'check_violation';
    end if;

    if new.solicitado_em > now() + interval '5 minutes' then
      raise exception 'Data de solicitação no futuro não é permitida'
        using errcode = 'check_violation';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('pedido_retorno:' || new.usuario_id::text, 0));

    select m.usuario_id, m.tipo, m.infracao_grave, m.revertida_em, m.inicio_em
      into v_medida
      from public.medidas_conta m
     where m.id = new.medida_id;

    if not found or v_medida.usuario_id is distinct from new.usuario_id then
      raise exception 'Medida de encerramento não pertence ao usuário'
        using errcode = 'check_violation';
    end if;

    if v_medida.tipo <> 'encerramento' or v_medida.revertida_em is not null then
      raise exception 'Pedido de retorno exige encerramento vigente'
        using errcode = 'check_violation';
    end if;

    if v_medida.infracao_grave or exists (
      select 1 from public.medidas_conta m
       where m.usuario_id = new.usuario_id
         and m.tipo = 'encerramento'
         and m.revertida_em is null
         and m.infracao_grave
    ) then
      raise exception 'Conta encerrada por infração grave não é elegível para pedido de retorno'
        using errcode = 'check_violation';
    end if;

    v_prazo := public.conta_retorno_prazo_dias_vigente();
    if new.prazo_dias_aplicado is null then
      new.prazo_dias_aplicado := v_prazo;
    elsif new.prazo_dias_aplicado <> v_prazo then
      raise exception 'prazo_dias_aplicado deve corresponder à configuração vigente (% dias)', v_prazo
        using errcode = 'check_violation';
    end if;

    v_elegivel := v_medida.inicio_em + make_interval(days => v_prazo);
    if new.elegivel_a_partir_de is null then
      new.elegivel_a_partir_de := v_elegivel;
    elsif new.elegivel_a_partir_de <> v_elegivel then
      raise exception 'elegivel_a_partir_de deve corresponder ao início do encerramento mais % dias', v_prazo
        using errcode = 'check_violation';
    end if;

    if new.solicitado_em < v_elegivel then
      raise exception 'Prazo mínimo de % dias para pedir retorno ainda não foi cumprido', v_prazo
        using errcode = 'check_violation';
    end if;

    return new;
  end if;

  if old.status in ('aprovado', 'recusado') then
    raise exception 'Pedido de retorno já decidido não pode mudar'
      using errcode = 'restrict_violation';
  end if;

  if old.status = 'em_analise' and new.status = 'aberto' then
    raise exception 'Pedido de retorno em análise não volta para aberto'
      using errcode = 'check_violation';
  end if;

  if new.status in ('em_analise', 'recusado') then
    if not exists (
      select 1 from public.equipe q
       where q.usuario_id = new.analista_id and q.ativo and q.revogado_em is null
         and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')
    ) then
      raise exception 'Analista precisa ser da equipe ativa com papel de análise'
        using errcode = 'check_violation';
    end if;
  elsif new.status = 'aprovado' then
    if not exists (
      select 1 from public.equipe q
       where q.usuario_id = new.analista_id and q.ativo and q.revogado_em is null
         and q.papel in ('lider_suporte', 'administrador')
    ) then
      raise exception 'Aprovação de retorno exige líder de suporte ou administrador ativo'
        using errcode = 'check_violation';
    end if;
  end if;

  if new.decidido_em is not null and new.decidido_em > now() + interval '5 minutes' then
    raise exception 'Data de decisão no futuro não é permitida'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;
revoke all on function public.conta_pedidos_retorno_validar() from public, anon, authenticated, service_role;

drop trigger if exists conta_pedidos_retorno_protocolo on public.conta_pedidos_retorno;
create trigger conta_pedidos_retorno_protocolo before insert on public.conta_pedidos_retorno
  for each row execute function public.sac_gerar_protocolo('RET', 'conta_pedidos_retorno_protocolo_seq');
drop trigger if exists conta_pedidos_retorno_proteger on public.conta_pedidos_retorno;
create trigger conta_pedidos_retorno_proteger before update on public.conta_pedidos_retorno
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'usuario_id', 'medida_id', 'justificativa_usuario', 'canal',
    'solicitado_em', 'prazo_dias_aplicado', 'elegivel_a_partir_de', 'criado_em');
drop trigger if exists conta_pedidos_retorno_validar_trg on public.conta_pedidos_retorno;
create trigger conta_pedidos_retorno_validar_trg before insert or update on public.conta_pedidos_retorno
  for each row execute function public.conta_pedidos_retorno_validar();
drop trigger if exists conta_pedidos_retorno_sem_delete on public.conta_pedidos_retorno;
create trigger conta_pedidos_retorno_sem_delete before delete on public.conta_pedidos_retorno
  for each row execute function public.bloquear_alteracao();
drop trigger if exists conta_pedidos_retorno_sem_truncate on public.conta_pedidos_retorno;
create trigger conta_pedidos_retorno_sem_truncate before truncate on public.conta_pedidos_retorno
  for each statement execute function public.bloquear_alteracao();

-- ---------------------------------------------------------------------------
-- 5) RLS e permissões
-- ---------------------------------------------------------------------------
alter table public.conta_impedimentos_cadastro enable row level security;
alter table public.conta_pedidos_retorno enable row level security;

revoke all on table public.conta_impedimentos_cadastro, public.conta_pedidos_retorno
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.conta_impedimentos_cadastro, public.conta_pedidos_retorno
  to service_role;

commit;
