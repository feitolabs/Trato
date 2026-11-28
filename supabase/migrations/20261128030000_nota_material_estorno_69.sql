-- ===========================================================================
-- 20261128030000_nota_material_estorno_69.sql
-- RASCUNHO (DB-69-MATERIAL). NÃO aplicada no Supabase de produção (OK do João só no código local).
-- Termos v1.2: 6.9, 6.10, 6.11 e 17.4. Regra aprovada pelo João em 28/11:
--   depois da aprovação 4-olhos o cliente recebe valor_reconhecido_centavos por estorno (pedido em
--   até 2 dias úteis); o custo do parcelamento volta na proporção do valor estornado; o que já foi
--   liberado ao profissional vira compensação em repasses futuros; material pago fora do app não
--   tem estorno automático (análise manual: NÃO chamar a função; fica 'pendente_financeiro').
-- Depende de 20261030120000_ordens_estorno, 20261125225400, 20261126061000 e 20261126195000.
--
-- Fluxo do backend, tudo NA MESMA TRANSAÇÃO:
--   1) travar o contrato (select ... from public.contratos ... for update);
--   2) gravar no livro o estorno da parte ainda RETIDA (se houver) e as ordens_estorno, com
--      chave 'nota-material/<contestacao_id>/<qualquer sufixo>' (uuid com ou sem hífens);
--      as ordens somam valor_reconhecido_centavos + custo do parcelamento proporcional;
--   3) chamar public.nota_material_executar_estorno(...). Resultado diferente de 'ok' e
--      'ja_executada': desfazer a transação inteira (as ordens e o livro do passo 2 não podem ficar).
--   O provedor só é chamado depois do commit.
-- Custo conferido pelas ordens da contestação (sem nenhuma: ordens_divergentes): em cada cobrança de onde sai dinheiro,
-- ordem * custo / cobrado, para baixo ou para cima, e o total limitado ao custo ainda em aberto
-- no livro antes desta contestação. custo_invalido devolve o máximo em maximo_centavos; depois
-- disso as ordens têm de somar valor reconhecido + custo.
-- p_valor_divida_centavos = parte do valor reconhecido que já tinha sido liberada (0 = tudo retido).
-- A função NÃO cria ordem de estorno nem lança a parte retida; ela confere, registra a dívida e
-- marca 'executado'. A dívida só é compensada depois de compensacao_avisar (17.4).
--
-- O banco NÃO sabe se um material foi pago fora do app (não há coluna para isso): quem decide é
-- a análise. Sem ordem de estorno no valor exato, nada é marcado como executado.
--
-- ATENÇÃO: o PRAZO de 2 dias úteis não é cobrado pelo banco; aprovada_em permite acompanhá-lo.
-- Só acrescenta (a única troca é a lista de origem_tipo, ampliada). Nenhum dado é alterado.
-- RLS ligada, sem policy; service_role só LÊ a tabela nova; escrita só pela função.
-- Rollback: supabase/rollback/20261128030000_nota_material_estorno_69_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.nota_material_contestacoes') is null
     or to_regclass('public.ordens_estorno') is null
     or to_regprocedure('public.compensacao_papel_ok(uuid,text[])') is null then
    raise exception 'Aplique antes ordens_estorno, 20261125225400, 20261126061000 e 20261126195000';
  end if;
end;
$$;

alter table public.compensacoes_dividas drop constraint if exists compensacoes_dividas_origem_tipo_check;
alter table public.compensacoes_dividas add constraint compensacoes_dividas_origem_tipo_check
  check (origem_tipo in ('disputa', 'disputa_contestacao', 'regresso', 'nota_material_contestacao'));
alter table public.compensacoes_dividas drop constraint if exists compensacoes_dividas_nota_material_check;
alter table public.compensacoes_dividas add constraint compensacoes_dividas_nota_material_check
  check (origem_tipo <> 'nota_material_contestacao'
         or (disputa_id is null and aprovada_por is not null and aprovada_por <> analista_id));

