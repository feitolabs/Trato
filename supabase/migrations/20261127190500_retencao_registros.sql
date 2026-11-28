-- ===========================================================================
-- 20261127190500_retencao_registros.sql
-- RASCUNHO (DB-RETENCAO). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 14.8 e 16.3: registros de Pedidos, pagamentos, mensagens e provas por [5] anos
-- da conclusão do Pedido; com Disputa, processo ou investigação em andamento, até o fim.
-- Acessos: mínimo 6 meses (já na 061200). Depende de 224700, 225400, 20261127190000 e 20261127190200.
-- Usa public.dia_em_brasilia da 190200: desfazer a 190500 ANTES da 190200.
--
-- ESTA MIGRATION NÃO APAGA NEM ANONIMIZA NADA e NÃO cria função que apague registro de Pedido:
-- o texto não diz, tabela a tabela, o que excluir e o que anonimizar. Ela responde SE e QUANDO
-- o prazo de um Pedido acabou e o que ainda o segura. Livros e travas de imutabilidade seguem.
--   * public.pedido_guardas: guarda por processo ou investigação, por Pedido.
--   * conclusão = último pedido_historico.para_status = 'concluido' de Pedido que ESTÁ
--     'concluido'. Sem isso: 'sem_marco' (nunca elegível).
--   * prazo: retencao_registros_pedido_anos (config vigente); sem valor ou abaixo de 5: 5.
--   * o expurgo de acessos passa a respeitar a guarda de Pedido.
--
-- CONFIGURAÇÃO: definição em supabase/seeds/seed_config_retencao.sql.
-- Rollback: supabase/rollback/20261127190500_retencao_registros_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.expurgo_acessos_enfileirar()') is null
     or to_regclass('public.disputa_contestacoes') is null
     or to_regclass('public.nota_material_contestacoes') is null
     or to_regprocedure('public.dia_em_brasilia(timestamptz)') is null then
    raise exception 'Aplique antes as migrations 224700, 225400, 20261127190000 e 20261127190200';
  end if;
end;
$$;

create table if not exists public.pedido_guardas (
  id            uuid primary key default gen_random_uuid(),
  pedido_id     uuid not null references public.pedidos (id) on delete restrict,
  tipo          text not null check (tipo in ('processo', 'investigacao')),
  motivo        text not null check (btrim(motivo) <> ''),
  criada_por    uuid not null references public.equipe (usuario_id) on delete restrict,
  criada_em     timestamptz not null default now(),
  encerrada_em  timestamptz,
  encerrada_por uuid references public.equipe (usuario_id) on delete restrict,
  check ((encerrada_em is null) = (encerrada_por is null))
);
create index if not exists ix_pedido_guardas_abertas
  on public.pedido_guardas (pedido_id) where encerrada_em is null;

create or replace function public.pedido_guardas_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_quem uuid;
begin
  if tg_op = 'INSERT' then
    if new.encerrada_em is not null then
      raise exception 'Guarda deve nascer aberta' using errcode = 'check_violation';
    end if;
    new.criada_em := now();
    v_quem := new.criada_por;
  else
    if old.encerrada_em is not null then
      raise exception 'Guarda encerrada não muda' using errcode = 'restrict_violation';
    end if;
    if new.encerrada_em is null then
      return new;
    end if;
    new.encerrada_em := now();
    v_quem := new.encerrada_por;
  end if;
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = v_quem and q.ativo and q.revogado_em is null
                    and q.papel in ('dpo', 'juridico', 'seguranca', 'administrador')) then
    raise exception 'Guarda de Pedido exige dpo, jurídico, segurança ou administrador ativo'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.pedido_guardas_validar() from public, anon, authenticated, service_role;

drop trigger if exists pedido_guardas_expurgo_fila_trg on public.pedido_guardas;
create trigger pedido_guardas_expurgo_fila_trg before insert on public.pedido_guardas
  for each row execute function public.expurgo_acessos_enfileirar();
drop trigger if exists pedido_guardas_proteger on public.pedido_guardas;
create trigger pedido_guardas_proteger before update on public.pedido_guardas
  for each row execute function public.proteger_colunas('id', 'pedido_id', 'tipo', 'motivo', 'criada_por', 'criada_em');
drop trigger if exists pedido_guardas_validar_trg on public.pedido_guardas;
create trigger pedido_guardas_validar_trg before insert or update on public.pedido_guardas
  for each row execute function public.pedido_guardas_validar();
drop trigger if exists pedido_guardas_sem_delete on public.pedido_guardas;
create trigger pedido_guardas_sem_delete before delete on public.pedido_guardas
  for each row execute function public.bloquear_alteracao();
drop trigger if exists pedido_guardas_sem_truncate on public.pedido_guardas;
create trigger pedido_guardas_sem_truncate before truncate on public.pedido_guardas
  for each statement execute function public.bloquear_alteracao();
alter table public.pedido_guardas enable row level security;
revoke all on table public.pedido_guardas from public, anon, authenticated, service_role;
grant select, insert, update on table public.pedido_guardas to service_role;

create or replace function public.retencao_registros_pedido_anos_vigente()
returns integer
language sql stable security definer set search_path = ''
as $$
  select greatest(coalesce(max(p.valor), 5), 5)::integer
    from public.config_parametros p
    join public.config_versoes v on v.id = p.versao_id and v.status = 'vigente'
   where p.chave = 'retencao_registros_pedido_anos' and p.escopo_tipo = 'global';
$$;

