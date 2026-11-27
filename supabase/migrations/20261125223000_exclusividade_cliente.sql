-- ===========================================================================
-- 20261125223000_exclusividade_cliente.sql
-- RASCUNHO (TERMOS-DB3). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2: 13.6, 13.8, I.4 e termos-v1.2-ajustes.md item 6 (exclusividade do CLIENTE).
-- Depende de 20261125141500 (coluna pagador e afins) e 20261125150000 (saldo e estorno).
--
-- O cliente paga moedas_config.exclusividade_custo_moedas; por exclusividade_duracao_horas
-- o pedido fica 'reservado' e só o profissional escolhido orça.
--   exclusividade_cliente_solicitar    cria já 'ativa' e debita a carteira 'cliente'
--   exclusividade_cliente_desistir     desistência do profissional: devolve, reabre
--   exclusividade_cliente_falha_trato  falha do Trato (analista ativo e motivo; grava auditoria):
--                                      devolve (também registrada depois do prazo)
--   exclusividade_cliente_contratar    contratação (ou pedido cancelado): encerra sem devolver
--   exclusividade_cliente_expirar      fim do prazo: 'expirada_sem_contratacao', sem devolver
-- Devolução: validade original; se venceu, crédito de 30 dias.
-- As 4 funções do profissional passam a ignorar linhas pagador = 'cliente'.
-- Nenhum dado existente é alterado.
--
-- ESCOLHAS onde o termo não define (a favor do consumidor; confirmar com o João):
--   a) vale para pedido urgente e qualquer categoria; sem limite de pedidos por cliente;
--   b) o cliente pode aceitar outro orçamento já recebido (encerra sem devolução);
--   c) falha do Trato pode ser registrada depois do prazo ou do cancelamento, nunca após
--      contratação com o escolhido;
--   d) moedas presas em reserva de desconto não pagam a exclusividade;
--   e) não cobra se o profissional escolhido não puder orçar o pedido (conta, verificação,
--      categoria, modalidade, região, série recorrente e MEI quando p_exigir_mei).
--      Medidas de conta que não mudem usuarios.status ficam a cargo do backend.
--
-- CONFERÊNCIA (somente leitura). Esperado: 14 linhas, secdef = t, anon/auth = f; svc = f só em
-- exclusividade_cliente_devolver, exclusividade_cliente_vencer, orcamentos_exclusividade_cliente,
-- exclusividade_estornar_moedas e profissional_pode_orcar.
-- select p.proname, p.prosecdef, p.proconfig,
--        has_function_privilege('anon', p.oid, 'execute') as anon,
--        has_function_privilege('authenticated', p.oid, 'execute') as auth,
--        has_function_privilege('service_role', p.oid, 'execute') as svc
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public' and (p.proname like 'exclusividade%' or p.proname in
--        ('orcamentos_exclusividade_cliente', 'profissional_pode_orcar'))
--  order by 1;
-- select tgname from pg_trigger where tgname = 'orcamentos_exclusividade_cliente_trg';
-- select pagador, status, count(*) from public.exclusividades group by 1, 2 order by 1, 2;
--
-- Rollback: supabase/rollback/20261125223000_exclusividade_cliente_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
                  and table_name = 'exclusividades' and column_name = 'pagador')
     or to_regprocedure('public.moedas_saldo(uuid,text,timestamptz)') is null
     or to_regprocedure('public.exclusividade_estornar_moedas(uuid,text,uuid,uuid,integer,timestamptz)') is null then
    raise exception 'Aplique antes as migrations 20261125141500 e 20261125150000';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Devolução (uso interno: só as funções abaixo chamam; ninguém tem EXECUTE)
-- O chamador já segura o lock do pedido e da exclusividade.
-- ---------------------------------------------------------------------------
create or replace function public.exclusividade_cliente_devolver(
  p_exclusividade uuid, p_motivo text, p_ator uuid, p_agora timestamptz)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_exc    public.exclusividades%rowtype;
  v_estorno uuid;
  v_total  integer;
  v_rows   integer;
