-- Etapa B, rodada 2: FUNÇÕES SQL da exclusividade de 48h (docs/etapa-b-plano.md, seção 6).
-- Depende de 20261121100000_exclusividade_schema.sql (tabela exclusividades, carteira, tipos do livro, pedidos 'reservado').
-- Só funções: sem tabela nova, sem UPDATE de dados. O dinheiro (moedas) e a concorrência ficam aqui, atômicos.
-- Padrão das funções de reserva de desconto: SECURITY DEFINER, search_path = '', tudo qualificado,
-- execute só service_role, uma transação por chamada. Tudo recebe p_agora (testável).
-- Livro (moedas_lancamentos) é imutável: só INSERT, carteira 'profissional', chave de idempotência única.
-- NÃO mexe em moedas_orcamento_mensal/diario (exclusividade não usa o orçamento de desconto da empresa).
-- APLICADA no Supabase Trato em 2026-11-20 com o OK do João. Rollback em supabase/rollback/.
--
-- SALDO do profissional = soma de moedas_lancamentos.quantidade com carteira = 'profissional'
-- e (expira_em is null or expira_em > p_agora).
--
-- ORDEM DE LOCKS (a mesma nas 4 funções, para não haver deadlock):
--   1) pg_advisory_xact_lock('exclusividade:' || profissional)  — SÓ em exclusividade_solicitar, e sempre o PRIMEIRO lock;
--   2) linha de public.pedidos (for update; na rotina de expiração, for update SKIP LOCKED);
--   3) linha de public.exclusividades (for update / update condicional por status);
--   4) insert em moedas_lancamentos e pedido_historico (só inserts; sem lock de linha existente).
--   Nenhuma função pede o lock 1 depois de já segurar 2 ou 3, e nenhuma pede 2 depois de 3.
--   (Em responder e encerrar_por_pedido o id do pedido é lido ANTES, sem lock: pedido_id nunca muda na exclusividade.)
--
-- CORRIDAS COBERTAS:
--   * aceite do cliente no mesmo segundo da expiração: os dois pegam o lock do pedido; o segundo vê o status já mudado
--     (responder devolve 'prazo_vencido' se a oferta já foi expirada; a rotina simplesmente não processa de novo);
--   * dois cliques do profissional (mesma p_chave): o lock por profissional serializa; o 2º recebe 'ja_existe', sem cobrar;
--   * profissional com 100 moedas pedindo 2 exclusividades ao mesmo tempo: o lock por profissional serializa; o 2º vê saldo 0;
--   * dois profissionais no mesmo pedido: o lock do pedido + índice único parcial deixam só 1 em andamento ('pedido_indisponivel').
--
-- NOTA: as transições do pedido feitas aqui (aberto -> reservado no aceite; reservado -> aberto ao fim das 48h) também
-- gravam uma linha em pedido_historico (append-only; ator = cliente no aceite, nulo na rotina).
--
-- CONTRATO (todas returns table; nomes e valores exatos do plano):
--   public.exclusividade_solicitar(p_profissional uuid, p_pedido uuid, p_chave text, p_agora timestamptz,
--       p_custo integer, p_max_simultaneas integer, p_prazo_resposta_horas integer, p_bloqueio_recusa_dias integer)
--     returns table (resultado text, exclusividade_id uuid, responder_ate timestamptz, saldo_restante integer)
--     resultado: 'ok' | 'ja_existe' | 'saldo_insuficiente' | 'limite_simultaneas' | 'pedido_indisponivel' |
--                'pedido_urgente' | 'categoria_sem_exclusividade' | 'bloqueado_recusa' | 'proprio_pedido'.
--     Ordem das checagens: proprio_pedido, pedido_indisponivel, pedido_urgente, categoria_sem_exclusividade,
--     bloqueado_recusa, limite_simultaneas, saldo_insuficiente. Sempre devolve 1 linha. Nada muda se resultado <> 'ok'.
--     'ja_existe' devolve a exclusividade da mesma chave (saldo_restante = saldo atual). Chave de outro profissional = erro.
--   public.exclusividade_responder(p_exclusividade uuid, p_cliente uuid, p_decisao text, p_agora timestamptz,
--       p_duracao_horas integer) returns table (resultado text, expira_em timestamptz)
--     p_decisao: 'aceitar' | 'recusar' (outro valor = erro).
--     resultado: 'ok' | 'nao_encontrada' | 'ja_respondida' | 'prazo_vencido' | 'pedido_indisponivel'.
--     'prazo_vencido' também vale quando a oferta já foi expirada pela rotina. expira_em só vem preenchido no 'ok' do aceite.
--   public.exclusividade_expirar(p_agora timestamptz)
--     returns table (exclusividade_id uuid, motivo text, profissional_id uuid, cliente_id uuid, pedido_id uuid)
--     motivo: 'sem_resposta' (com estorno) | 'sem_atendimento' (sem estorno; pedido reservado -> aberto).
--   public.exclusividade_encerrar_por_pedido(p_pedido uuid, p_profissional_aceito uuid, p_agora timestamptz)
--     returns table (exclusividade_id uuid, resultado text, profissional_id uuid)
--     resultado: 'concluida' (profissional aceito = o da exclusividade; sem estorno) | 'cancelada' (estorno integral).
--     Sem exclusividade em andamento no pedido: devolve 0 linhas. NÃO muda o estado do pedido (é do backend).

