-- ===========================================================================
-- 20261126195000_compensacao_regresso_proposta.sql
-- RASCUNHO (TERMOS-DB-174). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2, 17.4: o regresso é proposto por uma pessoa e aprovado por OUTRA (líder de
-- suporte ou administrador), que registra a dívida uma única vez. Depende da 20261126061000.
--
-- Papéis conferidos no banco (equipe ativa e não revogada):
--   propor / analista do regresso / avisar: mediador, lider_suporte, seguranca, administrador
--   aprovar, recusar e cancelar:            lider_suporte, administrador
-- MUDA ASSINATURA: compensacao_avisar(uuid) deixa de existir; agora (p_divida, p_operador).
-- compensacao_registrar_regresso (direta, duas pessoas) continua existindo, com os papéis.
-- RLS ligada, sem policy; service_role só LÊ; escrita só pelas funções. Nenhum dado alterado.
-- Rollback: supabase/rollback/20261126195000_compensacao_regresso_proposta_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.compensacoes_dividas') is null then
    raise exception 'Aplique antes a migration 20261126061000_compensacao_repasses';
  end if;
end;
$$;

create table if not exists public.compensacao_propostas_regresso (
  id               uuid primary key default gen_random_uuid(),
  contrato_id      uuid not null references public.contratos (id) on delete restrict,
  pedido_id        uuid not null references public.pedidos (id) on delete restrict,
  profissional_id  uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  referencia       uuid not null,
  valor_centavos   bigint not null check (valor_centavos > 0),
  motivo           text not null check (btrim(motivo) <> ''),
  status           text not null default 'proposta' check (status in ('proposta', 'aprovada', 'recusada')),
  proposta_por     uuid not null references public.equipe (usuario_id) on delete restrict,
  proposta_em      timestamptz not null default now(),
  decidida_por     uuid references public.equipe (usuario_id) on delete restrict,
  decidida_em      timestamptz,
  motivo_decisao   text,
  divida_id        uuid unique references public.compensacoes_dividas (id) on delete restrict,
  constraint propostas_regresso_decisao_check check (
    case status
      when 'proposta' then decidida_por is null and decidida_em is null and motivo_decisao is null
                           and divida_id is null
      when 'aprovada' then decidida_por is not null and decidida_em is not null and divida_id is not null
                           and decidida_por <> proposta_por
      else decidida_por is not null and decidida_em is not null and divida_id is null
           and btrim(coalesce(motivo_decisao, '')) <> ''
    end)
);
-- uma proposta viva por referência (a recusada libera nova proposta)
create unique index if not exists ux_propostas_regresso_referencia
  on public.compensacao_propostas_regresso (referencia) where status <> 'recusada';
create index if not exists ix_propostas_regresso_status
  on public.compensacao_propostas_regresso (status, proposta_em);

create or replace function public.compensacao_papel_ok(p_usuario uuid, p_papeis text[])
returns boolean
language sql volatile security definer set search_path = ''
as $$
  select exists (select 1 from public.equipe q
                  where q.usuario_id = p_usuario and q.ativo and q.revogado_em is null
                    and q.papel = any (p_papeis));
$$;

create or replace function public.compensacao_propor_regresso(
  p_contrato uuid, p_referencia uuid, p_valor_centavos bigint, p_motivo text, p_operador uuid)
returns table (resultado text, proposta_id uuid)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ctr   record;
  v_exist record;
  v_id    uuid;
begin
  if p_contrato is null or p_referencia is null or p_valor_centavos is null or p_valor_centavos <= 0
     or p_motivo is null or btrim(p_motivo) = '' or p_operador is null then
    raise exception 'contrato, referência, valor positivo, motivo e operador são obrigatórios';
  end if;
  if not public.compensacao_papel_ok(p_operador, '{mediador,lider_suporte,seguranca,administrador}') then
    return query select 'analista_invalido'::text, null::uuid;
    return;
  end if;
  select c.pedido_id, c.profissional_id into v_ctr from public.contratos c where c.id = p_contrato;
  if not found then
    return query select 'contrato_nao_encontrado'::text, null::uuid;
    return;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('regresso:' || p_referencia::text, 0));
  select x.id, x.contrato_id, x.valor_centavos into v_exist
    from public.compensacao_propostas_regresso x
   where x.referencia = p_referencia and x.status <> 'recusada';
  if found then
    return query select case when v_exist.contrato_id = p_contrato and v_exist.valor_centavos = p_valor_centavos
                             then 'ja_proposta' else 'conflito' end, v_exist.id;
    return;
  end if;
  if exists (select 1 from public.compensacoes_dividas d
              where d.origem_tipo = 'regresso' and d.origem_id = p_referencia) then
    return query select 'ja_registrada'::text, null::uuid;
    return;
  end if;
  insert into public.compensacao_propostas_regresso
    (contrato_id, pedido_id, profissional_id, referencia, valor_centavos, motivo, proposta_por)
  values (p_contrato, v_ctr.pedido_id, v_ctr.profissional_id, p_referencia, p_valor_centavos,
          btrim(p_motivo), p_operador)
  returning id into v_id;
  perform public.registrar_auditoria(
    p_operador, 'equipe', 'financeiro.regresso_proposto', 'compensacao_proposta', v_id, null,
    jsonb_build_object('contrato_id', p_contrato, 'referencia', p_referencia, 'valor_centavos', p_valor_centavos),
    btrim(p_motivo), null, null, null);
  return query select 'ok'::text, v_id;
