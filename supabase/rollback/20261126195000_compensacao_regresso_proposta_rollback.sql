-- Rollback de 20261126195000_compensacao_regresso_proposta.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA se houver proposta de regresso. Volta as 3 funções à 20261126061000.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.compensacao_propostas_regresso') is not null then
    lock table public.compensacao_propostas_regresso in access exclusive mode;
    execute 'select exists (select 1 from public.compensacao_propostas_regresso)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há propostas de regresso registradas';
    end if;
  end if;
end;
$$;

drop function if exists public.compensacao_propor_regresso(uuid, uuid, bigint, text, uuid);
drop function if exists public.compensacao_aprovar_regresso(uuid, uuid);
drop function if exists public.compensacao_recusar_regresso(uuid, uuid, text);
drop function if exists public.compensacao_avisar(uuid, uuid);
drop table if exists public.compensacao_propostas_regresso;
drop function if exists public.compensacao_propostas_validar();

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
     or not exists (select 1 from public.equipe q
                     where q.usuario_id = p_analista and q.ativo and q.revogado_em is null)
     or not exists (select 1 from public.equipe q
                     where q.usuario_id = p_aprovador and q.ativo and q.revogado_em is null
                       and q.papel in ('lider_suporte', 'administrador')) then
    return query select 'analista_invalido'::text, null::uuid, 0::bigint;
    return;
  end if;
  return query select * from public.compensacao_criar_divida(
    'regresso', p_referencia, p_contrato, null, p_valor_centavos, null, p_motivo, p_analista, p_aprovador,
    p_analista);
end;
$$;

create or replace function public.compensacao_avisar(p_divida uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_avisado timestamptz;
begin
  select d.avisado_em into v_avisado from public.compensacoes_dividas d where d.id = p_divida for update;
  if not found then
    return 'nao_encontrada';
  end if;
  if v_avisado is not null then
    return 'ja_avisada';
  end if;
  update public.compensacoes_dividas set avisado_em = now() where id = p_divida;
  return 'ok';
end;
$$;

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
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = p_analista and q.ativo and q.revogado_em is null) then
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

revoke all on function public.compensacao_registrar_regresso(uuid, uuid, bigint, text, uuid, uuid) from public, anon, authenticated;
revoke all on function public.compensacao_avisar(uuid) from public, anon, authenticated;
revoke all on function public.compensacao_cancelar(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.compensacao_registrar_regresso(uuid, uuid, bigint, text, uuid, uuid) to service_role;
grant execute on function public.compensacao_avisar(uuid) to service_role;
grant execute on function public.compensacao_cancelar(uuid, uuid, text) to service_role;
drop function if exists public.compensacao_papel_ok(uuid, text[]);

commit;
