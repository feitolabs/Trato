-- ===========================================================================
-- 20261127223000_selo_eventos.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, 10.3: histórico imutável do selo do profissional e retirada até a
-- regularização. Retirar = evento + nivel_verificacao 'basico', na mesma transação.
-- Enquanto houver retirada sem regularização, o banco recusa subir o nível por qualquer
-- outro caminho (inclusive a aprovação de nova verificação): erro 23001 'selo_retirado'.
-- Não suspende conta, não mexe em perfis_profissional.status nem em orçamento já
-- enviado. Selfie no Check-in fora do escopo (depende de decisão). Só acrescenta; sem
-- UPDATE de dados ao aplicar. Sem histórico para retiradas anteriores a esta migration.
--
-- Depende de 20261029025430 (perfis_profissional, equipe, bloquear_alteracao). O
-- gatilho de orçamento da 20261029030000 já recusa novo envio com nível 'basico'.
--
-- Rollback: supabase/rollback/20261127223000_selo_eventos_rollback.sql
-- ===========================================================================

begin;

create table if not exists public.selo_eventos (
  id                 uuid primary key default gen_random_uuid(),
  profissional_id    uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  tipo               text not null
                       constraint selo_eventos_tipo_check
                       check (tipo in ('retirada', 'reconferencia_pedida', 'regularizacao')),
  motivo             text not null
                       constraint selo_eventos_motivo_check check (length(btrim(motivo)) >= 10),
  operador_id        uuid not null references public.equipe (usuario_id) on delete restrict,
  nivel_anterior     text not null,
  nivel_novo         text not null,
  retirada_id        uuid references public.selo_eventos (id) on delete restrict,
  chave_idempotencia text not null
                       constraint selo_eventos_chave_check check (btrim(chave_idempotencia) <> ''),
  ocorrido_em        timestamptz not null default now(),
  constraint selo_eventos_niveis_check check (
    nivel_anterior in ('basico', 'verificado', 'verificado_plus')
    and nivel_novo in ('basico', 'verificado', 'verificado_plus')
    and case tipo
          when 'retirada' then nivel_anterior <> 'basico' and nivel_novo = 'basico'
          when 'regularizacao' then nivel_anterior = 'basico' and nivel_novo <> 'basico'
          else nivel_novo = nivel_anterior
        end),
  constraint selo_eventos_retirada_check check ((tipo = 'regularizacao') = (retirada_id is not null))
);
create unique index if not exists selo_eventos_chave_uidx on public.selo_eventos (chave_idempotencia);
-- cada retirada é regularizada uma vez só
create unique index if not exists selo_eventos_retirada_uidx on public.selo_eventos (retirada_id)
  where retirada_id is not null;
create index if not exists selo_eventos_profissional_idx on public.selo_eventos (profissional_id, ocorrido_em);
create index if not exists selo_eventos_operador_idx on public.selo_eventos (operador_id);

drop trigger if exists selo_eventos_imutavel on public.selo_eventos;
create trigger selo_eventos_imutavel before update or delete on public.selo_eventos
  for each row execute function public.bloquear_alteracao();
drop trigger if exists selo_eventos_sem_truncate on public.selo_eventos;
create trigger selo_eventos_sem_truncate before truncate on public.selo_eventos
  for each statement execute function public.bloquear_alteracao();

alter table public.selo_eventos enable row level security;
-- gravação só pelas funções abaixo
revoke all on table public.selo_eventos from public, anon, authenticated, service_role;
grant select on table public.selo_eventos to service_role;

