-- ===========================================================================
-- 20261127190000_expurgo_serializado.sql
-- RASCUNHO (DB-SEG-SQL). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 14.8 e 16.3. Depende de 20261127122500 (que depende da 061200).
-- Corrida: o expurgo apagava registros que uma guarda, disputa ou incidente ainda sem commit
-- deveria proteger.
--   * criar guarda, disputa ou incidente (ou mudar status/vínculo) pega a trava
--     'trato.expurgo_acessos' COMPARTILHADA até o fim da transação (não se bloqueiam entre si);
--   * o expurgo pega a mesma trava EXCLUSIVA: espera os pendentes e depois já os enxerga.
--     A medida 'preservar_registros' continua na fila pela trava da 122500.
--   * o expurgo passa a pular as partes do pedido de incidente não encerrado, mesmo sem medida.
-- Vale em READ COMMITTED (padrão). Se a 061200 ou a 122500 rodar de novo, rodar esta de novo.
--
-- Rollback: supabase/rollback/20261127190000_expurgo_serializado_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.usuario_com_registros_preservados(uuid)') is null then
    raise exception 'Aplique antes a migration 20261127122500_preservar_registros_incidente';
  end if;
end;
$$;

create or replace function public.expurgo_acessos_enfileirar()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock_shared(hashtextextended('trato.expurgo_acessos', 0));
  return new;
end;
$$;
revoke all on function public.expurgo_acessos_enfileirar() from public, anon, authenticated, service_role;
drop trigger if exists acessos_guardas_expurgo_fila_trg on public.acessos_conta_guardas;
create trigger acessos_guardas_expurgo_fila_trg before insert on public.acessos_conta_guardas
  for each row execute function public.expurgo_acessos_enfileirar();
drop trigger if exists disputas_expurgo_fila_trg on public.disputas;
create trigger disputas_expurgo_fila_trg before insert or update of status, contrato_id on public.disputas
  for each row execute function public.expurgo_acessos_enfileirar();
drop trigger if exists incidentes_expurgo_fila_trg on public.incidentes_seguranca;
create trigger incidentes_expurgo_fila_trg before insert or update of status, pedido_id, envolvido_id on public.incidentes_seguranca
  for each row execute function public.expurgo_acessos_enfileirar();

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

commit;
