-- Rollback de 20261127190200_fuso_e_desempate.sql
-- RASCUNHO (DB-SEG-SQL). NÃO aplicado no Supabase de produção. Não toca em dados.
-- Volta as funções da 004000 e da 061000. Rodar ANTES dos rollbacks delas.
-- A 20261127190500 depende desta: desfazer a 190500 primeiro (este rollback trava se ela existir).

begin;

do $$
begin
  if to_regprocedure('public.retencao_pedido_situacao(uuid,timestamptz)') is not null then
    raise exception 'Rollback travado: desfaça antes a 20261127190500_retencao_registros (usa dia_em_brasilia)';
  end if;
end;
$$;

create or replace function public.termos_versoes_proteger()
returns trigger
language plpgsql set search_path = ''
as $$
declare
  v_hoje date := (now() at time zone interval '-3 hours')::date;
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
   where v.vigente_desde <= (p_em at time zone interval '-3 hours')::date
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
                                   and (n.status <> 'cancelado' or n.criado_em > c.criado_em))))
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
   order by c.criado_em desc limit 1;
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

drop function if exists public.dia_em_brasilia(timestamptz);

commit;
