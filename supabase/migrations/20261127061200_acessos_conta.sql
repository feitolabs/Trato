-- ===========================================================================
-- 20261127061200_acessos_conta.sql
-- RASCUNHO (DB-TERMOS-100). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 14.3 (IP, data e hora, tipo de aparelho, sistema, identificadores e registros de
-- acesso), 16.1 (registros de acesso à conta), 14.8 e 16.3 (guardar no mínimo 6 meses; com
-- Disputa, processo ou investigação, até o fim). Marco Civil, art. 15.
-- Hoje só há IP/aparelho de ações isoladas (auditoria, consentimentos, aceite do contrato) e o
-- token de push: não existe registro de acesso.
--
--   1. public.acessos_conta: um registro por acesso; hora do banco; imutável.
--   2. public.acessos_conta_guardas: guarda por processo ou investigação (segura o expurgo).
--   3. registrar_acesso_conta: grava; repetição do mesmo usuário, evento, IP e aparelho dentro
--      da janela (padrão 60 min; 0 grava tudo) não grava de novo.
--   4. expurgar_acessos_conta: único caminho para apagar; só o que passou do prazo
--      (acessos_conta_retencao_meses, padrão e mínimo 6) e sem guarda, disputa aberta ou
--      incidente aberto. NADA roda sozinho; ligar o expurgo é decisão à parte.
-- RLS ligada, sem policy; service_role só lê e chama as funções.
-- Papéis que abrem ou encerram guarda (equipe ativa): dpo, juridico, seguranca, administrador.
--
-- Rollback: supabase/rollback/20261127061200_acessos_conta_rollback.sql
-- ===========================================================================

begin;

create table if not exists public.acessos_conta (
  id                  bigint generated always as identity primary key,
  usuario_id          uuid not null references public.usuarios (id) on delete restrict,
  evento              text not null check (evento in ('login', 'sessao_renovada', 'acesso', 'logout')),
  ocorrido_em         timestamptz not null default now(),
  ip                  inet not null,
  aparelho_tipo       text check (aparelho_tipo in ('android', 'ios', 'web', 'desktop', 'outro')),
  sistema_operacional text check (char_length(sistema_operacional) <= 80),
  dispositivo_id      text check (char_length(dispositivo_id) <= 200),
  user_agent          text check (char_length(user_agent) <= 400),
  app_versao          text check (char_length(app_versao) <= 40)
);
create index if not exists ix_acessos_conta_usuario on public.acessos_conta (usuario_id, ocorrido_em desc);
create index if not exists ix_acessos_conta_quando on public.acessos_conta (ocorrido_em);
create index if not exists ix_acessos_conta_ip on public.acessos_conta (ip, ocorrido_em desc);

create table if not exists public.acessos_conta_guardas (
  id            uuid primary key default gen_random_uuid(),
  usuario_id    uuid not null references public.usuarios (id) on delete restrict,
  motivo        text not null check (btrim(motivo) <> ''),
  criada_por    uuid not null references public.equipe (usuario_id) on delete restrict,
  criada_em     timestamptz not null default now(),
  encerrada_em  timestamptz,
  encerrada_por uuid references public.equipe (usuario_id) on delete restrict,
  check ((encerrada_em is null) = (encerrada_por is null))
);
create index if not exists ix_acessos_guardas_abertas
  on public.acessos_conta_guardas (usuario_id) where encerrada_em is null;

create or replace function public.acessos_conta_proteger()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'Registro de acesso não muda' using errcode = 'restrict_violation';
  end if;
  -- piso legal: vale para qualquer caminho, inclusive o dono do banco
  if old.ocorrido_em > now() - interval '6 months' then
    raise exception 'Registro de acesso com menos de 6 meses não se apaga'
      using errcode = 'restrict_violation';
  end if;
  return old;
end;
$$;
revoke all on function public.acessos_conta_proteger() from public, anon, authenticated, service_role;

create or replace function public.acessos_guardas_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_quem uuid;
begin
  if tg_op = 'INSERT' then
    if new.encerrada_em is not null then
      raise exception 'Guarda deve nascer aberta' using errcode = 'check_violation';
    end if;
    new.criada_em := now();
    v_quem := new.criada_por;
  else
    if old.encerrada_em is not null then
      raise exception 'Guarda encerrada não muda' using errcode = 'restrict_violation';
    end if;
    if new.encerrada_em is null then
      return new;
    end if;
    new.encerrada_em := now();
    v_quem := new.encerrada_por;
  end if;
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = v_quem and q.ativo and q.revogado_em is null
                    and q.papel in ('dpo', 'juridico', 'seguranca', 'administrador')) then
    raise exception 'Guarda de acessos exige dpo, jurídico, segurança ou administrador ativo'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.acessos_guardas_validar() from public, anon, authenticated, service_role;

drop trigger if exists acessos_conta_proteger_trg on public.acessos_conta;
create trigger acessos_conta_proteger_trg before update or delete on public.acessos_conta
  for each row execute function public.acessos_conta_proteger();
drop trigger if exists acessos_conta_sem_truncate on public.acessos_conta;
create trigger acessos_conta_sem_truncate before truncate on public.acessos_conta
  for each statement execute function public.bloquear_alteracao();
