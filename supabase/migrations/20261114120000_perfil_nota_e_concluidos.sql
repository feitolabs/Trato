-- Nota pública e serviços concluídos do profissional passam a ser calculados pelo banco.
-- Antes ninguém atualizava estas duas colunas: o perfil mostrava "0,0 (0)" e "0 serviços
-- concluídos" mesmo com serviço concluído e avaliado. Rollback em
-- supabase/rollback/perfil_nota_e_concluidos_rollback.sql.

create or replace function public.recalcular_perfil_profissional(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.perfis_profissional p
     set servicos_concluidos = (
           select count(*)
             from public.contratos c
             join public.pedidos x on x.id = c.pedido_id
            where c.profissional_id = p_id and x.status = 'concluido'),
         nota_publica = (
           select round(avg(a.nota_geral)::numeric, 2)
             from public.avaliacoes a
            where a.avaliado_id = p_id and a.direcao = 'cliente_para_profissional')
   where p.usuario_id = p_id;
$$;
revoke all on function public.recalcular_perfil_profissional(uuid) from public, anon, authenticated;

create or replace function public.avaliacao_recalcula_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.direcao = 'cliente_para_profissional' then
    perform public.recalcular_perfil_profissional(new.avaliado_id);
  end if;
  return new;
end;
$$;
revoke all on function public.avaliacao_recalcula_perfil() from public, anon, authenticated;

create or replace function public.pedido_concluido_recalcula_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
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

create trigger avaliacoes_recalcula_perfil after insert on public.avaliacoes
  for each row execute function public.avaliacao_recalcula_perfil();

create trigger pedidos_concluido_recalcula_perfil
  after update of status on public.pedidos
  for each row when (new.status = 'concluido' and old.status is distinct from new.status)
  execute function public.pedido_concluido_recalcula_perfil();

-- Conserta o que já existe.
select public.recalcular_perfil_profissional(usuario_id) from public.perfis_profissional;
