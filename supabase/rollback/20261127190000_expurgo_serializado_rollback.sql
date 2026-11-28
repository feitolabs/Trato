-- Rollback de 20261127190000_expurgo_serializado.sql
-- RASCUNHO (DB-SEG-SQL). NÃO aplicado no Supabase de produção. Não toca em dados.
-- Volta o expurgo da 122500 (com a corrida). Rodar ANTES dos rollbacks da 122500 e da 061200.

begin;

drop trigger if exists acessos_guardas_expurgo_fila_trg on public.acessos_conta_guardas;
drop trigger if exists disputas_expurgo_fila_trg on public.disputas;
drop trigger if exists incidentes_expurgo_fila_trg on public.incidentes_seguranca;

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
    || ' order by a.ocorrido_em limit $2)'
    using v_meses, p_limite;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.expurgar_acessos_conta(integer) from public, anon, authenticated;
grant execute on function public.expurgar_acessos_conta(integer) to service_role;

drop function if exists public.expurgo_acessos_enfileirar();

commit;
