-- ===========================================================================
-- 20261125150000_moedas_saldo_e_estorno_validade.sql
-- RASCUNHO (TERMOS-DB2). NÃO aplicada no Supabase de produção. Aguarda OK do João.
--
-- Objetivo:
--   1. Criar `public.moedas_saldo(p_usuario, p_carteira, p_agora)` com a MESMA regra
--      de `backend/src/trato/api/moedas_saldo.py` (Termos 13.4): cada gasto consome
--      créditos válidos no instante do gasto, vencimento mais próximo primeiro (sem
--      prazo por último); crédito vencido só perde o resto não gasto e nunca deixa
--      saldo negativo.
--   2. Criar `public.moedas_parcelas_gasto` e `public.exclusividade_estornar_moedas`
--      para que todo estorno de exclusividade em SQL devolva os Tratinhos com a
--      validade original de cada parcela consumida, ou novo crédito de 30 dias se
--      a validade original já tiver vencido (Termos 13.8). Só devolve se o débito
--      'exclusividade-uso:<id>' existir na própria carteira, no máximo o valor debitado.
--      A 1ª parcela usa a chave 'exclusividade-estorno:<id>'; as demais, '...:2', '...:3'.
--   3. Atualizar `public.moedas_reservar_desconto` (20261121100000) e as funções de
--      exclusividade (`exclusividade_solicitar`, `exclusividade_responder`,
--      `exclusividade_expirar`, `exclusividade_encerrar_por_pedido`, 20261121200000)
--      para usar `public.moedas_saldo` e `public.exclusividade_estornar_moedas`,
--      preservando assinaturas, travas (advisory locks / FOR UPDATE), atomicidade e grants.
--   4. Inserir a definição `'prazo_avaliacao_dias'` em `public.config_definicoes`
--      (`on conflict (chave) do nothing`).
--
-- Padrão: transação única, idempotente, SECURITY DEFINER com `search_path = ''`,
-- EXECUTE restrito a `service_role` (`exclusividade_estornar_moedas`: a ninguém, é interna), livro `moedas_lancamentos` continua imutável.
--
-- Rollback: supabase/rollback/20261125150000_moedas_saldo_e_estorno_validade_rollback.sql
--
-- LIMITE: as 4 funções de exclusividade continuam sendo as da exclusividade paga pelo
-- PROFISSIONAL. A paga pelo cliente (20261125141500) precisa de fluxo próprio.
--
-- CONFERÊNCIA (somente leitura, depois de aplicar):
-- [1] esperado: 8 linhas, secdef = t, config = {search_path=""}, anon = f, auth = f, svc = t (menos exclusividade_estornar_moedas, interna: svc = f)
-- select p.proname, p.prosecdef as secdef, p.proconfig as config,
--        has_function_privilege('anon', p.oid, 'execute') as anon,
--        has_function_privilege('authenticated', p.oid, 'execute') as auth,
--        has_function_privilege('service_role', p.oid, 'execute') as svc,
--        p.prosrc like '%public.moedas_saldo(%' as usa_saldo,
--        p.prosrc like '%public.exclusividade_estornar_moedas(%' as usa_estorno
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public' and p.proname in ('moedas_saldo', 'moedas_parcelas_gasto',
--        'exclusividade_estornar_moedas', 'moedas_reservar_desconto', 'exclusividade_solicitar',
--        'exclusividade_responder', 'exclusividade_expirar', 'exclusividade_encerrar_por_pedido')
--  order by 1;
-- [2] esperado: 1 linha (dias, 1, 90, {global}, f)
-- select unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao
--   from public.config_definicoes where chave = 'prazo_avaliacao_dias';
-- [3] quem muda de saldo com a regra nova (saldo_novo nunca negativo)
-- select usuario_id, carteira,
--        coalesce(sum(quantidade) filter (where expira_em is null or expira_em > now()), 0) as saldo_antigo,
--        public.moedas_saldo(usuario_id, carteira, now()) as saldo_novo
--   from public.moedas_lancamentos group by usuario_id, carteira;
-- [4] esperado: mesmo número antes e depois de aplicar
-- select count(*) from public.moedas_lancamentos;
-- ===========================================================================

