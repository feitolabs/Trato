-- ===========================================================================
-- 20261127190200_fuso_e_desempate.sql
-- RASCUNHO (DB-SEG-SQL). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Ajustes de baixa gravidade. Depende de 20261127004000 e 20261127061000.
--   061000: dia calculado em 'America/Sao_Paulo' por public.dia_em_brasilia (antes, -3 h fixo).
--   004000: empate de criado_em entre contratos do pedido desempatado por id.
-- Mesmas assinaturas e permissões. Se a 004000 ou a 061000 rodar de novo, rodar esta de novo.
--
-- Rollback: supabase/rollback/20261127190200_fuso_e_desempate_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.termos_versao_vigente(timestamptz)') is null
     or to_regprocedure('privado.contrato_conta_no_pedido(uuid)') is null then
    raise exception 'Aplique antes as migrations 20261127004000 e 20261127061000';
  end if;
end;
$$;

-- Dia no horário de Brasília. O -3 h é só reserva para Postgres sem a base de fusos
-- (o embutido dos testes locais não a traz).
create or replace function public.dia_em_brasilia(p_em timestamptz)
returns date
language plpgsql stable set search_path = ''
as $$
begin
  return (p_em at time zone 'America/Sao_Paulo')::date;
exception when undefined_file or invalid_parameter_value then
  return (p_em at time zone interval '-3 hours')::date;
end;
$$;
revoke all on function public.dia_em_brasilia(timestamptz) from public, anon, authenticated;
grant execute on function public.dia_em_brasilia(timestamptz) to service_role;

create or replace function public.termos_versoes_proteger()
returns trigger
language plpgsql set search_path = ''
as $$
declare
  v_hoje date := public.dia_em_brasilia(now());
begin
  if tg_op = 'INSERT' then
    return new;
  end if;
  if old.vigente_desde <= v_hoje then
    raise exception 'Versão dos Termos em vigor ou passada não muda' using errcode = 'restrict_violation';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.termos_versao_vigente(p_em timestamptz default now())
returns text
language sql stable security definer set search_path = ''
as $$
  select v.versao from public.termos_versoes v
   where v.vigente_desde <= public.dia_em_brasilia(p_em)
   order by v.vigente_desde desc
   limit 1;
$$;

create or replace function privado.contrato_conta_no_pedido(contrato uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.contratos c
     where c.id = contrato
       and (c.status <> 'cancelado'
            or (not exists (select 1 from public.orcamentos o
                             where o.id = c.orcamento_id and o.status = 'expirado')
                and not exists (select 1 from public.contratos n
                                 where n.pedido_id = c.pedido_id and n.id <> c.id
                                   and (n.status <> 'cancelado' or (n.criado_em, n.id) > (c.criado_em, c.id)))))
  );
$$;

create or replace function public.pedido_concluido_recalcula_perfil()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_pro uuid;
begin
  select c.profissional_id into v_pro from public.contratos c
   where c.pedido_id = new.id and privado.contrato_conta_no_pedido(c.id)
   order by c.criado_em desc, c.id desc limit 1;
  if v_pro is not null then
    perform public.recalcular_perfil_profissional(v_pro);
  end if;
  return new;
end;
$$;

revoke all on function public.termos_versoes_proteger() from public, anon, authenticated, service_role;
revoke all on function public.termos_versao_vigente(timestamptz) from public, anon, authenticated;
grant execute on function public.termos_versao_vigente(timestamptz) to service_role;
revoke all on function privado.contrato_conta_no_pedido(uuid) from public, anon, authenticated, service_role;
revoke all on function public.pedido_concluido_recalcula_perfil() from public, anon, authenticated;

commit;
