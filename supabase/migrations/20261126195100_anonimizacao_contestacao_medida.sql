-- ===========================================================================
-- 20261126195100_anonimizacao_contestacao_medida.sql
-- RASCUNHO (TERMOS-DB-174). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Provas da contestação de medida (20.5): bucket privado 'verificacao', pasta
-- contestacao-medida/. A anonimização da conta (privado.anonimizar_usuario) e os pedidos do
-- titular NÃO alcançam esses arquivos nem o texto. Depende da 20261125224600_medidas_conta.
--
-- NÃO apaga nada sozinha: são prova (Termos 14.8 e 16.3 preveem guarda). Dá o caminho:
--   lgpd_arquivos_contestacao_medida(usuario)  lista os arquivos e a pasta temporária
--   anonimizar_contestacao_medida(...)         dpo ou administrador, contestação decidida:
--        apaga texto e referências, audita e devolve os caminhos para o backend remover do
--        Storage. O prazo de guarda é decisão do João/jurídico, não está no banco.
-- As funções e regras de medida_contestacoes não mudam; os 2 gatilhos só passam a ignorar a
-- própria anonimização, que um 3º gatilho limita aos campos de texto e anexos.
-- Rollback: supabase/rollback/20261126195100_anonimizacao_contestacao_medida_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.medida_contestacoes') is null then
    raise exception 'Aplique antes a migration 20261125224600_medidas_conta';
  end if;
end;
$$;

create or replace function public.lgpd_arquivos_contestacao_medida(p_usuario uuid)
returns table (origem text, medida_id uuid, contestacao_id uuid, status text, decidida_em timestamptz,
               bucket text, caminho text)
language sql stable security definer set search_path = ''
as $$
  select 'prova'::text, c.medida_id, c.id, c.status, c.decidida_em,
         coalesce(a.item ->> 'bucket', 'verificacao'), a.item ->> 'caminho'
    from public.medida_contestacoes c
    cross join lateral jsonb_array_elements(c.anexos) as a(item)
   where c.usuario_id = p_usuario and a.item ->> 'caminho' is not null
  union all
  -- envios temporários (sem valor de prova): o backend lista e apaga tudo sob este prefixo
  select 'temporario'::text, null::uuid, null::uuid, null::text, null::timestamptz, 'verificacao'::text,
         'contestacao-medida/' || p_usuario::text || '/'
   where p_usuario is not null;
$$;

create or replace function public.anonimizar_contestacao_medida(p_contestacao uuid, p_operador uuid, p_motivo text)
returns table (resultado text, bucket text, caminho text)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_c        record;
  v_arquivos jsonb;
begin
  if p_contestacao is null or p_operador is null or p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'contestação, operador e motivo são obrigatórios';
  end if;
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = p_operador and q.ativo and q.revogado_em is null
                    and q.papel in ('dpo', 'administrador')) then
    return query select 'analista_invalido'::text, null::text, null::text;
    return;
  end if;
  select c.status, c.versao_usuario, c.anexos into v_c
    from public.medida_contestacoes c where c.id = p_contestacao for update;
  if not found then
    return query select 'nao_encontrada'::text, null::text, null::text;
    return;
  end if;
  if v_c.status not in ('mantida', 'alterada', 'revertida') then
    return query select 'nao_decidida'::text, null::text, null::text;
    return;
  end if;
  if v_c.versao_usuario = '[anonimizado]' and v_c.anexos = '[]'::jsonb then
    return query select 'ja_anonimizada'::text, null::text, null::text;
    return;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('bucket', coalesce(a.item ->> 'bucket', 'verificacao'),
                                               'caminho', a.item ->> 'caminho')), '[]'::jsonb)
    into v_arquivos
    from jsonb_array_elements(v_c.anexos) as a(item) where a.item ->> 'caminho' is not null;

  perform set_config('trato.anonimizando', 'sim', true);
  update public.medida_contestacoes
     set versao_usuario = '[anonimizado]', anexos = '[]'::jsonb,
         resposta = case when resposta is null then null else '[anonimizado]' end,
         mesmo_analista_justificativa = case when mesmo_analista_justificativa is null then null
                                             else '[anonimizado]' end
   where id = p_contestacao;
  perform set_config('trato.anonimizando', '', true);
  -- os caminhos ficam na auditoria para repetir a remoção se o Storage falhar
  perform public.registrar_auditoria(
    p_operador, 'equipe', 'dado_pessoal.anonimizacao_contestacao_medida', 'medida_contestacao', p_contestacao,
    null, jsonb_build_object('arquivos', v_arquivos), btrim(p_motivo), null, null, null);
  if v_arquivos = '[]'::jsonb then
    return query select 'ok'::text, null::text, null::text;
    return;
  end if;
  return query select 'ok'::text, a.item ->> 'bucket', a.item ->> 'caminho'
                 from jsonb_array_elements(v_arquivos) as a(item);