begin;

-- TRAVA DE ORDEM (sem opção de forçar): com a exclusividade do cliente instalada, recolocar
-- estas funções tiraria o filtro por pagador e criaria Tratinhos para o profissional.
do $$
begin
  if to_regprocedure('public.orcamentos_exclusividade_cliente()') is not null then
    raise exception 'Rode antes o rollback da 20261125223000_exclusividade_cliente';
  end if;
end;
$$;

create or replace function public.moedas_saldo(
  p_usuario  uuid,
  p_carteira text,
  p_agora    timestamptz default now()
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r         record;
  v_criada  timestamptz[] := '{}';
  v_expira  timestamptz[] := '{}';
  v_resto   bigint[]      := '{}';
  v_n       integer       := 0;
  v_devendo bigint        := 0;
  v_pago    bigint;
  v_falta   bigint;
  v_tirado  bigint;
  v_idx     integer;
  v_saldo   bigint        := 0;
begin
  if p_usuario is null or p_carteira is null
     or p_carteira not in ('cliente', 'profissional')
     or p_agora is null then
    raise exception 'parâmetros inválidos para moedas_saldo';
  end if;

  for r in
    select l.criada_em, l.expira_em, l.quantidade, l.chave_idempotencia
      from public.moedas_lancamentos l
     where l.usuario_id = p_usuario
       and l.carteira = p_carteira
     order by l.criada_em asc, (l.quantidade < 0) asc, l.chave_idempotencia collate "C" asc
  loop
    if r.quantidade > 0 then
      v_pago := least(r.quantidade::bigint, v_devendo);
      v_devendo := v_devendo - v_pago;
      v_n := v_n + 1;
      v_criada[v_n] := r.criada_em;
      v_expira[v_n] := r.expira_em;
      v_resto[v_n]  := r.quantidade::bigint - v_pago;
    else
      v_falta := (-r.quantidade)::bigint;

      if v_n > 0 and v_falta > 0 then
        for v_idx in
          select i
            from generate_series(1, v_n) as g(i)
           where v_resto[i] > 0
             and (v_expira[i] is null or v_expira[i] > r.criada_em)
           order by (v_expira[i] is null) asc, v_expira[i] asc nulls last, v_criada[i] asc, i asc
        loop
          v_tirado := least(v_resto[v_idx], v_falta);
          if v_tirado > 0 then
            v_resto[v_idx] := v_resto[v_idx] - v_tirado;
            v_falta := v_falta - v_tirado;
          end if;
          exit when v_falta = 0;
        end loop;
      end if;

      if v_n > 0 and v_falta > 0 then
        for v_idx in
          select i
            from generate_series(1, v_n) as g(i)
           where v_resto[i] > 0
             and v_expira[i] is not null
             and v_expira[i] <= r.criada_em
           order by v_expira[i] desc, v_criada[i] desc, i asc
        loop
          v_tirado := least(v_resto[v_idx], v_falta);
          if v_tirado > 0 then
            v_resto[v_idx] := v_resto[v_idx] - v_tirado;
            v_falta := v_falta - v_tirado;
          end if;
          exit when v_falta = 0;
        end loop;
      end if;

      v_devendo := v_devendo + v_falta;
    end if;
  end loop;

  if v_n > 0 then
    for v_idx in 1..v_n loop
      if v_resto[v_idx] > 0 and (v_expira[v_idx] is null or v_expira[v_idx] > p_agora) then
        v_saldo := v_saldo + v_resto[v_idx];
      end if;
    end loop;
  end if;

  return v_saldo;
end;
$$;

create or replace function public.moedas_parcelas_gasto(
  p_usuario  uuid,
  p_carteira text,
  p_chave    text
)
returns table (quantidade integer, expira_em timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r         record;
  v_criada  timestamptz[] := '{}';
  v_expira  timestamptz[] := '{}';
  v_resto   bigint[]      := '{}';
  v_n       integer       := 0;
  v_devendo bigint        := 0;
  v_pago    bigint;
  v_falta   bigint;
  v_tirado  bigint;
  v_idx     integer;
begin
  if p_usuario is null or p_carteira is null
     or p_carteira not in ('cliente', 'profissional')
     or p_chave is null or btrim(p_chave) = '' then
    raise exception 'parâmetros inválidos para moedas_parcelas_gasto';
  end if;

  for r in
    select l.criada_em, l.expira_em, l.quantidade, l.chave_idempotencia
      from public.moedas_lancamentos l
     where l.usuario_id = p_usuario
       and l.carteira = p_carteira
     order by l.criada_em asc, (l.quantidade < 0) asc, l.chave_idempotencia collate "C" asc
  loop
    if r.quantidade > 0 then
      v_pago := least(r.quantidade::bigint, v_devendo);
      v_devendo := v_devendo - v_pago;
      v_n := v_n + 1;
      v_criada[v_n] := r.criada_em;
      v_expira[v_n] := r.expira_em;
      v_resto[v_n]  := r.quantidade::bigint - v_pago;
    else
      v_falta := (-r.quantidade)::bigint;

      if v_n > 0 and v_falta > 0 then
        for v_idx in
          select i
            from generate_series(1, v_n) as g(i)
           where v_resto[i] > 0
             and (v_expira[i] is null or v_expira[i] > r.criada_em)
           order by (v_expira[i] is null) asc, v_expira[i] asc nulls last, v_criada[i] asc, i asc
        loop
          v_tirado := least(v_resto[v_idx], v_falta);
          if v_tirado > 0 then
            v_resto[v_idx] := v_resto[v_idx] - v_tirado;
            v_falta := v_falta - v_tirado;
            if r.chave_idempotencia = p_chave then
              return query select v_tirado::integer, v_expira[v_idx];
            end if;
          end if;
          exit when v_falta = 0;
        end loop;
      end if;

      if v_n > 0 and v_falta > 0 then
        for v_idx in
          select i
            from generate_series(1, v_n) as g(i)
           where v_resto[i] > 0
             and v_expira[i] is not null
             and v_expira[i] <= r.criada_em
           order by v_expira[i] desc, v_criada[i] desc, i asc
        loop
          v_tirado := least(v_resto[v_idx], v_falta);
          if v_tirado > 0 then
            v_resto[v_idx] := v_resto[v_idx] - v_tirado;
            v_falta := v_falta - v_tirado;
            if r.chave_idempotencia = p_chave then
              return query select v_tirado::integer, v_expira[v_idx];
            end if;
          end if;
          exit when v_falta = 0;
        end loop;
      end if;

      v_devendo := v_devendo + v_falta;
    end if;
  end loop;

  return;
end;
$$;

create or replace function public.exclusividade_estornar_moedas(
  p_usuario       uuid,
  p_carteira      text,
  p_exclusividade uuid,
  p_parceiro      uuid,
  p_moedas        integer,
  p_agora         timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chave_base text := 'exclusividade-estorno:' || p_exclusividade::text;
  v_chave_uso  text := 'exclusividade-uso:' || p_exclusividade::text;
  v_idx        integer := 0;
  v_estornado  integer := 0;
  v_chave      text;
  v_expira     timestamptz;
  v_devido     integer;
  v_parte      integer;
  r            record;
begin
  if p_usuario is null or p_carteira is null
     or p_carteira not in ('cliente', 'profissional')
     or p_exclusividade is null or p_moedas is null or p_moedas <= 0 or p_agora is null then
    raise exception 'parâmetros inválidos para exclusividade_estornar_moedas';
  end if;

  if exists (select 1 from public.moedas_lancamentos where chave_idempotencia = v_chave_base) then
    return;
  end if;

  -- Só devolve o que saiu DESTA carteira: sem o débito 'exclusividade-uso:<id>' em nome de
  -- p_usuario não há o que devolver (não cria Tratinhos para quem não pagou, ex.: exclusividade
  -- paga pelo cliente). Nunca devolve mais do que foi debitado.
  select least(p_moedas, -l.quantidade) into v_devido
    from public.moedas_lancamentos l
   where l.chave_idempotencia = v_chave_uso
     and l.usuario_id = p_usuario
     and l.carteira = p_carteira
     and l.quantidade < 0;
  if not found then
    return;
  end if;

  for r in
    select p.quantidade, p.expira_em
      from public.moedas_parcelas_gasto(p_usuario, p_carteira, v_chave_uso) p
  loop
    v_parte := least(r.quantidade, v_devido - v_estornado);
    exit when v_parte <= 0;
    v_idx := v_idx + 1;
    v_chave := case when v_idx = 1 then v_chave_base else v_chave_base || ':' || v_idx::text end;
    v_expira := case
      when r.expira_em is null then null
      when r.expira_em > p_agora then r.expira_em
      else p_agora + interval '30 days'
    end;

    insert into public.moedas_lancamentos
      (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, expira_em, criada_em)
    values (p_usuario, 'exclusividade_estorno', v_parte, v_chave,
            p_parceiro, p_exclusividade, p_carteira, v_expira, p_agora)
    on conflict (chave_idempotencia) do nothing;

    v_estornado := v_estornado + v_parte;
  end loop;

  -- débito sem crédito de origem (dado antigo): trata como vencido (30 dias), como no Python
  if v_estornado < v_devido then
    v_idx := v_idx + 1;
    v_chave := case when v_idx = 1 then v_chave_base else v_chave_base || ':' || v_idx::text end;
    insert into public.moedas_lancamentos
      (usuario_id, tipo, quantidade, chave_idempotencia, parceiro_id, referencia_id, carteira, expira_em, criada_em)
    values (p_usuario, 'exclusividade_estorno', v_devido - v_estornado, v_chave,
            p_parceiro, p_exclusividade, p_carteira, p_agora + interval '30 days', p_agora)
    on conflict (chave_idempotencia) do nothing;
  end if;
end;
$$;

create or replace function public.moedas_reservar_desconto(
  p_cobranca uuid, p_usuario uuid, p_mes date, p_dia date, p_moedas integer,
  p_desconto_centavos integer, p_orcamento_mes_centavos integer, p_teto_dia_centavos integer,
  p_teto_cliente_mes_centavos integer, p_max_reservas_abertas integer, p_expira_em timestamptz)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_mes     date;
  v_rows    integer;
  v_saldo   bigint;
  v_abertas integer;
  v_no_mes  bigint;
begin
  if p_cobranca is null or p_usuario is null or p_mes is null or p_dia is null
     or p_moedas is null or p_moedas <= 0 or p_desconto_centavos is null or p_desconto_centavos <= 0
     or p_orcamento_mes_centavos is null or p_teto_dia_centavos is null
     or p_teto_cliente_mes_centavos is null or p_max_reservas_abertas is null or p_expira_em is null then
    raise exception 'parâmetros inválidos para reserva de desconto';
  end if;
  v_mes := date_trunc('month', p_mes)::date;

  perform pg_advisory_xact_lock(hashtextextended(p_usuario::text, 0));

  if exists (select 1 from public.moedas_reservas where cobranca_id = p_cobranca) then
    return 'ja_reservada';
  end if;

  v_saldo := public.moedas_saldo(p_usuario, 'cliente', now());
  v_saldo := v_saldo - coalesce((select sum(moedas) from public.moedas_reservas
                                  where usuario_id = p_usuario and status = 'reservada'), 0);
  if v_saldo < p_moedas then
    return 'saldo_insuficiente';
  end if;

  select count(*) into v_abertas from public.moedas_reservas
   where usuario_id = p_usuario and status = 'reservada';
  if v_abertas >= p_max_reservas_abertas then
    return 'reservas_abertas';
  end if;

  select coalesce(sum(desconto_centavos), 0) into v_no_mes from public.moedas_reservas
   where usuario_id = p_usuario and mes_ref = v_mes and status in ('reservada', 'confirmada');
  if v_no_mes + p_desconto_centavos > p_teto_cliente_mes_centavos then
    return 'teto_cliente';
  end if;

  insert into public.moedas_orcamento_mensal (mes_ref) values (v_mes) on conflict (mes_ref) do nothing;
  insert into public.moedas_orcamento_diario (dia_ref) values (p_dia) on conflict (dia_ref) do nothing;

  update public.moedas_orcamento_diario
     set usado_centavos = usado_centavos + p_desconto_centavos, atualizado_em = now()
   where dia_ref = p_dia and usado_centavos + p_desconto_centavos <= p_teto_dia_centavos;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return 'limite_diario';
  end if;

  update public.moedas_orcamento_mensal
     set usado_centavos = usado_centavos + p_desconto_centavos, atualizado_em = now()
   where mes_ref = v_mes and usado_centavos + p_desconto_centavos <= p_orcamento_mes_centavos;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    update public.moedas_orcamento_diario
       set usado_centavos = usado_centavos - p_desconto_centavos, atualizado_em = now()
     where dia_ref = p_dia;
    return 'orcamento_esgotado';
  end if;

  insert into public.moedas_reservas
    (cobranca_id, usuario_id, mes_ref, dia_ref, moedas, desconto_centavos, expira_em)
  values (p_cobranca, p_usuario, v_mes, p_dia, p_moedas, p_desconto_centavos, p_expira_em);
  return 'ok';
end;
$$;

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

  v_saldo := public.moedas_saldo(p_profissional, 'profissional', p_agora);

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
    perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', v_exc.id, v_exc.cliente_id, v_exc.moedas_cobradas, p_agora);
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
  perform public.exclusividade_estornar_moedas(v_exc.profissional_id, 'profissional', v_exc.id, v_exc.cliente_id, v_exc.moedas_cobradas, p_agora);
  return query select v_exc.id, 'cancelada'::text, v_exc.profissional_id;
end;
$$;

-- Definição de 'prazo_avaliacao_dias' em public.config_definicoes
insert into public.config_definicoes
  (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values (
  'prazo_avaliacao_dias',
  'Prazo em dias após a conclusão do serviço para cliente e profissional avaliarem',
  'dias',
  1,
  90,
  array['global'],
  false
)
on conflict (chave) do nothing;

-- Grants: execute somente para service_role
revoke all on function public.moedas_saldo(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.moedas_parcelas_gasto(uuid, text, text) from public, anon, authenticated;
revoke all on function public.exclusividade_estornar_moedas(uuid, text, uuid, uuid, integer, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.moedas_reservar_desconto(uuid, uuid, date, date, integer, integer, integer, integer, integer, integer, timestamptz) from public, anon, authenticated;
revoke all on function public.exclusividade_solicitar(uuid, uuid, text, timestamptz, integer, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.exclusividade_responder(uuid, uuid, text, timestamptz, integer) from public, anon, authenticated;
revoke all on function public.exclusividade_expirar(timestamptz) from public, anon, authenticated;
revoke all on function public.exclusividade_encerrar_por_pedido(uuid, uuid, timestamptz) from public, anon, authenticated;

grant execute on function public.moedas_saldo(uuid, text, timestamptz) to service_role;
grant execute on function public.moedas_parcelas_gasto(uuid, text, text) to service_role;
grant execute on function public.moedas_reservar_desconto(uuid, uuid, date, date, integer, integer, integer, integer, integer, integer, timestamptz) to service_role;
grant execute on function public.exclusividade_solicitar(uuid, uuid, text, timestamptz, integer, integer, integer, integer) to service_role;
grant execute on function public.exclusividade_responder(uuid, uuid, text, timestamptz, integer) to service_role;
grant execute on function public.exclusividade_expirar(timestamptz) to service_role;
grant execute on function public.exclusividade_encerrar_por_pedido(uuid, uuid, timestamptz) to service_role;

commit;