-- uso interno
create or replace function public.selo_operador_ok(p_operador uuid, p_papeis text[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.equipe q
                  where q.usuario_id = p_operador and q.ativo and q.revogado_em is null
                    and q.papel = any (p_papeis));
$$;
revoke all on function public.selo_operador_ok(uuid, text[]) from public, anon, authenticated, service_role;

create or replace function public.perfis_profissional_selo_retirado()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.nivel_verificacao <> 'basico' and new.nivel_verificacao is distinct from old.nivel_verificacao
     and exists (select 1 from public.selo_eventos e
                  where e.profissional_id = new.usuario_id and e.tipo = 'retirada'
                    and not exists (select 1 from public.selo_eventos r where r.retirada_id = e.id)) then
    raise exception 'selo_retirado: há retirada do selo sem regularização (use selo_regularizar)'
      using errcode = 'restrict_violation';
  end if;
  return new;
end $$;
revoke all on function public.perfis_profissional_selo_retirado() from public, anon, authenticated, service_role;
drop trigger if exists perfis_profissional_selo_retirado_trg on public.perfis_profissional;
create trigger perfis_profissional_selo_retirado_trg before update of nivel_verificacao on public.perfis_profissional
  for each row execute function public.perfis_profissional_selo_retirado();

create or replace function public.selo_retirar(
  p_profissional uuid, p_operador uuid, p_motivo text, p_chave text, p_agora timestamptz)
returns table (resultado text, evento_id uuid, nivel text)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_atual    text;
  v_ant      record;
  v_retirada record;
  v_id       uuid;
begin
  if p_profissional is null or p_operador is null or p_agora is null
     or p_motivo is null or length(btrim(p_motivo)) < 10
     or p_chave is null or btrim(p_chave) = '' then
    raise exception 'parâmetros inválidos para selo_retirar (motivo com ao menos 10 caracteres)';
  end if;

  -- trava o perfil: serializa os eventos do mesmo profissional e a mudança de nível
  select p.nivel_verificacao into v_atual
    from public.perfis_profissional p where p.usuario_id = p_profissional for update;
  if not found then
    return query select 'profissional_nao_encontrado'::text, null::uuid, null::text;
    return;
  end if;

  select e.id, e.profissional_id, e.tipo into v_ant
    from public.selo_eventos e where e.chave_idempotencia = p_chave;
  if found then
    if v_ant.profissional_id <> p_profissional or v_ant.tipo <> 'retirada' then
      raise exception 'chave de idempotência já usada em outro evento do selo';
    end if;
    return query select 'ja_existe'::text, v_ant.id, v_atual;
    return;
  end if;
  if not public.selo_operador_ok(p_operador, array['cadastro', 'seguranca', 'administrador']) then
    return query select 'operador_invalido'::text, null::uuid, v_atual;
    return;
  end if;
  if v_atual = 'basico' then
    return query select 'sem_selo'::text, null::uuid, v_atual;
    return;
  end if;
  insert into public.selo_eventos
    (profissional_id, tipo, motivo, operador_id, nivel_anterior, nivel_novo, retirada_id, chave_idempotencia, ocorrido_em)
  values (p_profissional, 'retirada', btrim(p_motivo), p_operador, v_atual, 'basico', null, p_chave, p_agora)
  returning id into v_id;
  update public.perfis_profissional set nivel_verificacao = 'basico' where usuario_id = p_profissional;
  return query select 'ok'::text, v_id, 'basico'::text;
end;
$$;

create or replace function public.selo_pedir_reconferencia(
  p_profissional uuid, p_operador uuid, p_motivo text, p_chave text, p_agora timestamptz)
returns table (resultado text, evento_id uuid, nivel text)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_atual    text;
  v_ant      record;
  v_retirada record;
  v_id       uuid;
begin
  if p_profissional is null or p_operador is null or p_agora is null
     or p_motivo is null or length(btrim(p_motivo)) < 10
     or p_chave is null or btrim(p_chave) = '' then
    raise exception 'parâmetros inválidos para selo_pedir_reconferencia (motivo com ao menos 10 caracteres)';
  end if;

  -- trava o perfil: serializa os eventos do mesmo profissional e a mudança de nível
  select p.nivel_verificacao into v_atual
    from public.perfis_profissional p where p.usuario_id = p_profissional for update;
  if not found then
    return query select 'profissional_nao_encontrado'::text, null::uuid, null::text;
    return;
  end if;

  select e.id, e.profissional_id, e.tipo into v_ant
    from public.selo_eventos e where e.chave_idempotencia = p_chave;
  if found then
    if v_ant.profissional_id <> p_profissional or v_ant.tipo <> 'reconferencia_pedida' then
      raise exception 'chave de idempotência já usada em outro evento do selo';
    end if;
    return query select 'ja_existe'::text, v_ant.id, v_atual;
    return;
  end if;
  if not public.selo_operador_ok(p_operador, array['cadastro', 'seguranca', 'administrador']) then
    return query select 'operador_invalido'::text, null::uuid, v_atual;
    return;
  end if;
  insert into public.selo_eventos
    (profissional_id, tipo, motivo, operador_id, nivel_anterior, nivel_novo, retirada_id, chave_idempotencia, ocorrido_em)
  values (p_profissional, 'reconferencia_pedida', btrim(p_motivo), p_operador, v_atual, v_atual, null, p_chave, p_agora)
  returning id into v_id;
  return query select 'ok'::text, v_id, v_atual;
end;
$$;

create or replace function public.selo_regularizar(
  p_profissional uuid, p_operador uuid, p_motivo text, p_chave text, p_agora timestamptz)
returns table (resultado text, evento_id uuid, nivel text)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_atual    text;
  v_ant      record;
  v_retirada record;
  v_id       uuid;
begin
  if p_profissional is null or p_operador is null or p_agora is null
     or p_motivo is null or length(btrim(p_motivo)) < 10
     or p_chave is null or btrim(p_chave) = '' then
    raise exception 'parâmetros inválidos para selo_regularizar (motivo com ao menos 10 caracteres)';
  end if;

  -- trava o perfil: serializa os eventos do mesmo profissional e a mudança de nível
  select p.nivel_verificacao into v_atual
    from public.perfis_profissional p where p.usuario_id = p_profissional for update;
  if not found then
    return query select 'profissional_nao_encontrado'::text, null::uuid, null::text;
    return;
  end if;

  select e.id, e.profissional_id, e.tipo into v_ant
    from public.selo_eventos e where e.chave_idempotencia = p_chave;
  if found then
    if v_ant.profissional_id <> p_profissional or v_ant.tipo <> 'regularizacao' then
      raise exception 'chave de idempotência já usada em outro evento do selo';
    end if;
    return query select 'ja_existe'::text, v_ant.id, v_atual;
    return;
  end if;
  if not public.selo_operador_ok(p_operador, array['cadastro', 'administrador']) then
    return query select 'operador_invalido'::text, null::uuid, v_atual;
    return;
  end if;
  select e.id, e.nivel_anterior into v_retirada from public.selo_eventos e
   where e.profissional_id = p_profissional and e.tipo = 'retirada'
     and not exists (select 1 from public.selo_eventos r where r.retirada_id = e.id);
  if v_retirada.id is null then
    return query select 'sem_retirada_aberta'::text, null::uuid, v_atual;
    return;
  end if;
  insert into public.selo_eventos
    (profissional_id, tipo, motivo, operador_id, nivel_anterior, nivel_novo, retirada_id, chave_idempotencia, ocorrido_em)
  values (p_profissional, 'regularizacao', btrim(p_motivo), p_operador, v_atual, v_retirada.nivel_anterior, v_retirada.id, p_chave, p_agora)
  returning id into v_id;
  -- o evento entra antes: a trava do perfil já não vê retirada aberta
  update public.perfis_profissional set nivel_verificacao = v_retirada.nivel_anterior where usuario_id = p_profissional;
  return query select 'ok'::text, v_id, v_retirada.nivel_anterior;
end;
$$;

revoke all on function public.selo_retirar(uuid, uuid, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.selo_retirar(uuid, uuid, text, text, timestamptz) to service_role;
revoke all on function public.selo_pedir_reconferencia(uuid, uuid, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.selo_pedir_reconferencia(uuid, uuid, text, text, timestamptz) to service_role;
revoke all on function public.selo_regularizar(uuid, uuid, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.selo_regularizar(uuid, uuid, text, text, timestamptz) to service_role;

commit;
