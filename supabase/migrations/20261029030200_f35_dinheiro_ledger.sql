-- F3.5 — Dinheiro: pagamentos, webhooks, ledger de partidas dobradas, repasses, chaves Pix e saques.
-- Fonte: docs/modelo-de-dados.md, seção 7 (aprovado pelo João em 28/10/2026).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Só DDL. Sem seed: as contas de sistema do ledger (caixa_parceiro, retido_servico, receita_trato,
-- despesa_stripe, a_pagar_profissional) NÃO são criadas aqui, porque o desenho das contas depende de
-- P7 (Stripe Connect), P4 (30%) e P8 (fundo). Quem cria as contas é uma migration de seed futura, com OK.
-- RLS ligado e sem policy (F3.8). anon/authenticated sem acesso até a F3.8. Nenhuma tabela é escrita pelo app.
-- Depende da F3.3 e da F3.4. Reversão: supabase/rollback/F3.5_rollback.sql
--
-- Garantias do ledger:
--   * partidas e lançamentos nunca sofrem UPDATE, DELETE nem TRUNCATE (trigger + REVOKE);
--   * no fim da transação, soma dos débitos = soma dos créditos, com ao menos 2 partidas;
--   * um lançamento só recebe partidas na transação em que nasceu;
--   * só estorno corrige: novo lançamento com as partidas invertidas; um lançamento só é estornado uma vez.

-- ---------------------------------------------------------------------------
-- 7.1 pagamentos — cobranças ao cliente (nada de dado de cartão: só ids do Stripe)
-- ---------------------------------------------------------------------------
create table public.pagamentos (
  id                            uuid primary key default gen_random_uuid(),
  contrato_id                   uuid not null references public.contratos (id) on delete restrict,
  pagador_id                    uuid not null references public.usuarios (id) on delete restrict,
  tipo                          text not null check (tipo in ('adiantamento', 'saldo', 'etapa', 'aditivo')),
  etapa_id                      uuid references public.etapas (id) on delete restrict,
  aditivo_id                    uuid references public.aditivos (id) on delete restrict,
  meio                          text not null check (meio in ('pix', 'cartao_credito', 'cartao_debito')),
  parcelas                      smallint not null default 1 check (parcelas between 1 and 12),
  valor_centavos                bigint not null check (valor_centavos > 0),
  acrescimo_cliente_centavos    bigint not null default 0 check (acrescimo_cliente_centavos >= 0),  -- P3
  custo_stripe_estimado_centavos bigint check (custo_stripe_estimado_centavos is null
                                               or custo_stripe_estimado_centavos >= 0),
  custo_stripe_real_centavos    bigint check (custo_stripe_real_centavos is null or custo_stripe_real_centavos >= 0),
  status                        text not null default 'pendente'
                                  check (status in ('pendente', 'confirmado', 'falhou', 'expirado',
                                                    'reembolsado_parcial', 'reembolsado', 'contestado')),
  stripe_payment_intent_id      text unique,
  chave_idempotencia            text not null unique check (btrim(chave_idempotencia) <> ''),
  confirmado_em                 timestamptz,
  janela_chargeback_ate         timestamptz,
  criado_em                     timestamptz not null default now(),
  atualizado_em                 timestamptz not null default now(),
  check ((tipo = 'etapa') = (etapa_id is not null)),
  check ((tipo = 'aditivo') = (aditivo_id is not null)),
  check (meio = 'cartao_credito' or parcelas = 1),
  check (status = 'pendente' or status in ('falhou', 'expirado') or confirmado_em is not null)
);
create index pagamentos_contrato_tipo_idx on public.pagamentos (contrato_id, tipo);
create index pagamentos_status_idx on public.pagamentos (status);
create index pagamentos_pagador_idx on public.pagamentos (pagador_id);
create trigger pagamentos_atualizado_em before update on public.pagamentos
  for each row execute function public.definir_atualizado_em();
create trigger pagamentos_proteger before update on public.pagamentos
  for each row execute function public.proteger_colunas(
    'contrato_id', 'pagador_id', 'tipo', 'etapa_id', 'aditivo_id', 'meio', 'parcelas', 'valor_centavos',
    'chave_idempotencia', 'criado_em');
create trigger pagamentos_sem_delete before delete on public.pagamentos
  for each row execute function public.bloquear_alteracao();
create trigger pagamentos_sem_truncate before truncate on public.pagamentos
  for each statement execute function public.bloquear_alteracao();
alter table public.pagamentos enable row level security;