begin
  if p_exclusividade is null or p_agora is null
     or p_motivo is null or p_motivo not in ('falha_trato', 'desistencia_profissional') then
    raise exception 'parâmetros inválidos para devolver exclusividade do cliente';
  end if;
  select * into v_exc from public.exclusividades where id = p_exclusividade for update;
  if not found or v_exc.pagador <> 'cliente' or v_exc.estornada then
    raise exception 'exclusividade % não pode ser devolvida', p_exclusividade;
  end if;

  perform public.exclusividade_estornar_moedas(
    v_exc.cliente_id, 'cliente', v_exc.id, v_exc.profissional_id, v_exc.moedas_cobradas, p_agora);

  select l.id into v_estorno from public.moedas_lancamentos l
   where l.chave_idempotencia = 'exclusividade-estorno:' || v_exc.id::text
     and l.usuario_id = v_exc.cliente_id and l.carteira = 'cliente';
  if not found then
    raise exception 'exclusividade % sem débito para devolver', v_exc.id;
  end if;
  select coalesce(sum(l.quantidade), 0)::integer into v_total from public.moedas_lancamentos l
   where l.referencia_id = v_exc.id and l.usuario_id = v_exc.cliente_id
     and l.carteira = 'cliente' and l.tipo = 'exclusividade_estorno';

  update public.exclusividades
     set status = 'cancelada', motivo_encerramento = p_motivo, estornada = true, estornada_em = p_agora,
         estorno_lancamento_id = v_estorno, encerrada_em = coalesce(encerrada_em, p_agora),
         atualizado_em = p_agora
   where id = v_exc.id;

  -- reabre o pedido só se foi ESTA exclusividade (ainda ativa) que o reservou
  if v_exc.status = 'ativa' then
    update public.pedidos set status = 'aberto' where id = v_exc.pedido_id and status = 'reservado';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, motivo, prova, ocorrida_em)
      values (v_exc.pedido_id, 'reservado', 'aberto', p_ator, 'exclusividade devolvida: ' || p_motivo,
              jsonb_build_object('acao', 'expirar_exclusividade', 'papel', 'sistema',
                                 'dados', jsonb_build_object('exclusividade_id', v_exc.id, 'motivo', p_motivo)),
              p_agora);
    end if;
  end if;
  return v_total;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fim do prazo de UMA exclusividade (uso interno). O chamador segura o lock do pedido.
-- ---------------------------------------------------------------------------
create or replace function public.exclusividade_cliente_vencer(p_exclusividade uuid, p_agora timestamptz)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_pedido uuid;
  v_rows   integer;
begin
  update public.exclusividades
     set status = 'expirada_sem_contratacao', motivo_encerramento = 'prazo_expirado_sem_contratacao',
         encerrada_em = p_agora, atualizado_em = p_agora
   where id = p_exclusividade and pagador = 'cliente' and status = 'ativa' and expira_em <= p_agora
  returning pedido_id into v_pedido;
  if not found then
    return false;
  end if;
  update public.pedidos set status = 'aberto' where id = v_pedido and status = 'reservado';
  get diagnostics v_rows = row_count;
  if v_rows > 0 then
    insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, motivo, prova, ocorrida_em)
    values (v_pedido, 'reservado', 'aberto', null, 'exclusividade do cliente terminou sem contratação',
            jsonb_build_object('acao', 'expirar_exclusividade', 'papel', 'sistema',
                               'dados', jsonb_build_object('exclusividade_id', p_exclusividade)),
            p_agora);
  end if;
  return true;
end;
$$;

-- Pode orçar ESTE pedido? Mesma regra da lista de abertos e do envio de orçamento do backend:
-- conta ativa, perfil aprovado e verificado, categoria sem suspensão, modalidade e região,
-- série de visita recorrente e, quando p_exigir_mei, MEI válido. (uso interno)
-- FICA COM O BACKEND: medidas de conta vigentes (medidas_conta) que não mudem usuarios.status.
create or replace function public.profissional_pode_orcar(
  p_profissional uuid, p_pedido uuid, p_exigir_mei boolean)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
      from public.pedidos p
      join public.usuarios u on u.id = p_profissional
      join public.perfis_profissional pf on pf.usuario_id = p_profissional
     where p.id = p_pedido
       and p.cliente_id <> p_profissional
       and u.status = 'ativo'
       and pf.status = 'aprovado'
       and pf.nivel_verificacao in ('verificado', 'verificado_plus')
       and (not p_exigir_mei
            or (pf.mei_status = 'valido' and pf.tipo_cnpj is distinct from 'outro'))
       and exists (select 1 from public.profissional_categorias pc
                    where pc.profissional_id = p_profissional and pc.categoria_id = p.categoria_id
                      and pc.suspensa_em is null)
       and ((p.modalidade = 'presencial' and pf.atende_presencial
             and exists (select 1 from public.profissional_regioes pr
                          where pr.profissional_id = p_profissional and pr.cidade_id = p.cidade_id
                            and (pr.bairro is null or pr.bairro = p.bairro)))
            or (p.modalidade = 'remoto' and pf.atende_remoto))
       and (not exists (select 1 from public.recorrencia_visitas rv where rv.pedido_id = p.id)
            or exists (select 1 from public.recorrencia_visitas rv
                         join public.recorrencias rc on rc.id = rv.recorrencia_id
                        where rv.pedido_id = p.id and rc.profissional_id = p_profissional))
  );