-- quando a aprovação foi gravada (base do prazo de 2 dias úteis). Linhas antigas ficam nulas.
alter table public.nota_material_contestacoes add column if not exists aprovada_em timestamptz;

create table if not exists public.nota_material_execucoes (
  contestacao_id               uuid primary key
                                 references public.nota_material_contestacoes (id) on delete restrict,
  contrato_id                  uuid not null references public.contratos (id) on delete restrict,
  valor_reconhecido_centavos   bigint not null check (valor_reconhecido_centavos > 0),
  valor_divida_centavos        bigint not null check (valor_divida_centavos >= 0),
  custo_parcelamento_centavos  bigint not null check (custo_parcelamento_centavos >= 0),
  total_estornado_centavos     bigint not null check (total_estornado_centavos > 0),
  divida_id                    uuid unique references public.compensacoes_dividas (id) on delete restrict,
  operador                     uuid not null references public.equipe (usuario_id) on delete restrict,
  motivo                       text not null check (btrim(motivo) <> ''),
  criada_em                    timestamptz not null default now(),
  constraint nota_material_execucoes_divida_check check (
    valor_divida_centavos <= valor_reconhecido_centavos
    and (divida_id is null) = (valor_divida_centavos = 0)),
  constraint nota_material_execucoes_total_check check (
    total_estornado_centavos = valor_reconhecido_centavos + custo_parcelamento_centavos)
);
create index if not exists ix_nota_material_execucoes_contrato
  on public.nota_material_execucoes (contrato_id);

drop trigger if exists nota_material_execucoes_imutavel on public.nota_material_execucoes;
create trigger nota_material_execucoes_imutavel before update or delete on public.nota_material_execucoes
  for each row execute function public.bloquear_alteracao();
drop trigger if exists nota_material_execucoes_sem_truncate on public.nota_material_execucoes;
create trigger nota_material_execucoes_sem_truncate before truncate on public.nota_material_execucoes
  for each statement execute function public.bloquear_alteracao();
alter table public.nota_material_execucoes enable row level security;
revoke all on table public.nota_material_execucoes from public, anon, authenticated, service_role;
grant select on table public.nota_material_execucoes to service_role;

-- roda depois de nota_contestacoes_validar_trg (os triggers seguem a ordem do nome)
create or replace function public.nota_material_contestacoes_efeito()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.aprovada_em := null;
    return new;
  end if;
  if old.aprovada_por is null and new.aprovada_por is not null then
    new.aprovada_em := now();
  else
    new.aprovada_em := old.aprovada_em;
  end if;
  if new.efeito_financeiro = 'executado' and old.efeito_financeiro <> 'executado'
     and not exists (select 1 from public.nota_material_execucoes x where x.contestacao_id = new.id) then
    raise exception 'nota_material_sem_execucao: use nota_material_executar_estorno'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.nota_material_contestacoes_efeito() from public, anon, authenticated, service_role;

drop trigger if exists nota_contestacoes_z_efeito_trg on public.nota_material_contestacoes;
create trigger nota_contestacoes_z_efeito_trg before insert or update on public.nota_material_contestacoes
  for each row execute function public.nota_material_contestacoes_efeito();

create or replace function public.nota_material_executar_estorno(
  p_contestacao uuid, p_valor_divida_centavos bigint, p_custo_parcelamento_centavos bigint,
  p_motivo text, p_operador uuid)
returns table (resultado text, divida_id uuid, maximo_centavos bigint)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_contrato uuid;
  v_c        record;
  v_feita    record;
  v_custo    record;
  v_ordens   bigint;
  v_total    bigint;
  v_aberto   bigint;
  v_prefixo  text;
  v_prefixo_hex text;
  v_div      record;
  v_divida   uuid;