create or replace function public.pagamentos_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ctr public.contratos%rowtype;
begin
  if tg_op = 'UPDATE' then
    if old.stripe_payment_intent_id is not null
       and new.stripe_payment_intent_id is distinct from old.stripe_payment_intent_id then
      raise exception 'O id do PaymentIntent não pode mudar' using errcode = 'restrict_violation';
    end if;
    return new;
  end if;
  select * into ctr from public.contratos where id = new.contrato_id;
  -- Cartão e Pix só no CPF do próprio cliente (escopo 3.1).
  if new.pagador_id is distinct from ctr.cliente_id then
    raise exception 'Só o cliente do contrato paga' using errcode = 'check_violation';
  end if;
  if new.etapa_id is not null
     and not exists (select 1 from public.etapas where id = new.etapa_id and contrato_id = new.contrato_id) then
    raise exception 'A etapa é de outro contrato' using errcode = 'check_violation';
  end if;
  if new.aditivo_id is not null
     and not exists (select 1 from public.aditivos where id = new.aditivo_id and contrato_id = new.contrato_id
                     and status = 'aprovado') then
    raise exception 'O aditivo não é deste contrato ou não foi aprovado' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger pagamentos_validar_trg before insert or update on public.pagamentos
  for each row execute function public.pagamentos_validar();

-- ---------------------------------------------------------------------------
-- 7.2 eventos_webhook — assinados e sem repetição
-- ---------------------------------------------------------------------------
create table public.eventos_webhook (
  id                uuid primary key default gen_random_uuid(),
  provedor          text not null check (provedor in ('stripe')),
  evento_id         text not null,
  tipo              text not null,
  assinatura_valida boolean not null,
  payload           jsonb not null,  -- sem dados de cartão
  recebido_em       timestamptz not null default now(),
  processado_em     timestamptz,
  erro              text,
  unique (provedor, evento_id),
  -- Evento com assinatura inválida é guardado, mas nunca processado.
  check (assinatura_valida or processado_em is null)
);
create trigger eventos_webhook_proteger before update on public.eventos_webhook
  for each row execute function public.proteger_colunas(
    'provedor', 'evento_id', 'tipo', 'assinatura_valida', 'payload', 'recebido_em');
create trigger eventos_webhook_sem_delete before delete on public.eventos_webhook
  for each row execute function public.bloquear_alteracao();
alter table public.eventos_webhook enable row level security;

-- ---------------------------------------------------------------------------
-- 7.3 Ledger imutável de partidas dobradas
-- ---------------------------------------------------------------------------
create table public.contas_ledger (
  id         uuid primary key default gen_random_uuid(),
  codigo     text not null check (btrim(codigo) <> ''),
  natureza   text not null check (natureza in ('ativo', 'passivo', 'receita', 'despesa')),
  usuario_id uuid references public.usuarios (id) on delete restrict,
  moeda      char(3) not null default 'BRL' check (moeda = 'BRL'),
  criada_em  timestamptz not null default now()
);
-- Diferença do modelo aprovado: "codigo unique" não comporta a conta por usuário
-- (a_pagar_profissional existe uma vez por profissional). A unicidade é (codigo, usuario).
create unique index contas_ledger_codigo_usuario_idx
  on public.contas_ledger (codigo, (coalesce(usuario_id, '00000000-0000-0000-0000-000000000000'::uuid)));
create index contas_ledger_usuario_idx on public.contas_ledger (usuario_id) where usuario_id is not null;
create trigger contas_ledger_proteger before update on public.contas_ledger
  for each row execute function public.proteger_colunas('codigo', 'natureza', 'usuario_id', 'moeda', 'criada_em');
create trigger contas_ledger_sem_delete before delete on public.contas_ledger
  for each row execute function public.bloquear_alteracao();
create trigger contas_ledger_sem_truncate before truncate on public.contas_ledger
  for each statement execute function public.bloquear_alteracao();
alter table public.contas_ledger enable row level security;

create table public.lancamentos (
  id                 uuid primary key default gen_random_uuid(),
  -- Partidas dobradas por serviço. Nulo só no saque (não pertence a um contrato).
  contrato_id        uuid references public.contratos (id) on delete restrict,
  pagamento_id       uuid references public.pagamentos (id) on delete restrict,
  repasse_id         uuid,  -- FK adicionada abaixo (repasses é criada depois)
  saque_id           uuid,  -- FK adicionada abaixo
  disputa_id         uuid,  -- FK adicionada na F3.6
  tipo               text not null
                       check (tipo in ('cobranca', 'retencao', 'taxa', 'custo_stripe', 'repasse', 'saque',
                                       'reembolso', 'estorno')),
  estorna_id         uuid unique references public.lancamentos (id) on delete restrict,
  chave_idempotencia text not null unique check (btrim(chave_idempotencia) <> ''),
  descricao          text,
  ocorrido_em        timestamptz not null default now(),
  criado_por         uuid references public.usuarios (id) on delete restrict,  -- null = sistema
  criado_em          timestamptz not null default now(),
  check ((tipo = 'estorno') = (estorna_id is not null)),
  check (contrato_id is not null or tipo = 'saque')
);
create index lancamentos_contrato_idx on public.lancamentos (contrato_id);
create index lancamentos_pagamento_idx on public.lancamentos (pagamento_id) where pagamento_id is not null;
create trigger lancamentos_imutavel before update or delete on public.lancamentos
  for each row execute function public.bloquear_alteracao();