$$;

-- 1) SOLICITAR (cliente paga) ------------------------------------------------------------------
create or replace function public.exclusividade_cliente_solicitar(
  p_cliente uuid, p_pedido uuid, p_profissional uuid, p_orcamento uuid, p_chave text, p_agora timestamptz,
  p_exigir_mei boolean)  -- o backend passa a configuração TRATO_MEI_OBRIGATORIO
returns table (resultado text, exclusividade_id uuid, expira_em timestamptz, saldo_restante integer)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_custo  integer;
  v_horas  integer;
  v_saldo  bigint;
  v_exist  record;
  v_ped    record;
  v_orc    record;
  v_prof   uuid := p_profissional;
  v_id     uuid;
  v_fim    timestamptz;
begin
  if p_cliente is null or p_pedido is null or p_chave is null or btrim(p_chave) = '' or p_agora is null
     or (p_profissional is null and p_orcamento is null) or p_exigir_mei is null then
    raise exception 'parâmetros inválidos para solicitar exclusividade do cliente';
  end if;

  select c.exclusividade_custo_moedas, c.exclusividade_duracao_horas into v_custo, v_horas
    from public.moedas_config c where c.id;
  if not found then
    raise exception 'moedas_config sem a linha de configuração';
  end if;

  -- lock 1: a MESMA trava da reserva de desconto (o saldo do cliente não é gasto duas vezes)
  perform pg_advisory_xact_lock(hashtextextended(p_cliente::text, 0));

  -- saldo livre = saldo válido menos o que está preso em reservas de desconto abertas
  v_saldo := public.moedas_saldo(p_cliente, 'cliente', p_agora);
  v_saldo := greatest(v_saldo - coalesce((select sum(r.moedas) from public.moedas_reservas r
                                           where r.usuario_id = p_cliente and r.status = 'reservada'), 0), 0);

  select e.id, e.cliente_id, e.pedido_id, e.pagador, e.expira_em into v_exist
    from public.exclusividades e where e.chave_idempotencia = p_chave;
  if found then
    if v_exist.pagador <> 'cliente' or v_exist.cliente_id <> p_cliente or v_exist.pedido_id <> p_pedido then
      raise exception 'chave de idempotência já usada em outra exclusividade';
    end if;
    return query select 'ja_existe'::text, v_exist.id, v_exist.expira_em, v_saldo::integer;
    return;
  end if;

  -- lock 2: o pedido
  select p.cliente_id, p.status, p.expira_em into v_ped
    from public.pedidos p where p.id = p_pedido for update;
  if not found or v_ped.cliente_id <> p_cliente then
    return query select 'nao_encontrado'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;
  if v_ped.status <> 'aberto'
     or (v_ped.expira_em is not null and v_ped.expira_em <= p_agora)
     or exists (select 1 from public.exclusividades e
                 where e.pedido_id = p_pedido and e.status in ('aguardando_cliente', 'ativa')) then
    return query select 'pedido_indisponivel'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if p_orcamento is not null then
    select o.profissional_id, o.status, o.validade_ate into v_orc
      from public.orcamentos o where o.id = p_orcamento and o.pedido_id = p_pedido;
    if not found or v_orc.status <> 'enviado'
       or (v_orc.validade_ate is not null and v_orc.validade_ate <= p_agora)
       or (p_profissional is not null and p_profissional <> v_orc.profissional_id) then
      return query select 'orcamento_invalido'::text, null::uuid, null::timestamptz, v_saldo::integer;
      return;
    end if;
    v_prof := v_orc.profissional_id;
  end if;

  -- não cobra por quem não poderia enviar orçamento neste pedido
  if not public.profissional_pode_orcar(v_prof, p_pedido, p_exigir_mei) then
    return query select 'profissional_indisponivel'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if v_saldo < v_custo then
    return query select 'saldo_insuficiente'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  v_fim := p_agora + make_interval(hours => v_horas);
  insert into public.exclusividades
    (profissional_id, cliente_id, pedido_id, status, moedas_cobradas, chave_idempotencia, criada_em,
     responder_ate, expira_em, atualizado_em, pagador, orcamento_id)
  values (v_prof, p_cliente, p_pedido, 'ativa', v_custo, p_chave, p_agora,
          p_agora, v_fim, p_agora, 'cliente', p_orcamento)
  returning id into v_id;

  insert into public.moedas_lancamentos
    (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, criada_em)
  values (p_cliente, 'exclusividade_uso', -v_custo, 'exclusividade-uso:' || v_id::text,
          v_prof, v_id, 'cliente', p_agora);

  update public.pedidos set status = 'reservado' where id = p_pedido and status = 'aberto';
  insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, motivo, prova, ocorrida_em)
  values (p_pedido, 'aberto', 'reservado', p_cliente, 'exclusividade paga pelo cliente',
          jsonb_build_object('acao', 'reservar_exclusividade', 'papel', 'cliente',
                             'dados', jsonb_build_object('exclusividade_id', v_id)),
          p_agora);

  return query select 'ok'::text, v_id, v_fim, (v_saldo - v_custo)::integer;
