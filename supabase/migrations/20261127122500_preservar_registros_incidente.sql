-- ===========================================================================
-- 20261127122500_preservar_registros_incidente.sql
-- RASCUNHO (DB-LOTE-A). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 9.6 (preservar os registros do Pedido enquanto o Trato apura).
-- Depende de 224500, 224600, 225500, 225700, 195100 e 20261127061200.
--
-- Vale enquanto o incidente NÃO está encerrado e tem medida 'preservar_registros'.
-- Protegidos: cliente e profissional do pedido do incidente (qualquer contrato dele) e o
-- envolvido. O relator que não é parte do pedido não fica preso.
-- Como: gatilhos recusam o passo que apaga ou anonimiza (SQLSTATE 23001, mensagem começando
-- com 'registros_preservados'); a transação inteira volta atrás, inclusive os deletes da função.
--   privado.anonimizar_usuario, anonimizar_chamado, anonimizar_pedido_titular,
--   anonimizar_contestacao_medida: passam a dar esse erro.
--   expurgar_acessos_conta: não dá erro; pula as contas protegidas.
-- Uma trava de transação põe em fila a marcação da preservação e quem apaga.
--
-- Rollback: supabase/rollback/20261127122500_preservar_registros_incidente_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.incidente_medidas') is null or to_regclass('public.acessos_conta') is null
     or to_regclass('public.lgpd_pedidos_titular') is null or to_regclass('public.chamado_mensagens') is null
     or to_regprocedure('public.anonimizar_contestacao_medida(uuid,uuid,text)') is null then
    raise exception 'Aplique antes as migrations 224500, 224600, 225500, 225700, 195100 e 20261127061200';
  end if;
end;
$$;

create or replace function public.usuario_com_registros_preservados(p_usuario uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.incidentes_seguranca i
     where i.status <> 'encerrado'
       and exists (select 1 from public.incidente_medidas m
                    where m.incidente_id = i.id and m.tipo = 'preservar_registros')
       and (i.envolvido_id = p_usuario
            or exists (select 1 from public.pedidos p
                        where p.id = i.pedido_id and p.cliente_id = p_usuario)
            or exists (select 1 from public.contratos c
                        where c.pedido_id = i.pedido_id
                          and p_usuario in (c.cliente_id, c.profissional_id))));
$$;
revoke all on function public.usuario_com_registros_preservados(uuid) from public, anon, authenticated;
grant execute on function public.usuario_com_registros_preservados(uuid) to service_role;

create or replace function public.pedido_com_registros_preservados(p_pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.incidentes_seguranca i
      join public.incidente_medidas m on m.incidente_id = i.id
     where i.pedido_id = p_pedido and i.status <> 'encerrado' and m.tipo = 'preservar_registros');
$$;
revoke all on function public.pedido_com_registros_preservados(uuid) from public, anon, authenticated;
grant execute on function public.pedido_com_registros_preservados(uuid) to service_role;

-- Argumento do gatilho: de onde tirar o dono do registro.
create or replace function public.registros_preservados_barrar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_usuario uuid;
  v_pedido  uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('trato.preservacao_registros', 0));
  if tg_argv[0] = 'usuario' then
    v_usuario := (to_jsonb(old) ->> 'id')::uuid;
  elsif tg_argv[0] = 'dono' then
    v_usuario := (to_jsonb(old) ->> 'usuario_id')::uuid;
    v_pedido := (to_jsonb(old) ->> 'pedido_id')::uuid;
  else  -- mensagem de chamado
    select c.usuario_id, c.pedido_id into v_usuario, v_pedido
      from public.chamados c where c.id = (to_jsonb(old) ->> 'chamado_id')::uuid;
  end if;
  if public.usuario_com_registros_preservados(v_usuario)
     or public.pedido_com_registros_preservados(v_pedido) then
    raise exception 'registros_preservados: há incidente não encerrado com preservação de registros (Termos 9.6)'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.registros_preservados_barrar() from public, anon, authenticated, service_role;

create or replace function public.incidente_preservacao_enfileirar()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('trato.preservacao_registros', 0));
  return new;
end;
$$;
revoke all on function public.incidente_preservacao_enfileirar() from public, anon, authenticated, service_role;
drop trigger if exists incidente_preservacao_enfileirar_trg on public.incidente_medidas;
create trigger incidente_preservacao_enfileirar_trg before insert on public.incidente_medidas
  for each row when (new.tipo = 'preservar_registros')
  execute function public.incidente_preservacao_enfileirar();

drop trigger if exists usuarios_preservacao_trg on public.usuarios;
create trigger usuarios_preservacao_trg before update on public.usuarios
  for each row when (new.status = 'anonimizado' and old.status is distinct from 'anonimizado')
  execute function public.registros_preservados_barrar('usuario');
drop trigger if exists chamados_preservacao_trg on public.chamados;
create trigger chamados_preservacao_trg before update on public.chamados
  for each row when (new.assunto = '[anonimizado]' and old.assunto is distinct from new.assunto)
  execute function public.registros_preservados_barrar('dono');
drop trigger if exists chamado_mensagens_preservacao_trg on public.chamado_mensagens;
create trigger chamado_mensagens_preservacao_trg before update on public.chamado_mensagens
  for each row execute function public.registros_preservados_barrar('mensagem');
drop trigger if exists lgpd_titular_preservacao_trg on public.lgpd_pedidos_titular;
create trigger lgpd_titular_preservacao_trg before update on public.lgpd_pedidos_titular
  for each row when (new.descricao = '[anonimizado]' and old.descricao is distinct from new.descricao)
  execute function public.registros_preservados_barrar('dono');
drop trigger if exists medida_contestacoes_preservacao_trg on public.medida_contestacoes;
create trigger medida_contestacoes_preservacao_trg before update on public.medida_contestacoes
  for each row when (new.versao_usuario = '[anonimizado]'
                     and (old.versao_usuario is distinct from new.versao_usuario
                          or old.anexos is distinct from new.anexos))
  execute function public.registros_preservados_barrar('dono');

-- Igual à da 20261127061200, mais a trava e a exclusão das contas preservadas.
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

commit;