create trigger lancamentos_sem_truncate before truncate on public.lancamentos
  for each statement execute function public.bloquear_alteracao();
alter table public.lancamentos enable row level security;

-- criado_em é sempre a hora da transação: é por ela que se sabe se o lançamento ainda está "aberto".
create or replace function public.lancamentos_preparar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  original public.lancamentos%rowtype;
begin
  new.criado_em := now();
  if new.estorna_id is not null then
    select * into original from public.lancamentos where id = new.estorna_id;
    if original.contrato_id is distinct from new.contrato_id then
      raise exception 'O estorno deve ser do mesmo contrato do lançamento original' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
create trigger lancamentos_preparar_trg before insert on public.lancamentos
  for each row execute function public.lancamentos_preparar();

create table public.partidas (
  id             bigint generated always as identity primary key,
  lancamento_id  uuid not null references public.lancamentos (id) on delete restrict,
  conta_id       uuid not null references public.contas_ledger (id) on delete restrict,
  sentido        text not null check (sentido in ('debito', 'credito')),
  valor_centavos bigint not null check (valor_centavos > 0)
);
create index partidas_lancamento_idx on public.partidas (lancamento_id);
create index partidas_conta_idx on public.partidas (conta_id);
create trigger partidas_imutavel before update or delete on public.partidas
  for each row execute function public.bloquear_alteracao();
create trigger partidas_sem_truncate before truncate on public.partidas
  for each statement execute function public.bloquear_alteracao();
alter table public.partidas enable row level security;

-- Partida só entra na mesma transação do lançamento (depois de fechado, ninguém acrescenta nada).
create or replace function public.partidas_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from public.lancamentos where id = new.lancamento_id and criado_em = now()) then
    raise exception 'Lançamento % já fechado: não aceita novas partidas', new.lancamento_id
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
create trigger partidas_validar_trg before insert on public.partidas
  for each row execute function public.partidas_validar();

-- Equilíbrio conferido no COMMIT (constraint trigger adiado).
create or replace function public.ledger_conferir_equilibrio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  lanc uuid;
  debitos bigint;
  creditos bigint;
  qtd integer;
  lc public.lancamentos%rowtype;
  diferencas integer;
begin
  lanc := case when tg_table_name = 'lancamentos' then new.id else new.lancamento_id end;

  select coalesce(sum(valor_centavos) filter (where sentido = 'debito'), 0),
         coalesce(sum(valor_centavos) filter (where sentido = 'credito'), 0),
         count(*)
    into debitos, creditos, qtd
    from public.partidas where lancamento_id = lanc;

  if qtd < 2 then
    raise exception 'Lançamento % precisa de ao menos duas partidas (tem %)', lanc, qtd
      using errcode = 'check_violation';
  end if;
  if debitos <> creditos then
    raise exception 'Lançamento % desequilibrado: débitos % x créditos %', lanc, debitos, creditos
      using errcode = 'check_violation';
  end if;

  select * into lc from public.lancamentos where id = lanc;
  if lc.estorna_id is not null then
    select count(*) into diferencas from (
      (select conta_id,
              case sentido when 'debito' then 'credito' else 'debito' end as sentido_invertido,
              valor_centavos
         from public.partidas where lancamento_id = lc.estorna_id
       except all
       select conta_id, sentido, valor_centavos from public.partidas where lancamento_id = lanc)
      union all
      (select conta_id, sentido, valor_centavos from public.partidas where lancamento_id = lanc
       except all
       select conta_id,
              case sentido when 'debito' then 'credito' else 'debito' end,
              valor_centavos
         from public.partidas where lancamento_id = lc.estorna_id)
    ) d;
    if diferencas > 0 then
      raise exception 'O estorno % deve inverter exatamente as partidas do lançamento original', lanc
        using errcode = 'check_violation';
    end if;
  end if;
  return null;