begin;

-- 1) SOLICITAR -------------------------------------------------------------------------------------------------------
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

  select coalesce(sum(l.quantidade), 0) into v_saldo
    from public.moedas_lancamentos l
   where l.usuario_id = p_profissional and l.carteira = 'profissional'
     and (l.expira_em is null or l.expira_em > p_agora);

  -- idempotência por chave: devolve a existente, sem cobrar de novo
  select e.id, e.profissional_id, e.responder_ate into v_exist
    from public.exclusividades e where e.chave_idempotencia = p_chave;
  if found then
    if v_exist.profissional_id <> p_profissional then
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
       where e.profissional_id = p_profissional and e.status in ('aguardando_cliente', 'ativa')) >= p_max_simultaneas then
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

-- 2) RESPONDER -------------------------------------------------------------------------------------------------------
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
  select e.pedido_id, e.cliente_id into v_ini from public.exclusividades e where e.id = p_exclusividade;
  if not found or v_ini.cliente_id <> p_cliente then
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
      insert into public.moedas_lancamentos
        (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, criada_em)
      values (v_exc.profissional_id, 'exclusividade_estorno', v_exc.moedas_cobradas,
              'exclusividade-estorno:' || p_exclusividade::text, p_cliente, p_exclusividade, 'profissional', p_agora)
      on conflict (chave_idempotencia) do nothing;
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
      insert into public.moedas_lancamentos
        (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, criada_em)
      values (v_exc.profissional_id, 'exclusividade_estorno', v_exc.moedas_cobradas,
              'exclusividade-estorno:' || p_exclusividade::text, p_cliente, p_exclusividade, 'profissional', p_agora)
      on conflict (chave_idempotencia) do nothing;
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
      insert into public.moedas_lancamentos
        (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, criada_em)
      values (v_exc.profissional_id, 'exclusividade_estorno', v_exc.moedas_cobradas,
              'exclusividade-estorno:' || p_exclusividade::text, p_cliente, p_exclusividade, 'profissional', p_agora)
      on conflict (chave_idempotencia) do nothing;
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

-- 3) EXPIRAR (rotina) ------------------------------------------------------------------------------------------------
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
            where e.status = 'aguardando_cliente' and e.responder_ate < p_agora
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
    insert into public.moedas_lancamentos
      (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, criada_em)
    values (v_exc.profissional_id, 'exclusividade_estorno', v_exc.moedas_cobradas,
            'exclusividade-estorno:' || v_exc.id::text, v_exc.cliente_id, v_exc.id, 'profissional', p_agora)
    on conflict (chave_idempotencia) do nothing;
    return query select v_exc.id, 'sem_resposta'::text, v_exc.profissional_id, v_exc.cliente_id, v_exc.pedido_id;
  end loop;

  -- (b) exclusividade ativa que passou das horas sem atendimento: expira SEM estorno; pedido reservado -> aberto
  for r in select e.id, e.pedido_id from public.exclusividades e
            where e.status = 'ativa' and e.expira_em < p_agora
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

-- 4) ENCERRAR POR PEDIDO ---------------------------------------------------------------------------------------------
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
   where e.pedido_id = p_pedido and e.status in ('aguardando_cliente', 'ativa')
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
  insert into public.moedas_lancamentos
    (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, criada_em)
  values (v_exc.profissional_id, 'exclusividade_estorno', v_exc.moedas_cobradas,
          'exclusividade-estorno:' || v_exc.id::text, v_exc.cliente_id, v_exc.id, 'profissional', p_agora)
  on conflict (chave_idempotencia) do nothing;
  return query select v_exc.id, 'cancelada'::text, v_exc.profissional_id;
end;
$$;

-- Grants: só service_role executa.
revoke all on function public.exclusividade_solicitar(uuid, uuid, text, timestamptz, integer, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.exclusividade_responder(uuid, uuid, text, timestamptz, integer) from public, anon, authenticated;
revoke all on function public.exclusividade_expirar(timestamptz) from public, anon, authenticated;
revoke all on function public.exclusividade_encerrar_por_pedido(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.exclusividade_solicitar(uuid, uuid, text, timestamptz, integer, integer, integer, integer) to service_role;
grant execute on function public.exclusividade_responder(uuid, uuid, text, timestamptz, integer) to service_role;
grant execute on function public.exclusividade_expirar(timestamptz) to service_role;
grant execute on function public.exclusividade_encerrar_por_pedido(uuid, uuid, timestamptz) to service_role;

commit;
