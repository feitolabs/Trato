-- ===========================================================================
-- 20261127220000_orcamento_validade_falha.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, 22.3: a validade do orçamento é prorrogada pelo tempo das falhas do app
-- OU do Parceiro de Pagamento. Mesma conta de backend/src/trato/disputas/
-- indisponibilidade.py `estender` (usada por api/validade.py): janelas que se sobrepõem
-- ou encostam contam uma vez; falha dentro da própria prorrogação conta; falha ativa
-- conta até p_agora e o prazo alcançado por ela não vence; no instante exato da
-- validade vigente o orçamento já venceu.
-- (Difere da 20261127213000, que segue `prorrogar`: só 'app', nulo = suspenso.)
--
-- Cria public.orcamento_validade_vigente e recria exclusividade_cliente_solicitar
-- (versão da 20261125223000), a única função SQL que compara orcamentos.validade_ate,
-- mudando só essa comparação. Assinatura igual. orcamentos.validade_ate não é alterada.
-- Sem UPDATE de dados ao aplicar; sem mudança em tabela, estorno ou livro.
--
-- Depende de 20261125223000 e 20261127205000. Se a 20261125223000 rodar de novo,
-- rodar esta de novo.
-- Rollback: supabase/rollback/20261127220000_orcamento_validade_falha_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.janelas_indisponibilidade') is null then
    raise exception 'Pré-requisito ausente: public.janelas_indisponibilidade (aplicar 20261127205000 primeiro).';
  end if;
  if to_regprocedure('public.exclusividade_cliente_solicitar(uuid,uuid,uuid,uuid,text,timestamptz,boolean)') is null then
    raise exception 'Pré-requisito ausente: aplicar 20261125223000 (exclusividade do cliente) primeiro.';
  end if;
end $$;

-- Validade vigente em p_agora. Sem data de envio ou de validade, devolve a validade como está.
create or replace function public.orcamento_validade_vigente(
  p_enviado_em timestamptz, p_validade_ate timestamptz, p_agora timestamptz)
returns timestamptz
language plpgsql stable security definer set search_path = ''
as $$
declare
  j        record;
  v_limite timestamptz := p_validade_ate;
  v_inicio timestamptz;  -- bloco unido em montagem
  v_fim    timestamptz;
  v_aberta timestamptz;  -- início mais antigo entre as falhas ativas consideradas
begin
  if p_agora is null then
    raise exception 'p_agora é obrigatório para a validade do orçamento';
  end if;
  if p_enviado_em is null or p_validade_ate is null or p_validade_ate <= p_enviado_em then
    return p_validade_ate;
  end if;

  for j in select i.inicio_em, coalesce(i.fim_em, p_agora) as fim_em, i.fim_em is null as ativa
             from public.janelas_indisponibilidade i
            where i.origem in ('app', 'pagamento')
              and (i.fim_em > p_enviado_em or (i.fim_em is null and i.inicio_em < p_agora))
            order by i.inicio_em
  loop
    if j.ativa and v_aberta is null then
      v_aberta := j.inicio_em;
    end if;
    if v_inicio is not null and j.inicio_em <= v_fim then
      v_fim := greatest(v_fim, j.fim_em);
      continue;
    end if;
    if v_inicio is not null and v_inicio <= v_limite and v_fim > p_enviado_em then
      v_limite := v_limite + (v_fim - greatest(v_inicio, p_enviado_em));
    end if;
    v_inicio := j.inicio_em;
    v_fim := j.fim_em;
  end loop;
  if v_inicio is not null and v_inicio <= v_limite and v_fim > p_enviado_em then
    v_limite := v_limite + (v_fim - greatest(v_inicio, p_enviado_em));
  end if;

  if v_limite <= p_agora and v_aberta <= v_limite then
    return p_agora + interval '1 microsecond';
  end if;
  return v_limite;
end;
$$;

revoke all on function public.orcamento_validade_vigente(timestamptz, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_validade_vigente(timestamptz, timestamptz, timestamptz) to service_role;

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
    select o.profissional_id, o.status, o.validade_ate, o.enviado_em into v_orc
      from public.orcamentos o where o.id = p_orcamento and o.pedido_id = p_pedido;
    if not found or v_orc.status <> 'enviado'
       -- 22.3: validade prorrogada por falha do app ou do pagamento (valor gravado não muda)
       or (v_orc.validade_ate is not null
           and public.orcamento_validade_vigente(v_orc.enviado_em, v_orc.validade_ate, p_agora) <= p_agora)
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

revoke all on function public.exclusividade_cliente_solicitar(uuid, uuid, uuid, uuid, text, timestamptz, boolean) from public, anon, authenticated;
grant execute on function public.exclusividade_cliente_solicitar(uuid, uuid, uuid, uuid, text, timestamptz, boolean) to service_role;

commit;
