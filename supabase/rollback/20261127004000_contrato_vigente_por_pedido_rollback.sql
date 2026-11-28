-- ===========================================================================
-- Rollback de 20261127004000_contrato_vigente_por_pedido.sql
-- RASCUNHO (DB-REORCAR). NÃO aplicado no Supabase de produção.
-- Preserva dados: trava se algum pedido já tiver mais de um contrato (o UNIQUE não volta).
-- Restaura as funções (F3.8a, 20261030000000 e 20261114120000) e tira o filtro de
-- recalcular_perfil_profissional. Atenção: voltam também os acessos de contrato cancelado.
-- ===========================================================================

begin;

lock table public.contratos in access exclusive mode;

do $$
begin
  if exists (select 1 from public.contratos group by pedido_id having count(*) > 1) then
    raise exception 'Rollback travado: há pedidos com mais de um contrato';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.contratos'::regclass
                  and conname = 'contratos_pedido_id_key') then
    alter table public.contratos add constraint contratos_pedido_id_key unique (pedido_id);
  end if;
end;
$$;
drop index if exists public.contratos_um_vigente_por_pedido_idx;
drop index if exists public.contratos_pedido_idx;

do $$
declare
  v_def text := pg_get_functiondef('public.recalcular_perfil_profissional(uuid)'::regprocedure);
begin
  if position(' and privado.contrato_conta_no_pedido(c.id)' in v_def) > 0 then
    execute replace(v_def, ' and privado.contrato_conta_no_pedido(c.id)', '');
  end if;
end;
$$;

create or replace function privado.eh_profissional_do_pedido(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.contratos c
                  where c.pedido_id = pedido and c.profissional_id = (select auth.uid()));
$$;

create or replace function privado.pode_ver_pedido(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.pedidos p
     where p.id = pedido
       and (
            p.cliente_id = (select auth.uid())
         or exists (select 1 from public.contratos c
                     where c.pedido_id = p.id and c.profissional_id = (select auth.uid()))
         -- Orçou ou conversou, MAS só enquanto não há contrato com OUTRO profissional.
         or (not exists (select 1 from public.contratos c2
                          where c2.pedido_id = p.id and c2.profissional_id <> (select auth.uid()))
             and (exists (select 1 from public.orcamentos o
                           where o.pedido_id = p.id and o.profissional_id = (select auth.uid()))
                  or exists (select 1 from public.conversas v
                              where v.pedido_id = p.id and v.profissional_id = (select auth.uid()))))
         or (p.status = 'aberto'
             and (p.expira_em is null or p.expira_em > now())
             and exists (select 1 from public.usuarios cu where cu.id = p.cliente_id and cu.status = 'ativo')
             and exists (select 1 from public.perfis_profissional pp
                          where pp.usuario_id = (select auth.uid()) and pp.status = 'aprovado')
             and exists (select 1 from public.profissional_categorias pc
                          where pc.profissional_id = (select auth.uid())
                            and pc.categoria_id = p.categoria_id and pc.suspensa_em is null)
             and exists (select 1 from public.profissional_regioes pr
                          where pr.profissional_id = (select auth.uid())
                            and pr.cidade_id = p.cidade_id
                            and (pr.bairro is null or lower(pr.bairro) = lower(coalesce(p.bairro, '')))))
         or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador',
                              'financeiro', 'seguranca')
       )
  );
$$;

create or replace function privado.pode_ver_historico(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.pedidos p
     where p.id = pedido
       and (
            p.cliente_id = (select auth.uid())
         or exists (select 1 from public.contratos c
                     where c.pedido_id = p.id and c.profissional_id = (select auth.uid()))
         or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador',
                              'financeiro', 'seguranca')
       )
  );
$$;

create or replace function public.pedido_concluido_recalcula_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pro uuid;
begin
  select c.profissional_id into v_pro from public.contratos c where c.pedido_id = new.id;
  if v_pro is not null then
    perform public.recalcular_perfil_profissional(v_pro);
  end if;
  return new;
end;
$$;
revoke all on function public.pedido_concluido_recalcula_perfil() from public, anon, authenticated;

drop function if exists privado.contrato_conta_no_pedido(uuid);

commit;