end;
$$;

-- 2) DESISTÊNCIA DO PROFISSIONAL (devolve) -----------------------------------------------------
create or replace function public.exclusividade_cliente_desistir(
  p_exclusividade uuid, p_profissional uuid, p_agora timestamptz)
returns table (resultado text, devolvido integer)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ini  record;
  v_exc  record;
  v_lock uuid;
begin
  if p_exclusividade is null or p_profissional is null or p_agora is null then
    raise exception 'parâmetros inválidos para desistência do profissional';
  end if;
  -- pedido_id, profissional_id e pagador nunca mudam: leitura sem lock só para achar o pedido
  select e.pedido_id, e.profissional_id, e.pagador into v_ini
    from public.exclusividades e where e.id = p_exclusividade;
  if not found or v_ini.pagador <> 'cliente' or v_ini.profissional_id <> p_profissional then
    return query select 'nao_encontrada'::text, 0;
    return;
  end if;
  select p.id into v_lock from public.pedidos p where p.id = v_ini.pedido_id for update;
  select e.status, e.expira_em, e.estornada, e.motivo_encerramento, e.moedas_cobradas into v_exc
    from public.exclusividades e where e.id = p_exclusividade for update;

  if v_exc.estornada then
    return query select 'ja_devolvida'::text, v_exc.moedas_cobradas;
    return;
  end if;
  if v_exc.status <> 'ativa' then
    return query select 'ja_encerrada'::text, 0;
    return;
  end if;
  if v_exc.expira_em <= p_agora then
    perform public.exclusividade_cliente_vencer(p_exclusividade, p_agora);
    return query select 'prazo_vencido'::text, 0;
    return;
  end if;
  return query select 'ok'::text, public.exclusividade_cliente_devolver(
    p_exclusividade, 'desistencia_profissional', p_profissional, p_agora);
end;
$$;

-- 3) FALHA DO TRATO (devolve; aceita registro depois do prazo) ---------------------------------
create or replace function public.exclusividade_cliente_falha_trato(
  p_exclusividade uuid, p_analista uuid, p_motivo text, p_agora timestamptz)
returns table (resultado text, devolvido integer)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ini  record;
  v_exc  record;
  v_lock  uuid;
  v_total integer;
begin
  if p_exclusividade is null or p_analista is null or p_motivo is null or btrim(p_motivo) = ''
     or p_agora is null then
    raise exception 'parâmetros inválidos para falha do Trato: analista e motivo são obrigatórios';
  end if;
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = p_analista and q.ativo and q.revogado_em is null) then
    return query select 'analista_invalido'::text, 0;
    return;
  end if;
  select e.pedido_id, e.pagador into v_ini from public.exclusividades e where e.id = p_exclusividade;
  if not found or v_ini.pagador <> 'cliente' then
    return query select 'nao_encontrada'::text, 0;
    return;
  end if;
  select p.id into v_lock from public.pedidos p where p.id = v_ini.pedido_id for update;
  select e.status, e.estornada, e.moedas_cobradas into v_exc
    from public.exclusividades e where e.id = p_exclusividade for update;

  if v_exc.estornada then
    return query select 'ja_devolvida'::text, v_exc.moedas_cobradas;
    return;
  end if;
  if v_exc.status = 'concluida' then
    return query select 'nao_elegivel'::text, 0;
    return;
  end if;
  v_total := public.exclusividade_cliente_devolver(p_exclusividade, 'falha_trato', p_analista, p_agora);
  perform public.registrar_auditoria(
    p_analista, 'equipe', 'estorno.exclusividade_falha_trato', 'exclusividade', p_exclusividade,
    jsonb_build_object('status', v_exc.status),
    jsonb_build_object('status', 'cancelada', 'moedas_devolvidas', v_total, 'pedido_id', v_ini.pedido_id),
    btrim(p_motivo), null, null, null);
  return query select 'ok'::text, v_total;
end;
$$;

-- 4) CONTRATAÇÃO ou cancelamento do pedido (nunca devolve; não muda o estado do pedido) --------
create or replace function public.exclusividade_cliente_contratar(
  p_pedido uuid, p_profissional uuid, p_agora timestamptz)
returns table (exclusividade_id uuid, resultado text)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_lock uuid;
  v_exc  record;
  v_res  text;
