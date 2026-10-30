-- Desfaz a migration do fix de acesso (supabase/migrations/20261030000000_fix_acesso_storage_pedido_historico.sql).
-- Só rodar com OK do João.

-- M7: volta a regra antiga de visibilidade do pedido e do histórico.
drop policy if exists pedido_historico_select on public.pedido_historico;
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
         or exists (select 1 from public.orcamentos o
                     where o.pedido_id = p.id and o.profissional_id = (select auth.uid()))
         or exists (select 1 from public.conversas v
                     where v.pedido_id = p.id and v.profissional_id = (select auth.uid()))
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
create policy pedido_historico_select on public.pedido_historico for select to authenticated
  using (privado.pode_ver_pedido(pedido_id));
drop function if exists privado.pode_ver_historico(uuid);

-- M6: tira a restritiva que o preenchimento da migration pôs nas tabelas do agendador/push
-- (se elas existirem); as demais já nasceram com a restritiva e não são mexidas.
do $$
declare
  tabela text;
begin
  foreach tabela in array array['agendador_execucoes', 'dispositivos_push'] loop
    if to_regclass('public.' || tabela) is not null then
      execute format('drop policy if exists conta_ativa_obrigatoria on public.%I', tabela);
    end if;
  end loop;
end;
$$;
drop event trigger if exists trato_conta_ativa_tabela_nova;
drop function if exists privado.aplicar_conta_ativa_em_tabela_nova();
drop policy if exists conta_ativa_obrigatoria on storage.objects;

-- A8: devolve a leitura direta da equipe de cadastro (NÃO recomendado: sem registro de quem viu).
grant select on public.verificacao_documentos to authenticated;
create policy verificacao_documentos_select on public.verificacao_documentos for select to authenticated
  using (privado.eh_equipe('cadastro'));
create policy trato_verificacao_leitura on storage.objects for select to authenticated
  using (bucket_id = 'verificacao' and privado.eh_equipe('cadastro'));
