-- ===========================================================================
-- 20261127004000_contrato_vigente_por_pedido.sql
-- RASCUNHO (DB-REORCAR). NÃO aplicada no Supabase de produção. Aguarda OK do João
-- (o OK dado vale só para arquivo e Postgres local).
-- Termos v1.2: 5.2 e 6.3. Depois que o pagamento expira o pedido volta a 'aberto' e precisa
-- aceitar outro orçamento; hoje contratos.pedido_id é UNIQUE e o contrato não se apaga.
--
--   1. Troca o UNIQUE de contratos.pedido_id por índice único parcial: um contrato NÃO
--      CANCELADO por pedido. Acrescenta índice comum em pedido_id para as buscas.
--   2. privado.contrato_conta_no_pedido(contrato): contrato não cancelado conta. Cancelado só
--      conta se o orçamento dele não está 'expirado' E não há outro contrato do pedido não
--      cancelado ou mais novo. Contrato caído por pagamento expirado ou substituído não dá
--      acesso nem conta serviço; pedido cancelado do jeito comum continua como hoje.
--   3. Usa essa regra em pode_ver_pedido, pode_ver_historico, eh_profissional_do_pedido e
--      recalcular_perfil_profissional; o gatilho de pedido concluído pega o contrato vigente.
--
-- Nenhum dado é alterado. Pedidos já presos: arquivo separado, com OK próprio:
--   supabase/consultas/acerto_pedidos_presos_reorcar.sql
-- ORDEM: se a 20261125225600 for aplicada DEPOIS desta, ela recria
-- recalcular_perfil_profissional sem o filtro: rodar esta de novo (é idempotente).
-- O BACKEND precisa passar a filtrar o contrato vigente ANTES de qualquer pedido ter dois.
--
-- Rollback: supabase/rollback/20261127004000_contrato_vigente_por_pedido_rollback.sql
-- ===========================================================================

begin;

alter table public.contratos drop constraint if exists contratos_pedido_id_key;
create unique index if not exists contratos_um_vigente_por_pedido_idx
  on public.contratos (pedido_id) where status <> 'cancelado';
create index if not exists contratos_pedido_idx on public.contratos (pedido_id);

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
-- Usada só dentro de funções SECURITY DEFINER: ninguém precisa de EXECUTE.
revoke all on function privado.contrato_conta_no_pedido(uuid) from public, anon, authenticated, service_role;

create or replace function privado.eh_profissional_do_pedido(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.contratos c
                  where c.pedido_id = pedido and c.profissional_id = (select auth.uid())
                    and privado.contrato_conta_no_pedido(c.id));
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
                     where c.pedido_id = p.id and c.profissional_id = (select auth.uid())
                       and privado.contrato_conta_no_pedido(c.id))
         -- Orçou ou conversou, MAS só enquanto não há contrato com OUTRO profissional.
         or (not exists (select 1 from public.contratos c2
                          where c2.pedido_id = p.id and c2.profissional_id <> (select auth.uid())
                            and privado.contrato_conta_no_pedido(c2.id))
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
                     where c.pedido_id = p.id and c.profissional_id = (select auth.uid())
                       and privado.contrato_conta_no_pedido(c.id))
         or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador',
                              'financeiro', 'seguranca')
       )
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
revoke all on function public.pedido_concluido_recalcula_perfil() from public, anon, authenticated;

-- recalcular_perfil_profissional tem versões diferentes (20261122100000 ou 20261125225600):
-- acrescenta só o filtro ao corpo que estiver no banco.
do $$
declare
  v_def  text := pg_get_functiondef('public.recalcular_perfil_profissional(uuid)'::regprocedure);
  v_alvo constant text := 'c.profissional_id = p_id and x.status = ''concluido''';
begin
  if position('contrato_conta_no_pedido' in v_def) > 0 then
    return;
  end if;
  if position(v_alvo in v_def) = 0 then
    raise exception 'recalcular_perfil_profissional mudou: revisar esta migration';
  end if;
  execute replace(v_def, v_alvo, v_alvo || ' and privado.contrato_conta_no_pedido(c.id)');
end;
$$;

commit;