begin
  if p_pedido is null or p_agora is null then
    raise exception 'parâmetros inválidos para contratar com exclusividade';
  end if;
  select p.id into v_lock from public.pedidos p where p.id = p_pedido for update;
  if not found then
    return;
  end if;
  select e.id, e.profissional_id, e.expira_em into v_exc
    from public.exclusividades e
   where e.pedido_id = p_pedido and e.pagador = 'cliente' and e.status = 'ativa'
     for update;
  if not found then
    return;
  end if;

  if v_exc.expira_em <= p_agora then
    v_res := 'expirada';
    update public.exclusividades
       set status = 'expirada_sem_contratacao', motivo_encerramento = 'prazo_expirado_sem_contratacao',
           encerrada_em = p_agora, atualizado_em = p_agora
     where id = v_exc.id;
  elsif p_profissional is not null and p_profissional = v_exc.profissional_id then
    v_res := 'concluida';
    update public.exclusividades
       set status = 'concluida', motivo_encerramento = 'contratacao_realizada',
           encerrada_em = p_agora, atualizado_em = p_agora
     where id = v_exc.id;
  else
    -- outro profissional contratado, ou pedido cancelado pelo cliente (p_profissional nulo)
    v_res := 'cancelada';
    update public.exclusividades
       set status = 'cancelada', motivo_encerramento = 'cancelamento_cliente',
           encerrada_em = p_agora, atualizado_em = p_agora
     where id = v_exc.id;
  end if;
  return query select v_exc.id, v_res;
end;
$$;

-- 5) EXPIRAR (rotina) --------------------------------------------------------------------------
create or replace function public.exclusividade_cliente_expirar(p_agora timestamptz)
returns table (exclusividade_id uuid, cliente_id uuid, profissional_id uuid, pedido_id uuid)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  r      record;
  v_lock uuid;
begin
  if p_agora is null then
    raise exception 'p_agora é obrigatório';
  end if;
  for r in select e.id, e.cliente_id, e.profissional_id, e.pedido_id from public.exclusividades e
            where e.pagador = 'cliente' and e.status = 'ativa' and e.expira_em <= p_agora
            order by e.expira_em
  loop
    select p.id into v_lock from public.pedidos p where p.id = r.pedido_id for update skip locked;
    if not found then
      continue;
    end if;
    if public.exclusividade_cliente_vencer(r.id, p_agora) then
      return query select r.id, r.cliente_id, r.profissional_id, r.pedido_id;
    end if;
  end loop;
  return;
end;
$$;

-- ---------------------------------------------------------------------------
-- Durante o prazo, só o profissional escolhido cria ou envia orçamento no pedido.
-- ---------------------------------------------------------------------------
create or replace function public.orcamentos_exclusividade_cliente()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.status <> 'enviado' or old.status = 'enviado' then
      return new;
    end if;
  end if;
  -- serializa com a solicitação, que segura o pedido FOR UPDATE
  perform 1 from public.pedidos p where p.id = new.pedido_id for share;
  if exists (select 1 from public.exclusividades e
              where e.pedido_id = new.pedido_id and e.pagador = 'cliente' and e.status = 'ativa'
                and e.expira_em > now() and e.profissional_id <> new.profissional_id) then
    raise exception 'Pedido em exclusividade: só o profissional escolhido pode orçar'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists orcamentos_exclusividade_cliente_trg on public.orcamentos;
create trigger orcamentos_exclusividade_cliente_trg before insert or update on public.orcamentos
  for each row execute function public.orcamentos_exclusividade_cliente();