drop trigger if exists acessos_guardas_proteger on public.acessos_conta_guardas;
create trigger acessos_guardas_proteger before update on public.acessos_conta_guardas
  for each row execute function public.proteger_colunas('id', 'usuario_id', 'motivo', 'criada_por', 'criada_em');
drop trigger if exists acessos_guardas_validar_trg on public.acessos_conta_guardas;
create trigger acessos_guardas_validar_trg before insert or update on public.acessos_conta_guardas
  for each row execute function public.acessos_guardas_validar();
drop trigger if exists acessos_guardas_sem_delete on public.acessos_conta_guardas;
create trigger acessos_guardas_sem_delete before delete on public.acessos_conta_guardas
  for each row execute function public.bloquear_alteracao();
drop trigger if exists acessos_guardas_sem_truncate on public.acessos_conta_guardas;
create trigger acessos_guardas_sem_truncate before truncate on public.acessos_conta_guardas
  for each statement execute function public.bloquear_alteracao();

create or replace function public.registrar_acesso_conta(
  p_usuario uuid, p_evento text, p_ip text, p_aparelho_tipo text default null,
  p_sistema text default null, p_dispositivo_id text default null, p_user_agent text default null,
  p_app_versao text default null, p_janela_minutos integer default 60)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_ip          inet;
  v_dispositivo text := nullif(btrim(left(p_dispositivo_id, 200)), '');
begin
  if p_usuario is null or p_evento is null or p_janela_minutos is null or p_janela_minutos < 0
     or p_janela_minutos > 1440 then
    raise exception 'usuário, evento e janela de 0 a 1440 minutos são obrigatórios';
  end if;
  begin
    v_ip := btrim(p_ip)::inet;
  exception when invalid_text_representation then
    return 'ip_invalido';
  end;
  if v_ip is null then
    return 'ip_invalido';
  end if;
  if not exists (select 1 from public.usuarios u where u.id = p_usuario) then
    return 'usuario_nao_encontrado';
  end if;
  if p_janela_minutos > 0 then
    perform pg_advisory_xact_lock(hashtextextended('acesso:' || p_usuario::text, 0));
    if exists (select 1 from public.acessos_conta a
                where a.usuario_id = p_usuario and a.evento = p_evento and a.ip = v_ip
                  and a.dispositivo_id is not distinct from v_dispositivo
                  and a.ocorrido_em > now() - make_interval(mins => p_janela_minutos)) then
      return 'repetido';
    end if;
  end if;
  insert into public.acessos_conta
    (usuario_id, evento, ip, aparelho_tipo, sistema_operacional, dispositivo_id, user_agent, app_versao)
  values (p_usuario, p_evento, v_ip, p_aparelho_tipo, nullif(btrim(left(p_sistema, 80)), ''),
          v_dispositivo, nullif(btrim(left(p_user_agent, 400)), ''), nullif(btrim(left(p_app_versao, 40)), ''));
  return 'registrado';
end;
$$;

create or replace function public.expurgar_acessos_conta(p_limite integer default 5000)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_meses integer;
  v_n     integer;
  v_extra text := '';
begin
  if p_limite is null or p_limite < 1 or p_limite > 100000 then
    raise exception 'limite deve ficar entre 1 e 100000';
  end if;
  select greatest(coalesce(max(p.valor), 6), 6)::integer into v_meses
    from public.config_parametros p
    join public.config_versoes v on v.id = p.versao_id and v.status = 'vigente'
   where p.chave = 'acessos_conta_retencao_meses' and p.escopo_tipo = 'global';
  -- incidentes: tabela da 20261125225500, que pode ainda não existir
  if to_regclass('public.incidentes_seguranca') is not null then
    v_extra := ' and not exists (select 1 from public.incidentes_seguranca i '
            || 'where i.envolvido_id = a.usuario_id and i.status <> ''encerrado'')';
  end if;
  execute
    'delete from public.acessos_conta where id in (select a.id from public.acessos_conta a '
    || 'where a.ocorrido_em < now() - make_interval(months => $1) '
    || 'and not exists (select 1 from public.acessos_conta_guardas g '
    ||                'where g.usuario_id = a.usuario_id and g.encerrada_em is null) '
    || 'and not exists (select 1 from public.disputas d join public.contratos c on c.id = d.contrato_id '
    ||                'where a.usuario_id in (c.cliente_id, c.profissional_id) '
    ||                'and d.status not in (''acordo'', ''decidida'', ''cancelada''))'
    || v_extra || ' order by a.ocorrido_em limit $2)'
    using v_meses, p_limite;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

alter table public.acessos_conta enable row level security;
alter table public.acessos_conta_guardas enable row level security;
revoke all on table public.acessos_conta, public.acessos_conta_guardas
  from public, anon, authenticated, service_role;
grant select on table public.acessos_conta to service_role;
grant select, insert, update on table public.acessos_conta_guardas to service_role;
revoke all on function public.registrar_acesso_conta(uuid, text, text, text, text, text, text, text, integer)
  from public, anon, authenticated;
revoke all on function public.expurgar_acessos_conta(integer) from public, anon, authenticated;
grant execute on function public.registrar_acesso_conta(uuid, text, text, text, text, text, text, text, integer)
  to service_role;
grant execute on function public.expurgar_acessos_conta(integer) to service_role;

commit;
