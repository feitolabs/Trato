-- Rollback de 20261127122500_preservar_registros_incidente.sql
-- RASCUNHO (DB-LOTE-A). NÃO aplicado no Supabase de produção.
-- Não apaga dados. Trava enquanto houver preservação em vigor (tirar a proteção deixaria apagar).
-- Restaura expurgar_acessos_conta como na 20261127061200. Rodar ANTES do rollback dela.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.incidente_medidas') is not null then
    lock table public.incidente_medidas in share mode;
    select exists (select 1 from public.incidentes_seguranca i
                     join public.incidente_medidas m on m.incidente_id = i.id
                    where i.status <> 'encerrado' and m.tipo = 'preservar_registros') into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há preservação de registros em incidente não encerrado';
    end if;
  end if;
end;
$$;

drop trigger if exists incidente_preservacao_enfileirar_trg on public.incidente_medidas;
drop trigger if exists usuarios_preservacao_trg on public.usuarios;
drop trigger if exists chamados_preservacao_trg on public.chamados;
drop trigger if exists chamado_mensagens_preservacao_trg on public.chamado_mensagens;
drop trigger if exists lgpd_titular_preservacao_trg on public.lgpd_pedidos_titular;
drop trigger if exists medida_contestacoes_preservacao_trg on public.medida_contestacoes;

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
    || v_extra || ' order by a.ocorrido_em limit $2)'
    using v_meses, p_limite;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.expurgar_acessos_conta(integer) from public, anon, authenticated;
grant execute on function public.expurgar_acessos_conta(integer) to service_role;

drop function if exists public.registros_preservados_barrar();
drop function if exists public.incidente_preservacao_enfileirar();
drop function if exists public.usuario_com_registros_preservados(uuid);
drop function if exists public.pedido_com_registros_preservados(uuid);

commit;