-- Grants: as 5 funções chamadas pelo backend só para service_role; as internas para ninguém.
revoke all on function public.exclusividade_cliente_devolver(uuid, text, uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.exclusividade_cliente_vencer(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.orcamentos_exclusividade_cliente() from public, anon, authenticated, service_role;
revoke all on function public.profissional_pode_orcar(uuid, uuid, boolean) from public, anon, authenticated, service_role;
revoke all on function public.exclusividade_cliente_solicitar(uuid, uuid, uuid, uuid, text, timestamptz, boolean) from public, anon, authenticated;
revoke all on function public.exclusividade_cliente_desistir(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.exclusividade_cliente_falha_trato(uuid, uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.exclusividade_cliente_contratar(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.exclusividade_cliente_expirar(timestamptz) from public, anon, authenticated;
grant execute on function public.exclusividade_cliente_solicitar(uuid, uuid, uuid, uuid, text, timestamptz, boolean) to service_role;
grant execute on function public.exclusividade_cliente_desistir(uuid, uuid, timestamptz) to service_role;
grant execute on function public.exclusividade_cliente_falha_trato(uuid, uuid, text, timestamptz) to service_role;
grant execute on function public.exclusividade_cliente_contratar(uuid, uuid, timestamptz) to service_role;
grant execute on function public.exclusividade_cliente_expirar(timestamptz) to service_role;

-- Funções do profissional (versão da 20261125150000), agora só para pagador = 'profissional'
create or replace function public.exclusividade_solicitar(
  p_profissional uuid, p_pedido uuid, p_chave text, p_agora timestamptz,
  p_custo integer, p_max_simultaneas integer, p_prazo_resposta_horas integer, p_bloqueio_recusa_dias integer)
returns table (resultado text, exclusividade_id uuid, responder_ate timestamptz, saldo_restante integer)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pedido record;
  v_exist  record;
  v_saldo  bigint;
  v_id     uuid;
  v_resp   timestamptz;
  v_permite boolean;
begin
  if p_profissional is null or p_pedido is null or p_chave is null or btrim(p_chave) = '' or p_agora is null
     or p_custo is null or p_custo <= 0 or p_max_simultaneas is null or p_max_simultaneas <= 0
     or p_prazo_resposta_horas is null or p_prazo_resposta_horas <= 0
     or p_bloqueio_recusa_dias is null or p_bloqueio_recusa_dias < 0 then
    raise exception 'parâmetros inválidos para solicitar exclusividade';
  end if;

  -- lock 1: serializa tudo do mesmo profissional (cliques duplos, saldo gasto 2x, limite de simultâneas)
  perform pg_advisory_xact_lock(hashtextextended('exclusividade:' || p_profissional::text, 0));

  v_saldo := public.moedas_saldo(p_profissional, 'profissional', p_agora);

  -- idempotência por chave: devolve a existente, sem cobrar de novo
  select e.id, e.profissional_id, e.responder_ate, e.pagador into v_exist
    from public.exclusividades e where e.chave_idempotencia = p_chave;
  if found then
    if v_exist.profissional_id <> p_profissional or v_exist.pagador <> 'profissional' then
      raise exception 'chave de idempotência já usada por outro profissional';
    end if;
    return query select 'ja_existe'::text, v_exist.id, v_exist.responder_ate, v_saldo::integer;
    return;
  end if;

  -- lock 2: o pedido
  select p.cliente_id, p.categoria_id, p.urgente, p.status into v_pedido
    from public.pedidos p where p.id = p_pedido for update;
  if not found then
    return query select 'pedido_indisponivel'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if v_pedido.cliente_id = p_profissional then
    return query select 'proprio_pedido'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if v_pedido.status <> 'aberto'
     or exists (select 1 from public.exclusividades e
                 where e.pedido_id = p_pedido and e.status in ('aguardando_cliente', 'ativa')) then
    return query select 'pedido_indisponivel'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if v_pedido.urgente then
    return query select 'pedido_urgente'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  select c.permite_exclusividade into v_permite from public.categorias c where c.id = v_pedido.categoria_id;
  if v_permite is distinct from true then
    return query select 'categoria_sem_exclusividade'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  -- recusado pelo mesmo cliente há menos de N dias
  if exists (select 1 from public.exclusividades e
              where e.profissional_id = p_profissional and e.cliente_id = v_pedido.cliente_id
                and e.status = 'recusada'
                and e.encerrada_em > p_agora - make_interval(days => p_bloqueio_recusa_dias)) then
    return query select 'bloqueado_recusa'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if (select count(*) from public.exclusividades e
       where e.profissional_id = p_profissional and e.pagador = 'profissional'
         and e.status in ('aguardando_cliente', 'ativa')) >= p_max_simultaneas then
    return query select 'limite_simultaneas'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  if v_saldo < p_custo then
    return query select 'saldo_insuficiente'::text, null::uuid, null::timestamptz, v_saldo::integer;
    return;
  end if;

  -- lock 3 + efeitos: cria a exclusividade e cobra no livro
  v_resp := p_agora + make_interval(hours => p_prazo_resposta_horas);
  insert into public.exclusividades
    (profissional_id, cliente_id, pedido_id, status, moedas_cobradas, chave_idempotencia, criada_em, responder_ate, atualizado_em)
  values (p_profissional, v_pedido.cliente_id, p_pedido, 'aguardando_cliente', p_custo, p_chave, p_agora, v_resp, p_agora)
  returning id into v_id;

  insert into public.moedas_lancamentos
    (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, criada_em)
  values (p_profissional, 'exclusividade_uso', -p_custo, 'exclusividade-uso:' || v_id::text,
          v_pedido.cliente_id, v_id, 'profissional', p_agora);

  return query select 'ok'::text, v_id, v_resp, (v_saldo - p_custo)::integer;
end;
$$;

create or replace function public.exclusividade_responder(
  p_exclusividade uuid, p_cliente uuid, p_decisao text, p_agora timestamptz, p_duracao_horas integer)
returns table (resultado text, expira_em timestamptz)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ini  record;
  v_exc  record;
  v_ped  record;
  v_rows integer;
  v_fim  timestamptz;
begin
  if p_exclusividade is null or p_cliente is null or p_agora is null
     or p_decisao is null or p_decisao not in ('aceitar', 'recusar')
     or p_duracao_horas is null or p_duracao_horas <= 0 then
    raise exception 'parâmetros inválidos para responder exclusividade';
  end if;

  -- leitura sem lock só para achar o pedido (pedido_id e cliente_id nunca mudam)
  select e.pedido_id, e.cliente_id, e.pagador into v_ini from public.exclusividades e where e.id = p_exclusividade;
  if not found or v_ini.cliente_id <> p_cliente or v_ini.pagador <> 'profissional' then
    return query select 'nao_encontrada'::text, null::timestamptz;
    return;
  end if;

  -- lock 2: pedido; lock 3: exclusividade
  select p.status into v_ped from public.pedidos p where p.id = v_ini.pedido_id for update;
  select e.id, e.profissional_id, e.pedido_id, e.status, e.responder_ate, e.moedas_cobradas into v_exc
    from public.exclusividades e where e.id = p_exclusividade for update;

  if v_exc.status = 'expirada_sem_resposta' then
    return query select 'prazo_vencido'::text, null::timestamptz;
    return;
  end if;
  if v_exc.status <> 'aguardando_cliente' then
    return query select 'ja_respondida'::text, null::timestamptz;
    return;
  end if;

  -- prazo vencido: marca como a rotina e estorna
  if v_exc.responder_ate < p_agora then
    update public.exclusividades
       set status = 'expirada_sem_resposta', encerrada_em = p_agora, atualizado_em = p_agora
     where id = p_exclusividade and status = 'aguardando_cliente';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', p_exclusividade, p_cliente, v_exc.moedas_cobradas, p_agora);
    end if;
    return query select 'prazo_vencido'::text, null::timestamptz;
    return;
  end if;

  if p_decisao = 'recusar' then
    update public.exclusividades
       set status = 'recusada', respondida_em = p_agora, encerrada_em = p_agora, atualizado_em = p_agora
     where id = p_exclusividade and status = 'aguardando_cliente';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', p_exclusividade, p_cliente, v_exc.moedas_cobradas, p_agora);
    end if;
    return query select 'ok'::text, null::timestamptz;
    return;
  end if;

  -- aceitar: o pedido precisa seguir 'aberto'; senão cancela a oferta com estorno
  if v_ped.status is distinct from 'aberto' then
    update public.exclusividades
       set status = 'cancelada', respondida_em = p_agora, encerrada_em = p_agora, atualizado_em = p_agora
     where id = p_exclusividade and status = 'aguardando_cliente';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', p_exclusividade, p_cliente, v_exc.moedas_cobradas, p_agora);
    end if;
    return query select 'pedido_indisponivel'::text, null::timestamptz;
    return;
  end if;

  v_fim := p_agora + make_interval(hours => p_duracao_horas);
  update public.exclusividades
     set status = 'ativa', respondida_em = p_agora, expira_em = v_fim, atualizado_em = p_agora
   where id = p_exclusividade and status = 'aguardando_cliente';

  update public.pedidos set status = 'reservado' where id = v_exc.pedido_id and status = 'aberto';
  insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, motivo, prova, ocorrida_em)
  values (v_exc.pedido_id, 'aberto', 'reservado', p_cliente, 'exclusividade aceita pelo cliente',
          jsonb_build_object('acao', 'reservar_exclusividade', 'papel', 'cliente', 'dados', jsonb_build_object('exclusividade_id', p_exclusividade)),
          p_agora);

  return query select 'ok'::text, v_fim;
end;
$$;

create or replace function public.exclusividade_expirar(p_agora timestamptz)
returns table (exclusividade_id uuid, motivo text, profissional_id uuid, cliente_id uuid, pedido_id uuid)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  r      record;
  v_lock uuid;
  v_exc  record;
  v_rows integer;
begin
  if p_agora is null then
    raise exception 'p_agora é obrigatório';
  end if;

  -- (a) ofertas sem resposta no prazo: expiram COM estorno
  for r in select e.id, e.pedido_id from public.exclusividades e
            where e.pagador = 'profissional' and e.status = 'aguardando_cliente' and e.responder_ate < p_agora
            order by e.responder_ate
  loop
    -- lock 2 (pula se outra transação já está com o pedido); lock 3 pelo update condicional
    select p.id into v_lock from public.pedidos p where p.id = r.pedido_id for update skip locked;
    if not found then
      continue;
    end if;
    update public.exclusividades e
       set status = 'expirada_sem_resposta', encerrada_em = p_agora, atualizado_em = p_agora
     where e.id = r.id and e.status = 'aguardando_cliente' and e.responder_ate < p_agora
    returning e.id, e.profissional_id, e.cliente_id, e.pedido_id, e.moedas_cobradas into v_exc;
    if not found then
      continue;
    end if;
    perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', v_exc.id, v_exc.cliente_id, v_exc.moedas_cobradas, p_agora);
    return query select v_exc.id, 'sem_resposta'::text, v_exc.profissional_id, v_exc.cliente_id, v_exc.pedido_id;
  end loop;

  -- (b) exclusividade ativa que passou das horas sem atendimento: expira SEM estorno; pedido reservado -> aberto
  for r in select e.id, e.pedido_id from public.exclusividades e
            where e.pagador = 'profissional' and e.status = 'ativa' and e.expira_em < p_agora
            order by e.expira_em
  loop
    select p.id into v_lock from public.pedidos p where p.id = r.pedido_id for update skip locked;
    if not found then
      continue;
    end if;
    update public.exclusividades e
       set status = 'expirada_sem_atendimento', encerrada_em = p_agora, atualizado_em = p_agora
     where e.id = r.id and e.status = 'ativa' and e.expira_em < p_agora
    returning e.id, e.profissional_id, e.cliente_id, e.pedido_id into v_exc;
    if not found then
      continue;
    end if;
    update public.pedidos set status = 'aberto' where id = v_exc.pedido_id and status = 'reservado';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, motivo, prova, ocorrida_em)
      values (v_exc.pedido_id, 'reservado', 'aberto', null, 'exclusividade expirou sem atendimento',
              jsonb_build_object('acao', 'expirar_exclusividade', 'papel', 'sistema', 'dados', jsonb_build_object('exclusividade_id', v_exc.id)),
              p_agora);
    end if;
    return query select v_exc.id, 'sem_atendimento'::text, v_exc.profissional_id, v_exc.cliente_id, v_exc.pedido_id;
  end loop;

  return;
end;
$$;

create or replace function public.exclusividade_encerrar_por_pedido(
  p_pedido uuid, p_profissional_aceito uuid, p_agora timestamptz)
returns table (exclusividade_id uuid, resultado text, profissional_id uuid)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_lock uuid;
  v_exc  record;
begin
  if p_pedido is null or p_agora is null then
    raise exception 'parâmetros inválidos para encerrar exclusividade';
  end if;

  -- lock 2: pedido (se não existe, não há o que encerrar)
  select p.id into v_lock from public.pedidos p where p.id = p_pedido for update;
  if not found then
    return;
  end if;

  -- lock 3: a exclusividade em andamento (no máximo 1 por pedido, pelo índice único parcial)
  select e.id, e.profissional_id, e.status, e.cliente_id, e.moedas_cobradas into v_exc
    from public.exclusividades e
   where e.pedido_id = p_pedido and e.pagador = 'profissional'
     and e.status in ('aguardando_cliente', 'ativa')
     for update;
  if not found then
    return;
  end if;

  if p_profissional_aceito is not null and p_profissional_aceito = v_exc.profissional_id then
    update public.exclusividades e
       set status = 'concluida', encerrada_em = p_agora, atualizado_em = p_agora
     where e.id = v_exc.id and e.status in ('aguardando_cliente', 'ativa');
    return query select v_exc.id, 'concluida'::text, v_exc.profissional_id;
    return;
  end if;

  update public.exclusividades e
     set status = 'cancelada', encerrada_em = p_agora, atualizado_em = p_agora
   where e.id = v_exc.id and e.status in ('aguardando_cliente', 'ativa');
  perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', v_exc.id, v_exc.cliente_id, v_exc.moedas_cobradas, p_agora);
  return query select v_exc.id, 'cancelada'::text, v_exc.profissional_id;
end;
$$;

revoke all on function public.exclusividade_solicitar(uuid, uuid, text, timestamptz, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.exclusividade_solicitar(uuid, uuid, text, timestamptz, integer, integer, integer, integer) to service_role;
revoke all on function public.exclusividade_responder(uuid, uuid, text, timestamptz, integer) from public, anon, authenticated;
grant execute on function public.exclusividade_responder(uuid, uuid, text, timestamptz, integer) to service_role;
revoke all on function public.exclusividade_expirar(timestamptz) from public, anon, authenticated;
grant execute on function public.exclusividade_expirar(timestamptz) to service_role;
revoke all on function public.exclusividade_encerrar_por_pedido(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.exclusividade_encerrar_por_pedido(uuid, uuid, timestamptz) to service_role;

commit;