create or replace function public.retencao_pedido_bloqueios(p_pedido uuid)
returns text[]
language sql stable security definer set search_path = ''
as $$
  with partes as (
    select p.cliente_id as u from public.pedidos p where p.id = p_pedido
    union
    select x.u from public.contratos c, lateral (values (c.cliente_id), (c.profissional_id)) x(u)
     where c.pedido_id = p_pedido
  )
  select array_remove(array[
    case when exists (select 1 from public.disputas d
                       where d.pedido_id = p_pedido
                         and d.status not in ('acordo', 'decidida', 'cancelada'))
         then 'disputa_aberta' end,
    case when exists (select 1 from public.disputa_contestacoes k
                       where k.pedido_id = p_pedido
                         and (k.status in ('aberta', 'em_analise', 'aguardando_aprovacao')
                              or k.efeito_financeiro = 'pendente_financeiro'))
         then 'contestacao_disputa_aberta' end,
    case when exists (select 1 from public.nota_material_contestacoes k
                        join public.notas_material n on n.id = k.nota_id
                        join public.contratos c on c.id = n.contrato_id
                       where c.pedido_id = p_pedido
                         and (k.status in ('aberta', 'em_analise')
                              or k.efeito_financeiro = 'pendente_financeiro'))
         then 'contestacao_nota_aberta' end,
    case when exists (select 1 from public.pagamentos g
                        join public.contratos c on c.id = g.contrato_id
                       where c.pedido_id = p_pedido and g.status = 'contestado')
         then 'pagamento_contestado' end,
    case when exists (select 1 from public.incidentes_seguranca i
                       where i.status <> 'encerrado'
                         and (i.pedido_id = p_pedido or i.envolvido_id in (select u from partes)))
         then 'incidente_nao_encerrado' end,
    case when public.pedido_com_registros_preservados(p_pedido)
           or exists (select 1 from partes where public.usuario_com_registros_preservados(u))
         then 'preservacao_9_6' end,
    case when exists (select 1 from public.pedido_guardas g
                       where g.pedido_id = p_pedido and g.encerrada_em is null)
         then 'guarda_pedido' end,
    case when exists (select 1 from public.acessos_conta_guardas g
                       where g.encerrada_em is null and g.usuario_id in (select u from partes))
         then 'guarda_usuario' end
  ], null);
$$;

create or replace function public.retencao_pedido_situacao(p_pedido uuid, p_agora timestamptz default now())
returns table (pedido_id uuid, situacao text, concluido_em timestamptz, prazo_anos integer,
               guarda_ate timestamptz, bloqueios text[])
language sql stable security definer set search_path = ''
as $$
  with base as (
    select p.id,
           case when p.status = 'concluido' then
             (select h.ocorrida_em from public.pedido_historico h
               where h.pedido_id = p.id and h.para_status = 'concluido'
               order by h.ocorrida_em desc, h.id desc limit 1) end as fim,
           public.retencao_registros_pedido_anos_vigente() as anos
      from public.pedidos p where p.id = p_pedido
  ),
  calc as (
    select b.id, b.fim, b.anos,
           -- último dia de guarda, pela data de Brasília
           (public.dia_em_brasilia(b.fim) + make_interval(years => b.anos))::date as ultimo_dia,
           public.retencao_pedido_bloqueios(b.id) as blq
      from base b
  )
  select c.id,
         case when c.fim is null then 'sem_marco'
              when public.dia_em_brasilia(p_agora) <= c.ultimo_dia then 'no_prazo'
              when cardinality(c.blq) > 0 then 'bloqueado'
              else 'vencido' end,
         c.fim, c.anos,
         -- instante em que o último dia termina (informativo; a decisão é pela data)
         (c.ultimo_dia + 1)::timestamp at time zone interval '-3 hours', c.blq
    from calc c;
$$;

-- Portão para qualquer eliminação futura: usa a hora do banco e, na MESMA transação de quem
-- vai apagar, põe em fila guardas, disputas, incidentes e preservação ainda por gravar.
create or replace function public.pode_eliminar_registros_pedido(p_pedido uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('trato.expurgo_acessos', 0));
  perform pg_advisory_xact_lock(hashtextextended('trato.preservacao_registros', 0));
  return coalesce((select s.situacao = 'vencido'
                     from public.retencao_pedido_situacao(p_pedido, now()) s), false);
end;
$$;

revoke all on function public.retencao_registros_pedido_anos_vigente() from public, anon, authenticated;
revoke all on function public.retencao_pedido_bloqueios(uuid) from public, anon, authenticated;
revoke all on function public.retencao_pedido_situacao(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.pode_eliminar_registros_pedido(uuid) from public, anon, authenticated;
grant execute on function public.retencao_registros_pedido_anos_vigente() to service_role;
grant execute on function public.retencao_pedido_bloqueios(uuid) to service_role;
grant execute on function public.retencao_pedido_situacao(uuid, timestamptz) to service_role;
grant execute on function public.pode_eliminar_registros_pedido(uuid) to service_role;

-- Igual à da 20261127190000, mais a guarda de Pedido.
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
    -- guarda de Pedido aberta (processo ou investigação) segura os acessos das partes
    || ' and not exists (select 1 from public.pedido_guardas pg join public.pedidos p2 on p2.id = pg.pedido_id'
    ||   ' where pg.encerrada_em is null and (p2.cliente_id = a.usuario_id or exists'
    ||     ' (select 1 from public.contratos c2 where c2.pedido_id = p2.id'
    ||     ' and a.usuario_id in (c2.cliente_id, c2.profissional_id))))'
    || ' order by a.ocorrido_em limit $2)'
    using v_meses, p_limite;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.expurgar_acessos_conta(integer) from public, anon, authenticated;
grant execute on function public.expurgar_acessos_conta(integer) to service_role;

commit;