end;
$$;
revoke execute on function public.ledger_conferir_equilibrio() from public, anon, authenticated;
create constraint trigger lancamentos_equilibrio after insert on public.lancamentos
  deferrable initially deferred for each row execute function public.ledger_conferir_equilibrio();
create constraint trigger partidas_equilibrio after insert on public.partidas
  deferrable initially deferred for each row execute function public.ledger_conferir_equilibrio();

-- Saldo nunca é coluna: sai das partidas. security_invoker = a RLS de quem consulta vale
-- (o profissional só enxerga as próprias contas; ver F3.8).
create view public.saldos_contas with (security_invoker = true) as
select conta_id, codigo, natureza, usuario_id, debitos_centavos, creditos_centavos,
       case when natureza in ('ativo', 'despesa')
            then debitos_centavos - creditos_centavos
            else creditos_centavos - debitos_centavos end as saldo_centavos
from (
  select c.id as conta_id, c.codigo, c.natureza, c.usuario_id,
         coalesce(sum(p.valor_centavos) filter (where p.sentido = 'debito'), 0)::bigint as debitos_centavos,
         coalesce(sum(p.valor_centavos) filter (where p.sentido = 'credito'), 0)::bigint as creditos_centavos
    from public.contas_ledger c
    left join public.partidas p on p.conta_id = c.id
   group by c.id, c.codigo, c.natureza, c.usuario_id
) s;

-- ---------------------------------------------------------------------------
-- 7.4 repasses
-- ---------------------------------------------------------------------------
create table public.repasses (
  id                       uuid primary key default gen_random_uuid(),
  contrato_id              uuid not null references public.contratos (id) on delete restrict,
  etapa_id                 uuid references public.etapas (id) on delete restrict,
  profissional_id          uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  valor_bruto_centavos     bigint not null check (valor_bruto_centavos > 0),
  taxa_centavos            bigint not null check (taxa_centavos >= 0),
  valor_liquido_centavos   bigint not null check (valor_liquido_centavos >= 0),
  gatilho                  text not null
                             check (gatilho in ('confirmacao_cliente', 'prazo', 'etapa_aprovada',
                                                'decisao_disputa', 'sinal_material')),
  status                   text not null default 'agendado'
                             check (status in ('agendado', 'congelado', 'liberado', 'estornado')),
  liberar_em               timestamptz,  -- P1: prazo ainda em decisão
  congelado_por_disputa_id uuid,         -- FK adicionada na F3.6
  lancamento_id            uuid references public.lancamentos (id) on delete restrict,
  chave_idempotencia       text not null unique check (btrim(chave_idempotencia) <> ''),
  criado_em                timestamptz not null default now(),
  liberado_em              timestamptz,
  check (valor_bruto_centavos = taxa_centavos + valor_liquido_centavos),
  check (status <> 'liberado' or (lancamento_id is not null and liberado_em is not null)),
  check (status <> 'congelado' or congelado_por_disputa_id is not null)
);
create index repasses_contrato_idx on public.repasses (contrato_id);
create index repasses_profissional_idx on public.repasses (profissional_id);
create index repasses_agendados_idx on public.repasses (liberar_em) where status = 'agendado';
create trigger repasses_proteger before update on public.repasses
  for each row execute function public.proteger_colunas(
    'contrato_id', 'etapa_id', 'profissional_id', 'valor_bruto_centavos', 'taxa_centavos',
    'valor_liquido_centavos', 'gatilho', 'chave_idempotencia', 'criado_em');
create trigger repasses_sem_delete before delete on public.repasses
  for each row execute function public.bloquear_alteracao();
create trigger repasses_sem_truncate before truncate on public.repasses
  for each statement execute function public.bloquear_alteracao();
alter table public.repasses enable row level security;

create or replace function public.repasses_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ctr public.contratos%rowtype;
begin
  select * into ctr from public.contratos where id = new.contrato_id;
  if new.profissional_id is distinct from ctr.profissional_id then
    raise exception 'O repasse deve ir para o profissional do contrato' using errcode = 'check_violation';
  end if;
  if new.etapa_id is not null
     and not exists (select 1 from public.etapas where id = new.etapa_id and contrato_id = new.contrato_id) then
    raise exception 'A etapa é de outro contrato' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger repasses_validar_trg before insert on public.repasses
  for each row execute function public.repasses_validar();

