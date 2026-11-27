-- Rollback de 20261125225600_avaliacoes_moderacao.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA se houver ocultação ou pedido de revisão. Avaliações intactas.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.avaliacao_ocultacoes') is not null then
    lock table public.avaliacao_ocultacoes in access exclusive mode;
    execute 'select exists (select 1 from public.avaliacao_ocultacoes)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há ocultações de avaliações registradas';
    end if;
  end if;
  if to_regclass('public.avaliacao_revisoes') is not null then
    lock table public.avaliacao_revisoes in access exclusive mode;
    execute 'select exists (select 1 from public.avaliacao_revisoes)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há pedidos de revisão de avaliações registrados';
    end if;
  end if;
end;
$$;

drop trigger if exists avaliacoes_status_recalcula_perfil on public.avaliacoes;
drop trigger if exists avaliacoes_travar_ocultada_trg on public.avaliacoes;
drop function if exists public.avaliacoes_travar_ocultada();

-- volta a função da 20261122100000
create or replace function public.recalcular_perfil_profissional(p_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.perfis_profissional p
     set servicos_concluidos = (
           select count(*)
             from public.contratos c
             join public.pedidos x on x.id = c.pedido_id
            where c.profissional_id = p_id and x.status = 'concluido'),
         nota_publica = (
           select round(avg(coalesce(a.nota_decimal, a.nota_geral::numeric)), 2)
             from public.avaliacoes a
            where a.avaliado_id = p_id and a.direcao = 'cliente_para_profissional')
   where p.usuario_id = p_id;
$$;
revoke all on function public.recalcular_perfil_profissional(uuid) from public, anon, authenticated;

drop table if exists public.avaliacao_revisoes;
drop table if exists public.avaliacao_ocultacoes;
drop function if exists public.avaliacao_ocultacoes_aplicar();
drop function if exists public.avaliacao_revisoes_validar();
drop sequence if exists public.avaliacao_revisoes_protocolo_seq;

commit;
