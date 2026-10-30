-- Fix de acesso: A8, M6 e M7 da revisão de segurança (docs/revisao-seguranca.md).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Depende da F3.8a, F3.8b e F3.8c. Reversão: supabase/rollback/fix_acesso_rollback.sql
-- Migration NOVA: nenhuma migration já aplicada foi alterada.
--
--  A8  A equipe de cadastro deixa de ler documentos/selfie DIRETO (Storage e tabela). A leitura passa
--      a ser só por URL assinada curta gerada pelo backend (service_role ignora a RLS), com motivo e
--      registro de quem viu na auditoria (rota POST /v1/admin/verificacoes/{id}/documentos/{doc}/url).
--  M6  Conta bloqueada/anonimizada também não lê o Storage (policy restritiva em storage.objects)
--      e toda tabela NOVA de public nasce com a policy restritiva (gatilho de evento).
--  M7  Quem perdeu o orçamento (contrato fechado com OUTRO profissional) não vê mais o pedido, e o
--      histórico do pedido (prova em JSON: motivo, localização, foto do check-in) é só das partes
--      e da equipe.

-- ---------------------------------------------------------------------------
-- A8. Documentos de verificação: sem leitura direta pela equipe
-- ---------------------------------------------------------------------------
drop policy if exists trato_verificacao_leitura on storage.objects;
drop policy if exists verificacao_documentos_select on public.verificacao_documentos;
-- Sem policy e sem grant: nem pelo PostgREST. O backend (service_role) lê e assina a URL de 60 s.
revoke select on public.verificacao_documentos from authenticated;

-- ---------------------------------------------------------------------------
-- M6. Conta bloqueada não lê o Storage; tabelas futuras nascem com a policy restritiva
-- ---------------------------------------------------------------------------
create policy conta_ativa_obrigatoria on storage.objects as restrictive for select to authenticated
  using ((select privado.conta_ativa()));

-- Tabela de public criada DEPOIS desta migration (por qualquer papel) ganha RLS e a restritiva.
create or replace function privado.aplicar_conta_ativa_em_tabela_nova()
returns event_trigger
language plpgsql security definer set search_path = ''
as $$
declare
  obj record;
begin
  for obj in
    select * from pg_event_trigger_ddl_commands()
     where command_tag in ('CREATE TABLE', 'CREATE TABLE AS') and schema_name = 'public'
  loop
    execute format('alter table %s enable row level security', obj.object_identity);
    if not exists (select 1 from pg_policies
                    where schemaname = 'public'
                      and tablename = split_part(obj.object_identity, '.', 2)
                      and policyname = 'conta_ativa_obrigatoria') then
      execute format(
        'create policy conta_ativa_obrigatoria on %s as restrictive for select to authenticated '
        'using ((select privado.conta_ativa()))', obj.object_identity);
    end if;
  end loop;
end;
$$;
revoke all on function privado.aplicar_conta_ativa_em_tabela_nova() from public, anon, authenticated;

create event trigger trato_conta_ativa_tabela_nova on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS')
  execute function privado.aplicar_conta_ativa_em_tabela_nova();

-- Tabelas que já existem e ficaram sem a restritiva (criadas fora das migrations).
do $$
declare
  tabela text;
begin
  for tabela in
    select t.tablename from pg_tables t
     where t.schemaname = 'public'
       and not exists (select 1 from pg_policies p
                        where p.schemaname = 'public' and p.tablename = t.tablename
                          and p.policyname = 'conta_ativa_obrigatoria')
  loop
    execute format(
      'create policy conta_ativa_obrigatoria on public.%I as restrictive for select to authenticated '
      'using ((select privado.conta_ativa()))', tabela);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- M7. Perdedor do orçamento não vê mais o pedido; histórico só das partes e da equipe
-- ---------------------------------------------------------------------------
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

-- Histórico do pedido: cliente, profissional do contrato e equipe. Quem só orçou NÃO lê.
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
revoke all on function privado.pode_ver_historico(uuid) from public, anon;
grant execute on function privado.pode_ver_historico(uuid) to authenticated, service_role;

drop policy pedido_historico_select on public.pedido_historico;
create policy pedido_historico_select on public.pedido_historico for select to authenticated
  using (privado.pode_ver_historico(pedido_id));