-- ---------------------------------------------------------------------------
-- 7.5 chaves_pix e saques
-- ---------------------------------------------------------------------------
create table public.chaves_pix (
  id                uuid primary key default gen_random_uuid(),
  usuario_id        uuid not null references public.usuarios (id) on delete restrict,
  tipo              text not null check (tipo in ('cpf', 'cnpj', 'email', 'telefone', 'aleatoria')),
  chave             text not null check (btrim(chave) <> ''),
  documento_titular text not null,
  verificada_em     timestamptz,
  ativa             boolean not null default true,
  criada_em         timestamptz not null default now(),
  unique (usuario_id, chave)
);
create trigger chaves_pix_proteger before update on public.chaves_pix
  for each row execute function public.proteger_colunas('usuario_id', 'tipo', 'chave', 'documento_titular', 'criada_em');
create trigger chaves_pix_sem_delete before delete on public.chaves_pix
  for each row execute function public.bloquear_alteracao();
alter table public.chaves_pix enable row level security;

-- O titular da chave precisa ser o próprio usuário (CPF ou CNPJ dele), escopo 8.1.
create or replace function public.chaves_pix_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  doc text := regexp_replace(new.documento_titular, '\D', '', 'g');
  cpf_dono text;
  cnpj_dono text;
begin
  select regexp_replace(cpf, '\D', '', 'g') into cpf_dono
    from public.usuarios_privados where usuario_id = new.usuario_id;
  select regexp_replace(cnpj, '\D', '', 'g') into cnpj_dono
    from public.perfis_profissional where usuario_id = new.usuario_id;
  if doc = '' or doc is distinct from cpf_dono and doc is distinct from cnpj_dono then
    raise exception 'O titular da chave Pix deve ser o próprio usuário (CPF ou CNPJ)' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger chaves_pix_validar_trg before insert on public.chaves_pix
  for each row execute function public.chaves_pix_validar();

create table public.saques (
  id                 uuid primary key default gen_random_uuid(),
  profissional_id    uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  chave_pix_id       uuid not null references public.chaves_pix (id) on delete restrict,
  valor_centavos     bigint not null check (valor_centavos > 0),
  taxa_saque_centavos bigint check (taxa_saque_centavos is null or taxa_saque_centavos >= 0),
  status             text not null default 'solicitado'
                       check (status in ('solicitado', 'em_analise', 'enviado', 'pago', 'falhou', 'estornado')),
  stripe_payout_id   text unique,
  chave_idempotencia text not null unique check (btrim(chave_idempotencia) <> ''),
  solicitado_em      timestamptz not null default now(),
  pago_em            timestamptz,
  lancamento_id      uuid references public.lancamentos (id) on delete restrict,
  check (status <> 'pago' or pago_em is not null)
);
create index saques_profissional_idx on public.saques (profissional_id, solicitado_em desc);
create trigger saques_proteger before update on public.saques
  for each row execute function public.proteger_colunas(
    'profissional_id', 'chave_pix_id', 'valor_centavos', 'chave_idempotencia', 'solicitado_em');
create trigger saques_sem_delete before delete on public.saques
  for each row execute function public.bloquear_alteracao();
create trigger saques_sem_truncate before truncate on public.saques
  for each statement execute function public.bloquear_alteracao();
alter table public.saques enable row level security;

-- Saque só para chave própria, ativa e verificada.
create or replace function public.saques_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  chave public.chaves_pix%rowtype;
begin
  select * into chave from public.chaves_pix where id = new.chave_pix_id;
  if chave.usuario_id is distinct from new.profissional_id then
    raise exception 'A chave Pix não é do profissional' using errcode = 'check_violation';
  end if;
  if not chave.ativa or chave.verificada_em is null then
    raise exception 'A chave Pix precisa estar ativa e verificada' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger saques_validar_trg before insert on public.saques
  for each row execute function public.saques_validar();

-- Agora que repasses e saques existem, fecha as FKs do lançamento.
alter table public.lancamentos
  add constraint lancamentos_repasse_fk foreign key (repasse_id) references public.repasses (id) on delete restrict,
  add constraint lancamentos_saque_fk foreign key (saque_id) references public.saques (id) on delete restrict;

-- ---------------------------------------------------------------------------
-- Acesso: sem app até a F3.8. Ledger sem UPDATE/DELETE/TRUNCATE nem para o service_role.
-- ---------------------------------------------------------------------------
revoke all on table public.pagamentos, public.eventos_webhook, public.contas_ledger, public.lancamentos,
  public.partidas, public.repasses, public.chaves_pix, public.saques, public.saldos_contas
  from public, anon, authenticated;
revoke update, delete, truncate on table public.lancamentos, public.partidas from service_role;
revoke delete, truncate on table public.pagamentos, public.eventos_webhook, public.contas_ledger,
  public.repasses, public.chaves_pix, public.saques from service_role;