end;
$$;

-- Verdadeiro só dentro da função acima (roda como dona). SECURITY INVOKER de propósito: um
-- service_role que ligue a bandeira continua barrado.
create or replace function public.anonimizacao_de_contestacao_em_curso()
returns boolean
language sql volatile set search_path = ''
as $$
  select coalesce(current_setting('trato.anonimizando', true), '') = 'sim'
     and current_user = (select pg_get_userbyid(f.proowner) from pg_catalog.pg_proc f
                          where f.oid = to_regprocedure('public.anonimizar_contestacao_medida(uuid,uuid,text)'));
$$;

create or replace function public.medida_contestacoes_so_anonimizar()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if (to_jsonb(new) - 'versao_usuario' - 'anexos' - 'resposta' - 'mesmo_analista_justificativa')
     is distinct from
     (to_jsonb(old) - 'versao_usuario' - 'anexos' - 'resposta' - 'mesmo_analista_justificativa') then
    raise exception 'A anonimização só apaga texto e anexos' using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists medida_contestacoes_proteger on public.medida_contestacoes;
create trigger medida_contestacoes_proteger before update on public.medida_contestacoes
  for each row when (not public.anonimizacao_de_contestacao_em_curso())
  execute function public.proteger_colunas(
    'id', 'protocolo', 'medida_id', 'usuario_id', 'versao_usuario', 'anexos', 'canal', 'aberta_em',
    'responder_ate');
drop trigger if exists medida_contestacoes_validar_trg on public.medida_contestacoes;
drop trigger if exists medida_contestacoes_validar_insert_trg on public.medida_contestacoes;
create trigger medida_contestacoes_validar_insert_trg before insert on public.medida_contestacoes
  for each row execute function public.medida_contestacoes_validar();
create trigger medida_contestacoes_validar_trg before update on public.medida_contestacoes
  for each row when (not public.anonimizacao_de_contestacao_em_curso())
  execute function public.medida_contestacoes_validar();
drop trigger if exists medida_contestacoes_anonimizar_trg on public.medida_contestacoes;
create trigger medida_contestacoes_anonimizar_trg before update on public.medida_contestacoes
  for each row when (public.anonimizacao_de_contestacao_em_curso())
  execute function public.medida_contestacoes_so_anonimizar();

revoke all on function public.medida_contestacoes_so_anonimizar() from public, anon, authenticated, service_role;
revoke all on function public.anonimizacao_de_contestacao_em_curso() from public, anon, authenticated;
grant execute on function public.anonimizacao_de_contestacao_em_curso() to service_role;
revoke all on function public.lgpd_arquivos_contestacao_medida(uuid) from public, anon, authenticated;
revoke all on function public.anonimizar_contestacao_medida(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.lgpd_arquivos_contestacao_medida(uuid) to service_role;
grant execute on function public.anonimizar_contestacao_medida(uuid, uuid, text) to service_role;

commit;