end;
$$;

create or replace function public.compensacao_aprovar_regresso(p_proposta uuid, p_operador uuid)
returns table (resultado text, divida_id uuid, maximo_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_contrato uuid;
  v_p        record;
  v_r        record;
begin
  if p_proposta is null or p_operador is null then
    raise exception 'proposta e operador são obrigatórios';
  end if;
  if not public.compensacao_papel_ok(p_operador, '{lider_suporte,administrador}') then
    return query select 'analista_invalido'::text, null::uuid, 0::bigint;
    return;
  end if;
  select x.contrato_id into v_contrato from public.compensacao_propostas_regresso x where x.id = p_proposta;
  if not found then
    return query select 'nao_encontrada'::text, null::uuid, 0::bigint;
    return;
  end if;
  -- travas: contrato (como o resto da compensação), depois a proposta
  perform 1 from public.contratos c where c.id = v_contrato for update;
  select x.* into v_p from public.compensacao_propostas_regresso x where x.id = p_proposta for update;
  if v_p.status = 'aprovada' then
    return query select 'ja_aprovada'::text, v_p.divida_id, v_p.valor_centavos;
    return;
  end if;
  if v_p.status = 'recusada' then
    return query select 'ja_recusada'::text, null::uuid, 0::bigint;
    return;
  end if;
  if v_p.proposta_por = p_operador then
    return query select 'mesma_pessoa'::text, null::uuid, 0::bigint;
    return;
  end if;
  -- quem propôs precisa continuar com papel de análise na hora da aprovação
  if not public.compensacao_papel_ok(v_p.proposta_por, '{mediador,lider_suporte,seguranca,administrador}') then
    return query select 'proponente_invalido'::text, null::uuid, 0::bigint;
    return;
  end if;
  select * into v_r from public.compensacao_criar_divida(
    'regresso', v_p.referencia, v_p.contrato_id, null, v_p.valor_centavos, null, v_p.motivo,
    v_p.proposta_por, p_operador, p_operador);
  if v_r.resultado <> 'ok' then
    -- 'ja_registrada': a referência já virou dívida por outro caminho; a proposta não a assume
    return query select case when v_r.resultado = 'ja_registrada' then 'conflito' else v_r.resultado end,
                        null::uuid, coalesce(v_r.maximo_centavos, 0);
    return;
  end if;
  update public.compensacao_propostas_regresso
     set status = 'aprovada', decidida_por = p_operador, decidida_em = now(), divida_id = v_r.divida_id
   where id = p_proposta;
  perform public.registrar_auditoria(
    p_operador, 'equipe', 'financeiro.regresso_aprovado', 'compensacao_proposta', p_proposta,
    jsonb_build_object('status', 'proposta', 'proposta_por', v_p.proposta_por),
    jsonb_build_object('status', 'aprovada', 'divida_id', v_r.divida_id, 'valor_centavos', v_p.valor_centavos),
    v_p.motivo, null, null, null);
  return query select 'ok'::text, v_r.divida_id, v_r.maximo_centavos;
end;
$$;

create or replace function public.compensacao_recusar_regresso(p_proposta uuid, p_operador uuid, p_motivo text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_status text;
begin
  if p_proposta is null or p_operador is null or p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'proposta, operador e motivo são obrigatórios';
  end if;
  if not public.compensacao_papel_ok(p_operador, '{lider_suporte,administrador}') then
    return 'analista_invalido';
  end if;
  select x.status into v_status from public.compensacao_propostas_regresso x where x.id = p_proposta for update;
  if not found then
    return 'nao_encontrada';
  end if;
  if v_status = 'recusada' then
    return 'ja_recusada';
  end if;
  if v_status = 'aprovada' then
    return 'ja_aprovada';
  end if;
  update public.compensacao_propostas_regresso
     set status = 'recusada', decidida_por = p_operador, decidida_em = now(), motivo_decisao = btrim(p_motivo)
   where id = p_proposta;
  perform public.registrar_auditoria(
    p_operador, 'equipe', 'financeiro.regresso_recusado', 'compensacao_proposta', p_proposta,
    jsonb_build_object('status', 'proposta'), jsonb_build_object('status', 'recusada'),
    btrim(p_motivo), null, null, null);
  return 'ok';
end;
$$;

-- Aviso com operador (a versão sem operador sai: não dá para conferir papel).
drop function if exists public.compensacao_avisar(uuid);
create or replace function public.compensacao_avisar(p_divida uuid, p_operador uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_avisado timestamptz;
begin
  if p_divida is null or p_operador is null then
    raise exception 'dívida e operador são obrigatórios';
  end if;
  if not public.compensacao_papel_ok(p_operador, '{mediador,lider_suporte,seguranca,administrador}') then
    return 'analista_invalido';
  end if;
  select d.avisado_em into v_avisado from public.compensacoes_dividas d where d.id = p_divida for update;
  if not found then
    return 'nao_encontrada';
  end if;
  if v_avisado is not null then
    return 'ja_avisada';
  end if;
  update public.compensacoes_dividas set avisado_em = now() where id = p_divida;
  perform public.registrar_auditoria(
    p_operador, 'equipe', 'financeiro.compensacao_avisada', 'compensacao', p_divida, null, null,
    'Aviso ao profissional (Termos 17.4)', null, null, null);
  return 'ok';
end;
$$;

-- Regresso direto: agora também confere o papel do analista.
create or replace function public.compensacao_registrar_regresso(
  p_contrato uuid, p_referencia uuid, p_valor_centavos bigint, p_motivo text, p_analista uuid, p_aprovador uuid)
returns table (resultado text, divida_id uuid, maximo_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if p_contrato is null or p_referencia is null or p_valor_centavos is null or p_valor_centavos <= 0
     or p_motivo is null or btrim(p_motivo) = '' or p_analista is null or p_aprovador is null then
    raise exception 'contrato, referência, valor positivo, motivo, analista e aprovador são obrigatórios';
  end if;
  if p_analista = p_aprovador
     or not public.compensacao_papel_ok(p_analista, '{mediador,lider_suporte,seguranca,administrador}')
     or not public.compensacao_papel_ok(p_aprovador, '{lider_suporte,administrador}') then
    return query select 'analista_invalido'::text, null::uuid, 0::bigint;
    return;
  end if;
  return query select * from public.compensacao_criar_divida(
    'regresso', p_referencia, p_contrato, null, p_valor_centavos, null, p_motivo, p_analista, p_aprovador,
    p_analista);
end;
$$;

-- Cancelar: só líder de suporte ou administrador.
create or replace function public.compensacao_cancelar(p_divida uuid, p_analista uuid, p_motivo text)
returns table (resultado text, devolvido_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_d      record;
  v_total  bigint := 0;
  r        record;
begin
  if p_divida is null or p_analista is null or p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'dívida, analista e motivo são obrigatórios';
  end if;
  -- cancelar devolve dinheiro: só líder de suporte ou administrador
  if not public.compensacao_papel_ok(p_analista, '{lider_suporte,administrador}') then
    return query select 'analista_invalido'::text, 0::bigint;
    return;
  end if;
  select d.contrato_id, d.profissional_id into v_d from public.compensacoes_dividas d where d.id = p_divida;
  if not found then
    return query select 'nao_encontrada'::text, 0::bigint;
    return;
  end if;
  -- o estorno escreve nos contratos já compensados, e compensacao_aplicar segura o contrato
  -- antes do profissional: travar todos os contratos dele PRIMEIRO, em ordem, evita deadlock
  perform 1 from public.contratos c where c.profissional_id = v_d.profissional_id order by c.id for update;
  perform pg_advisory_xact_lock(hashtextextended('compensacao:' || v_d.profissional_id::text, 0));
  select d.contrato_id, d.profissional_id, d.status, d.valor_centavos, d.disputa_id into v_d
    from public.compensacoes_dividas d where d.id = p_divida for update;
  if v_d.status = 'cancelada' then
    return query select 'ja_cancelada'::text, 0::bigint;
    return;
  end if;

  for r in select a.lancamento_id, a.contrato_id, a.valor_centavos from public.compensacoes_aplicadas a
            where a.divida_id = p_divida
              and not exists (select 1 from public.lancamentos e where e.estorna_id = a.lancamento_id)
            order by a.criada_em, a.id
  loop
    perform public.compensacao_lancar(
      r.contrato_id, 'estorno',
      public.compensacao_conta('a_compensar', v_d.profissional_id),
      public.compensacao_conta('liberado', v_d.profissional_id),
      r.valor_centavos, 'comp/estorno/' || r.lancamento_id::text,
      'Estorno de compensação contestada', v_d.disputa_id, r.lancamento_id, p_analista);
    v_total := v_total + r.valor_centavos;
  end loop;
  perform public.compensacao_lancar(
    v_d.contrato_id, 'reembolso',
    public.compensacao_conta('taxa_trato', null),
    public.compensacao_conta('a_compensar', v_d.profissional_id),
    v_d.valor_centavos, 'comp/assume/' || p_divida::text,
    'Dívida cancelada: o Trato assume o reembolso', v_d.disputa_id, null, p_analista);
  update public.compensacoes_dividas
     set status = 'cancelada', cancelada_em = now(), cancelada_por = p_analista,
         motivo_cancelamento = btrim(p_motivo)
   where id = p_divida;
  perform public.registrar_auditoria(
    p_analista, 'equipe', 'financeiro.compensacao_cancelada', 'compensacao', p_divida,
    jsonb_build_object('status', v_d.status), jsonb_build_object('devolvido_centavos', v_total),
    btrim(p_motivo), null, null, null);
  return query select 'ok'::text, v_total;
end;
$$;

create or replace function public.compensacao_propostas_validar()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.status <> 'proposta' and new is distinct from old then
    raise exception 'Proposta já decidida não muda' using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists propostas_regresso_validar_trg on public.compensacao_propostas_regresso;
create trigger propostas_regresso_validar_trg before update on public.compensacao_propostas_regresso
  for each row execute function public.compensacao_propostas_validar();
drop trigger if exists propostas_regresso_proteger on public.compensacao_propostas_regresso;
create trigger propostas_regresso_proteger before update on public.compensacao_propostas_regresso
  for each row execute function public.proteger_colunas(
    'id', 'contrato_id', 'pedido_id', 'profissional_id', 'referencia', 'valor_centavos', 'motivo',
    'proposta_por', 'proposta_em');
drop trigger if exists propostas_regresso_sem_delete on public.compensacao_propostas_regresso;
create trigger propostas_regresso_sem_delete before delete on public.compensacao_propostas_regresso
  for each row execute function public.bloquear_alteracao();
drop trigger if exists propostas_regresso_sem_truncate on public.compensacao_propostas_regresso;
create trigger propostas_regresso_sem_truncate before truncate on public.compensacao_propostas_regresso
  for each statement execute function public.bloquear_alteracao();

alter table public.compensacao_propostas_regresso enable row level security;
revoke all on table public.compensacao_propostas_regresso from public, anon, authenticated, service_role;
grant select on table public.compensacao_propostas_regresso to service_role;

revoke all on function public.compensacao_papel_ok(uuid, text[]) from public, anon, authenticated, service_role;
revoke all on function public.compensacao_propostas_validar() from public, anon, authenticated, service_role;
revoke all on function public.compensacao_propor_regresso(uuid, uuid, bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.compensacao_aprovar_regresso(uuid, uuid) from public, anon, authenticated;
revoke all on function public.compensacao_recusar_regresso(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.compensacao_avisar(uuid, uuid) from public, anon, authenticated;
revoke all on function public.compensacao_registrar_regresso(uuid, uuid, bigint, text, uuid, uuid) from public, anon, authenticated;
revoke all on function public.compensacao_cancelar(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.compensacao_propor_regresso(uuid, uuid, bigint, text, uuid) to service_role;
grant execute on function public.compensacao_aprovar_regresso(uuid, uuid) to service_role;
grant execute on function public.compensacao_recusar_regresso(uuid, uuid, text) to service_role;
grant execute on function public.compensacao_avisar(uuid, uuid) to service_role;
grant execute on function public.compensacao_registrar_regresso(uuid, uuid, bigint, text, uuid, uuid) to service_role;
grant execute on function public.compensacao_cancelar(uuid, uuid, text) to service_role;

commit;