begin
  if p_contestacao is null or p_valor_divida_centavos is null or p_custo_parcelamento_centavos is null
     or p_motivo is null or btrim(p_motivo) = '' or p_operador is null then
    raise exception 'contestação, valor da dívida, custo do parcelamento, motivo e operador são obrigatórios';
  end if;
  if not public.compensacao_papel_ok(p_operador, '{lider_suporte,administrador}') then
    return query select 'analista_invalido'::text, null::uuid, 0::bigint;
    return;
  end if;
  select n.contrato_id into v_contrato
    from public.nota_material_contestacoes k join public.notas_material n on n.id = k.nota_id
   where k.id = p_contestacao;
  if not found then
    return query select 'nao_encontrada'::text, null::uuid, 0::bigint;
    return;
  end if;
  -- mesma ordem de travas da compensação: contrato primeiro, depois a contestação
  perform 1 from public.contratos c where c.id = v_contrato for update;
  select k.status, k.analista_id, k.aprovada_por, k.efeito_financeiro, k.valor_reconhecido_centavos
    into v_c from public.nota_material_contestacoes k where k.id = p_contestacao for update;

  select x.valor_divida_centavos, x.custo_parcelamento_centavos, x.divida_id into v_feita
    from public.nota_material_execucoes x where x.contestacao_id = p_contestacao;
  if found then
    if v_feita.valor_divida_centavos = p_valor_divida_centavos
       and v_feita.custo_parcelamento_centavos = p_custo_parcelamento_centavos then
      return query select 'ja_executada'::text, v_feita.divida_id, v_feita.valor_divida_centavos;
    else
      return query select 'conflito'::text, v_feita.divida_id, v_feita.valor_divida_centavos;
    end if;
    return;
  end if;

  if v_c.status not in ('procedente', 'parcial') or v_c.aprovada_por is null
     or v_c.analista_id is null or v_c.aprovada_por = v_c.analista_id
     or v_c.efeito_financeiro <> 'pendente_financeiro' then
    return query select 'nao_elegivel'::text, null::uuid, 0::bigint;
    return;
  end if;
  if p_valor_divida_centavos < 0 or p_valor_divida_centavos > v_c.valor_reconhecido_centavos then
    return query select 'valor_invalido'::text, null::uuid, v_c.valor_reconhecido_centavos;
    return;
  end if;

  -- o cliente recebe o valor reconhecido e o custo: as ordens desta contestação somam os dois
  v_total := v_c.valor_reconhecido_centavos + p_custo_parcelamento_centavos;
  v_prefixo := 'nota-material/' || p_contestacao::text || '/';
  v_prefixo_hex := 'nota-material/' || replace(p_contestacao::text, '-', '') || '/';
  select coalesce(sum(o.valor_centavos), 0) into v_ordens
    from public.ordens_estorno o
   where o.contrato_id = v_contrato
     and (starts_with(o.chave_idempotencia, v_prefixo) or starts_with(o.chave_idempotencia, v_prefixo_hex));
  if v_ordens = 0 then
    return query select 'ordens_divergentes'::text, null::uuid, v_total;
    return;
  end if;

  -- custo ainda em aberto no livro ANTES desta contestação (o que ela mesma já lançou nesta
  -- transação, inclusive estorno e '/mantida/parcelamento', fica fora da conta)
  with livro as (
    select l.id, l.tipo, l.chave_idempotencia as chave, l.estorna_id,
           starts_with(l.chave_idempotencia, v_prefixo)
             or starts_with(l.chave_idempotencia, v_prefixo_hex) as desta,
           (select sum(pa.valor_centavos) from public.partidas pa
             where pa.lancamento_id = l.id and pa.sentido = 'debito') as valor
      from public.lancamentos l where l.contrato_id = v_contrato)
  select greatest(coalesce(sum(case when x.tipo = 'taxa' and x.chave like '%/parcelamento' then x.valor
                                    when x.tipo = 'reembolso' and x.chave like '%/custo-devolvido' then -x.valor
                               end), 0), 0)::bigint
    into v_aberto
    from livro x
   where not x.desta
     and not exists (select 1 from livro e where e.estorna_id = x.id and not e.desta);

  -- custo proporcional ao que sai de CADA cobrança: a ordem leva serviço + custo, então a parte
  -- do custo é ordem * custo / cobrado (para baixo ou para cima), sem passar do que está em aberto
  select least(coalesce(sum(floor(q.ordem::numeric * q.custo / q.cobrado)), 0), v_aberto)::bigint as minimo,
         least(coalesce(sum(ceil(q.ordem::numeric * q.custo / q.cobrado)), 0), v_aberto)::bigint as maximo
    into v_custo
    from (select sum(o.valor_centavos) as ordem, p.valor_centavos as cobrado,
                 coalesce((select sum(pa.valor_centavos)
                             from public.lancamentos l
                             join public.partidas pa on pa.lancamento_id = l.id and pa.sentido = 'debito'
                            where l.contrato_id = p.contrato_id and l.tipo = 'taxa'
                              and l.chave_idempotencia = p.chave_idempotencia || '/parcelamento'), 0) as custo
            from public.ordens_estorno o
            join public.pagamentos p on p.id = o.pagamento_id
           where o.contrato_id = v_contrato
             and (starts_with(o.chave_idempotencia, v_prefixo)
                  or starts_with(o.chave_idempotencia, v_prefixo_hex))
           group by p.id) q;
  if p_custo_parcelamento_centavos < v_custo.minimo or p_custo_parcelamento_centavos > v_custo.maximo then
    return query select 'custo_invalido'::text, null::uuid, v_custo.maximo;
    return;
  end if;
  if v_ordens <> v_total then
    return query select 'ordens_divergentes'::text, null::uuid, v_total;
    return;
  end if;

  if p_valor_divida_centavos > 0 then
    select * into v_div from public.compensacao_criar_divida(
      'nota_material_contestacao', p_contestacao, v_contrato, null, p_valor_divida_centavos,
      p_valor_divida_centavos, p_motivo, v_c.analista_id, v_c.aprovada_por, p_operador);
    if v_div.resultado <> 'ok' then
      return query select v_div.resultado::text, v_div.divida_id::uuid, v_div.maximo_centavos::bigint;
      return;
    end if;
    v_divida := v_div.divida_id;
  end if;

  insert into public.nota_material_execucoes
    (contestacao_id, contrato_id, valor_reconhecido_centavos, valor_divida_centavos,
     custo_parcelamento_centavos, total_estornado_centavos, divida_id, operador, motivo)
  values (p_contestacao, v_contrato, v_c.valor_reconhecido_centavos, p_valor_divida_centavos,
          p_custo_parcelamento_centavos, v_total, v_divida, p_operador, btrim(p_motivo));
  update public.nota_material_contestacoes set efeito_financeiro = 'executado' where id = p_contestacao;
  perform public.registrar_auditoria(
    p_operador, 'equipe', 'financeiro.material_estorno_executado', 'nota_material_contestacoes',
    p_contestacao, jsonb_build_object('efeito_financeiro', 'pendente_financeiro'),
    jsonb_build_object('efeito_financeiro', 'executado', 'total_estornado_centavos', v_total,
                       'valor_divida_centavos', p_valor_divida_centavos,
                       'custo_parcelamento_centavos', p_custo_parcelamento_centavos, 'divida_id', v_divida),
    btrim(p_motivo), null, null, null);
  return query select 'ok'::text, v_divida, p_valor_divida_centavos;
end;
$$;
revoke all on function public.nota_material_executar_estorno(uuid, bigint, bigint, text, uuid)
  from public, anon, authenticated;
grant execute on function public.nota_material_executar_estorno(uuid, bigint, bigint, text, uuid)
  to service_role;

commit;
