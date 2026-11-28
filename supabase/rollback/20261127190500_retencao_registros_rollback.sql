-- Rollback de 20261127190500_retencao_registros.sql
-- RASCUNHO (DB-RETENCAO). NÃO aplicado no Supabase de produção.
-- Preserva dados: trava se houver guarda de Pedido. Volta o expurgo da 20261127190000.
-- Rodar ANTES dos rollbacks da 20261127190200, da 20261127190000 e das bases.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.pedido_guardas') is not null then
    lock table public.pedido_guardas in access exclusive mode;
    execute 'select exists (select 1 from public.pedido_guardas)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há guardas de Pedido';
    end if;
  end if;
end;
$$;

create or replace function public.expurgar_acessos_conta(p_limite integer default 5000)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_meses integer;
  v_n     integer;
  v_extra text := '';
begin
  if p_limite is null or p_limite < 1 or p_limite > 100000 then
    raise exception 'limite deve ficar entre 1 e 100000';
  end if;
  -- ordem fixa: primeiro a trava do expurgo, depois a da preservação
  perform pg_advisory_xact_lock(hashtextextended('trato.expurgo_acessos', 0));
  perform pg_advisory_xact_lock(hashtextextended('trato.preservacao_registros', 0));
  select greatest(coalesce(max(p.valor), 6), 6)::integer into v_meses
    from public.config_parametros p
    join public.config_versoes v on v.id = p.versao_id and v.status = 'vigente'
   where p.chave = 'acessos_conta_retencao_meses' and p.escopo_tipo = 'global';
  -- incidentes: tabela da 20261125225500, que pode ainda não existir
  if to_regclass('public.incidentes_seguranca') is not null then
    v_extra := ' and not exists (select 1 from public.incidentes_seguranca i '
            || 'where i.envolvido_id = a.usuario_id and i.status <> ''encerrado'')';
  end if;
  execute
    'delete from public.acessos_conta where id in (select a.id from public.acessos_conta a '
    || 'where a.ocorrido_em < now() - make_interval(months => $1) '
    || 'and not exists (select 1 from public.acessos_conta_guardas g '
    ||                'where g.usuario_id = a.usuario_id and g.encerrada_em is null) '
    || 'and not exists (select 1 from public.disputas d join public.contratos c on c.id = d.contrato_id '
    ||                'where a.usuario_id in (c.cliente_id, c.profissional_id) '
    ||                'and d.status not in (''acordo'', ''decidida'', ''cancelada''))'
    || v_extra || ' and not public.usuario_com_registros_preservados(a.usuario_id)'
    -- partes do pedido de incidente não encerrado, com ou sem medida
    || ' and not exists (select 1 from public.incidentes_seguranca i join public.pedidos p on p.id = i.pedido_id'
    ||   ' where i.status <> ''encerrado'' and (p.cliente_id = a.usuario_id or exists'
    ||     ' (select 1 from public.contratos c where c.pedido_id = p.id'
    ||     ' and a.usuario_id in (c.cliente_id, c.profissional_id))))'
    || ' order by a.ocorrido_em limit $2)'
    using v_meses, p_limite;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.expurgar_acessos_conta(integer) from public, anon, authenticated;
grant execute on function public.expurgar_acessos_conta(integer) to service_role;

drop function if exists public.pode_eliminar_registros_pedido(uuid);
drop function if exists public.retencao_pedido_situacao(uuid, timestamptz);
drop function if exists public.retencao_pedido_bloqueios(uuid);
drop function if exists public.retencao_registros_pedido_anos_vigente();
drop table if exists public.pedido_guardas;
drop function if exists public.pedido_guardas_validar();

commit;
