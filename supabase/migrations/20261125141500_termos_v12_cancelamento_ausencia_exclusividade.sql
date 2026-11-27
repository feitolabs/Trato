-- ===========================================================================
-- 20261125141500_termos_v12_cancelamento_ausencia_exclusividade.sql
-- RASCUNHO (TERMOS-DB1). NÃO aplicada no Supabase de produção. Aguarda OK do João.
--
-- Referência jurídica: docs/juridico/termos-de-uso-v1.2.txt (7.2-7.6, 7.9, 13.6, I.4)
-- e docs/juridico/termos-v1.2-ajustes.md (decisões do João em 25/11/2026).
--
-- O que JÁ existia (não duplicado):
--   - Momento da contratação: `public.contratos.aceito_em` (já existe e é imutável).
--   - Registro imutável de chegada/ausência: `public.presencas` (já aceita
--     `tipo in ('check_in', 'check_out', 'cliente_ausente')`).
--   - Livro de Tratinhos e config de exclusividade: `public.moedas_lancamentos`
--     (já tem `carteira in ('cliente', 'profissional')` e tipos `'exclusividade_uso'`
--     e `'exclusividade_estorno'`) e `public.moedas_config` (já tem
--     `exclusividade_custo_moedas = 100` e `exclusividade_duracao_horas = 48`).
--
-- Mudanças desta migration (100% aditivas, idempotentes, sem UPDATE de dados):
--   1. `public.config_definicoes`: amplia `config_definicoes_unidade_check` para
--      incluir `'minutos'` (necessário para o prazo de espera de 20 min).
--   2. `public.contratos`: adiciona `consentimento_execucao_imediata boolean not null default false`
--      e `consentimento_execucao_imediata_em timestamptz` (cláusula 7.3), com check
--      exigindo timestamp quando `true` e NULL quando `false`.
--   3. `public.cancelamentos_pedido`: nova tabela para pedido de desistência (7.2/7.3),
--      cancelamento tardio com proposta de retenção limitada a 30% / `retencao_limite_bps`
--      (valor em centavos, justificativa, comprovantes, ciência/aceite do cliente) e
--      decisão do analista (7.3/7.4/7.6/7.9). RLS ligada, sem policy, grants só `service_role`.
--   4. `public.ausencias_cliente`: nova tabela para o fluxo da cláusula 7.6 (chegada,
--      espera mínima de 20 min validada em CHECK, aviso ao cliente, prazo de 24 h para
--      justificar, justificativa/comprovantes e decisão do analista). RLS ligada, sem
--      policy, grants só `service_role`.
--   5. `public.exclusividades`: evolução retrocompatível da tabela atual (preserva
--      registros existentes do profissional) para suportar a exclusividade paga pelo
--      CLIENTE (100 Tratinhos / 48 h, cláusulas 13.6 e I.4), com `pagador`, `orcamento_id`,
--      `motivo_encerramento`, `estornada`, `estornada_em`, `estorno_lancamento_id`,
--      novo status `'expirada_sem_contratacao'` e CHECK travando estorno do cliente
--      somente em `'falha_trato'` ou `'desistencia_profissional'`.
--
-- CONFIGURAÇÃO DE DADOS (NÃO executada nesta migration; rodar só com OK do João
-- via fluxo oficial de config_definicoes / nova config_versoes):
--   insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao) values
--     ('arrependimento_dias',                'Prazo legal de arrependimento (CDC art. 49)',              'dias',    7,    30,   array['global'], false),
--     ('cancelamento_sem_retencao_horas',    'Antecedência mínima para cancelamento sem retenção',       'horas',   1,    168,  array['global'], false),
--     ('retencao_cancelamento_max_bps',      'Teto de retenção por custos comprovados (3000 = 30%)',     'bps',     0,    3000, array['global'], true),
--     ('espera_cliente_ausente_minutos',     'Tempo mínimo de espera após check-in antes de ausência',   'minutos', 20,   120,  array['global'], false),
--     ('justificativa_cliente_ausente_horas','Prazo para o cliente justificar ausência após aviso',      'horas',   24,   168,  array['global'], false)
--   on conflict (chave) do nothing;
--   -- Valores iniciais na nova versão de config_parametros:
--   --   arrependimento_dias = 7
--   --   cancelamento_sem_retencao_horas = 24
--   --   retencao_cancelamento_max_bps = 3000
--   --   espera_cliente_ausente_minutos = 20
--   --   justificativa_cliente_ausente_horas = 24
--   -- Exclusividade em public.moedas_config já tem:
--   --   exclusividade_custo_moedas = 100, exclusividade_duracao_horas = 48.
--
-- Rollback: supabase/rollback/20261125141500_termos_v12_cancelamento_ausencia_exclusividade_rollback.sql
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1) config_definicoes: aceitar unidade 'minutos'
-- ---------------------------------------------------------------------------
alter table public.config_definicoes
  drop constraint if exists config_definicoes_unidade_check;
alter table public.config_definicoes
  add constraint config_definicoes_unidade_check
  check (unidade in ('centavos', 'bps', 'minutos', 'horas', 'dias', 'dias_uteis', 'quantidade'));

-- ---------------------------------------------------------------------------
-- 2) contratos: consentimento expresso de execução antes dos 7 dias (7.3)
-- ---------------------------------------------------------------------------
alter table public.contratos
  add column if not exists consentimento_execucao_imediata boolean not null default false,
  add column if not exists consentimento_execucao_imediata_em timestamptz;

alter table public.contratos
  drop constraint if exists contratos_consentimento_execucao_check;
alter table public.contratos
  add constraint contratos_consentimento_execucao_check
  check (
    (consentimento_execucao_imediata = false and consentimento_execucao_imediata_em is null)
    or (consentimento_execucao_imediata = true and consentimento_execucao_imediata_em is not null)
  );

-- escrita única: só de falso para verdadeiro, uma vez, antes do início do serviço; a data é
-- sempre now() do banco (o valor enviado é ignorado)
create or replace function public.contratos_consentimento_unico()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.consentimento_execucao_imediata then
    if (new.consentimento_execucao_imediata, new.consentimento_execucao_imediata_em)
       is distinct from (old.consentimento_execucao_imediata, old.consentimento_execucao_imediata_em) then
      raise exception 'O consentimento de execução imediata já foi registrado e não muda'
        using errcode = 'restrict_violation';
    end if;
    return new;
  end if;
  if not new.consentimento_execucao_imediata then
    return new;
  end if;
  if new.status in ('concluido', 'cancelado', 'em_disputa')
     or exists (select 1 from public.pedidos p where p.id = new.pedido_id
                 and p.status in ('em_andamento', 'em_confirmacao', 'concluido', 'cancelado',
                                  'em_disputa', 'retrabalho'))
     or exists (select 1 from public.presencas pr
                  join public.agendamentos ag on ag.id = pr.agendamento_id
                 where ag.contrato_id = new.id and pr.tipo = 'check_in') then
    raise exception 'Consentimento só antes do início do serviço' using errcode = 'check_violation';
  end if;
  new.consentimento_execucao_imediata_em := now();
  return new;
end;
$$;
revoke all on function public.contratos_consentimento_unico() from public, anon, authenticated, service_role;
drop trigger if exists contratos_consentimento_unico_trg on public.contratos;
create trigger contratos_consentimento_unico_trg before insert or update on public.contratos
  for each row execute function public.contratos_consentimento_unico();

comment on column public.contratos.consentimento_execucao_imediata is
  'Cláusula 7.3: cliente marcou expressamente no pagamento que deseja execução antes de 7 dias (padrão sempre false).';
comment on column public.contratos.consentimento_execucao_imediata_em is
  'Instante exato do consentimento expresso de execução antes dos 7 dias (obrigatório quando true).';

-- ---------------------------------------------------------------------------
-- 3) cancelamentos_pedido: desistência, cancelamento e retenção até 30% (7.2-7.4, 7.9)
-- ---------------------------------------------------------------------------
create table if not exists public.cancelamentos_pedido (
  id                           uuid primary key default gen_random_uuid(),
  pedido_id                    uuid not null references public.pedidos (id) on delete restrict,
  contrato_id                  uuid references public.contratos (id) on delete restrict,
  solicitado_por               uuid not null references public.usuarios (id) on delete restrict,
  papel_solicitante            text not null
                                 check (papel_solicitante in ('cliente', 'profissional', 'sistema', 'analista')),
  tipo                         text not null
                                 check (tipo in (
                                   'desistencia_arrependimento',
                                   'cancelamento_cliente',
                                   'cancelamento_profissional',
                                   'cliente_ausente',
                                   'evento_externo'
                                 )),
  motivo                       text not null default '' check (char_length(motivo) <= 1000),
  status                       text not null default 'solicitado'
                                 check (status in (
                                   'solicitado',
                                   'aguardando_analise',
                                   'proposta_retencao_enviada',
                                   'confirmado',
                                   'cancelado_sem_retencao',
                                   'recusado'
                                 )),
  recebimento_confirmado_em    timestamptz not null default now(),
  servico_iniciado             boolean not null default false,
  dentro_arrependimento_7d     boolean not null default false,

  -- Proposta de retenção por custos comprovados (cláusula 7.4 / 7.6; teto padrão 30% = 3000 bps)
  retencao_valor_centavos      bigint not null default 0 check (retencao_valor_centavos >= 0),
  retencao_limite_bps          integer not null default 3000 check (retencao_limite_bps between 0 and 3000),
  retencao_valor_base_centavos bigint check (retencao_valor_base_centavos is null or retencao_valor_base_centavos >= 0),
  retencao_justificativa       text,
  retencao_comprovantes        jsonb not null default '[]'::jsonb check (jsonb_typeof(retencao_comprovantes) = 'array'),
  retencao_mostrada_cliente_em timestamptz,
  retencao_aceita_cliente      boolean,
  retencao_respondida_em       timestamptz,

  -- Reembolso apurado e decisão humana (cláusula 7.3 proporcional / análise)
  reembolso_centavos           bigint check (reembolso_centavos is null or reembolso_centavos >= 0),
  analista_id                  uuid references public.equipe (usuario_id) on delete restrict,
  decisao_analista             text,
  decidido_em                  timestamptz,

  criado_em                    timestamptz not null default now(),
  atualizado_em                timestamptz not null default now(),

  constraint cancelamentos_retencao_teto_check check (
    retencao_valor_centavos = 0
    or (retencao_valor_base_centavos is not null
        and retencao_valor_centavos <= (retencao_valor_base_centavos * retencao_limite_bps) / 10000)
  ),
  -- sem retenção no arrependimento, no cancelamento pelo profissional e em evento externo
  constraint cancelamentos_sem_retencao_check check (
    retencao_valor_centavos = 0
    or (not dentro_arrependimento_7d
        and tipo not in ('desistencia_arrependimento', 'cancelamento_profissional', 'evento_externo'))
  ),
  constraint cancelamentos_retencao_justificativa_check check (
    retencao_valor_centavos = 0
    or (retencao_justificativa is not null and btrim(retencao_justificativa) <> '')
  ),
  constraint cancelamentos_retencao_aceite_check check (
    retencao_aceita_cliente is null
    or (retencao_mostrada_cliente_em is not null and retencao_respondida_em is not null)
  ),
  constraint cancelamentos_decisao_analista_check check (
    decidido_em is null or analista_id is not null
  )
);

comment on table public.cancelamentos_pedido is
  'Pedidos de desistência (CDC 7 dias), cancelamentos e propostas de retenção por custos comprovados (até 30%, cláusulas 7.2-7.4 e 7.9).';

create index if not exists ix_cancelamentos_pedido_pedido
  on public.cancelamentos_pedido (pedido_id, criado_em desc);
create index if not exists ix_cancelamentos_pedido_contrato
  on public.cancelamentos_pedido (contrato_id)
  where contrato_id is not null;
create index if not exists ix_cancelamentos_pedido_status
  on public.cancelamentos_pedido (status, criado_em desc);

-- um só cancelamento por pedido: em aberto ou já efetivado (só 'recusado' libera outro)
create unique index if not exists ux_cancelamentos_pedido_unico
  on public.cancelamentos_pedido (pedido_id)
  where status in ('solicitado', 'aguardando_analise', 'proposta_retencao_enviada', 'confirmado',
                   'cancelado_sem_retencao');

-- a base da retenção não passa do valor contratado (contrato + aditivos aprovados)
create or replace function public.cancelamentos_pedido_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_teto bigint;
  v_pago timestamptz;
  v_dias integer;
begin
  -- Termos 5.3 e 7.2: o prazo conta da Contratação = pagamento confirmado. Mesma regra de
  -- backend/src/trato/api/desistencia.py: última confirmação no histórico do pedido; 7 dias
  -- corridos (mais, se a configuração vigente disser) até o fim do último dia em Brasília.
  -- Sem evento no histórico, vale o registro do pagamento (sem aditivos). Sem pagamento
  -- confirmado o prazo nem começou: fica dentro (a favor do consumidor).
  -- Recebimento anterior é aceito; futuro vira now().
  if tg_op = 'INSERT' then
    new.recebimento_confirmado_em := least(coalesce(new.recebimento_confirmado_em, now()), now());
    select h.ocorrida_em into v_pago
      from public.pedido_historico h
     where h.pedido_id = new.pedido_id and h.prova ->> 'acao' = 'confirmar_pagamento'
     order by h.id desc
     limit 1;
    if v_pago is null then
      select max(p.confirmado_em) into v_pago
        from public.pagamentos p
        join public.contratos c on c.id = p.contrato_id
       where c.pedido_id = new.pedido_id and p.tipo <> 'aditivo'
         and p.status in ('confirmado', 'reembolsado_parcial', 'reembolsado', 'contestado');
    end if;
    select greatest(coalesce(max(cp.valor), 7), 7) into v_dias
      from public.config_parametros cp
      join public.config_versoes cv on cv.id = cp.versao_id
     where cv.status = 'vigente' and cp.chave = 'arrependimento_dias' and cp.escopo_tipo = 'global';
    new.dentro_arrependimento_7d := v_pago is null
      or (new.recebimento_confirmado_em at time zone interval '-3 hours')::date
         <= (v_pago at time zone interval '-3 hours')::date + v_dias;
  end if;
  if new.retencao_valor_centavos = 0 then
    return new;
  end if;
  select c.valor_total_centavos
         + coalesce((select sum(a.valor_centavos) from public.aditivos a
                      where a.contrato_id = c.id and a.status = 'aprovado'), 0)
    into v_teto
    from public.contratos c where c.id = new.contrato_id and c.pedido_id = new.pedido_id;
  if not found then
    raise exception 'Retenção exige o contrato deste pedido' using errcode = 'check_violation';
  end if;
  if new.retencao_valor_base_centavos > v_teto then
    raise exception 'Base da retenção maior que o valor contratado' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.cancelamentos_pedido_validar() from public, anon, authenticated, service_role;

drop trigger if exists cancelamentos_pedido_validar_trg on public.cancelamentos_pedido;
create trigger cancelamentos_pedido_validar_trg before insert or update on public.cancelamentos_pedido
  for each row execute function public.cancelamentos_pedido_validar();
-- tipo, pedido e arrependimento não mudam depois (senão a retenção seria liberada trocando-os)
drop trigger if exists cancelamentos_pedido_proteger on public.cancelamentos_pedido;
create trigger cancelamentos_pedido_proteger before update on public.cancelamentos_pedido
  for each row execute function public.proteger_colunas(
    'id', 'pedido_id', 'solicitado_por', 'tipo', 'dentro_arrependimento_7d',
    'recebimento_confirmado_em', 'criado_em');

drop trigger if exists cancelamentos_pedido_atualizado_em on public.cancelamentos_pedido;
create trigger cancelamentos_pedido_atualizado_em before update on public.cancelamentos_pedido
  for each row execute function public.definir_atualizado_em();

alter table public.cancelamentos_pedido enable row level security;
revoke all on table public.cancelamentos_pedido from public, anon, authenticated, service_role;
grant select, insert, update on table public.cancelamentos_pedido to service_role;

-- ---------------------------------------------------------------------------
-- 4) ausencias_cliente: espera de 20 min, justificativa em 24 h e análise (7.6)
-- ---------------------------------------------------------------------------
create table if not exists public.ausencias_cliente (
  id                          uuid primary key default gen_random_uuid(),
  agendamento_id              uuid not null unique references public.agendamentos (id) on delete restrict,
  contrato_id                 uuid not null references public.contratos (id) on delete restrict,
  pedido_id                   uuid not null references public.pedidos (id) on delete restrict,
  profissional_id             uuid not null references public.perfis_profissional (usuario_id) on delete restrict,
  cliente_id                  uuid not null references public.usuarios (id) on delete restrict,
  presenca_checkin_id         uuid references public.presencas (id) on delete restrict,
  presenca_ausencia_id        uuid references public.presencas (id) on delete restrict,
  chegada_em                  timestamptz not null,
  espera_minutos              integer not null default 20 check (espera_minutos >= 20),
  ausencia_registrada_em      timestamptz,
  cliente_avisado_em          timestamptz,
  justificativa_prazo_horas   integer not null default 24 check (justificativa_prazo_horas >= 24),
  justificativa_ate           timestamptz,
  justificativa_texto         text,
  justificativa_comprovantes  jsonb not null default '[]'::jsonb check (jsonb_typeof(justificativa_comprovantes) = 'array'),
  justificativa_enviada_em    timestamptz,
  status                      text not null default 'aguardando_espera'
                                check (status in (
                                  'aguardando_espera',
                                  'aguardando_justificativa',
                                  'em_analise',
                                  'justificativa_aceita',
                                  'justificativa_recusada',
                                  'expirada_sem_justificativa',
                                  'cancelada'
                                )),
  analista_id                 uuid references public.equipe (usuario_id) on delete restrict,
  decisao_analista            text,
  decidido_em                 timestamptz,
  cancelamento_id             uuid references public.cancelamentos_pedido (id) on delete restrict,
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),

  constraint ausencias_cliente_partes_check check (cliente_id <> profissional_id),
  -- o prazo só existe depois do aviso e dura pelo menos o configurado (mínimo 24 h)
  constraint ausencias_cliente_prazo_check check (
    justificativa_ate is null
    or (cliente_avisado_em is not null
        and justificativa_ate >= cliente_avisado_em + make_interval(hours => justificativa_prazo_horas))
  ),
  constraint ausencias_cliente_expirada_check check (
    status <> 'expirada_sem_justificativa' or justificativa_ate is not null
  ),
  constraint ausencias_cliente_espera_check check (
    ausencia_registrada_em is null
    or ausencia_registrada_em >= chegada_em + make_interval(mins => espera_minutos)
  ),
  constraint ausencias_cliente_decisao_check check (
    decidido_em is null or analista_id is not null
  )
);

comment on table public.ausencias_cliente is
  'Fluxo da cláusula 7.6 (Cliente ausente): chegada/check-in, espera mínima configurável (20 min), aviso ao cliente, prazo de 24 h para justificativa e decisão do analista.';

create index if not exists ix_ausencias_cliente_status_prazo
  on public.ausencias_cliente (status, justificativa_ate);
create index if not exists ix_ausencias_cliente_pedido
  on public.ausencias_cliente (pedido_id);

-- só expira depois do prazo e sem justificativa enviada (relógio do banco)
create or replace function public.ausencias_cliente_validar()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.status = 'expirada_sem_justificativa'
     and (tg_op = 'INSERT' or old.status is distinct from new.status)
     and (new.justificativa_ate is null or now() <= new.justificativa_ate
          or new.justificativa_enviada_em is not null) then
    raise exception 'Ausência só expira depois do prazo e sem justificativa' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.ausencias_cliente_validar() from public, anon, authenticated, service_role;
drop trigger if exists ausencias_cliente_validar_trg on public.ausencias_cliente;
create trigger ausencias_cliente_validar_trg before insert or update on public.ausencias_cliente
  for each row execute function public.ausencias_cliente_validar();

drop trigger if exists ausencias_cliente_proteger on public.ausencias_cliente;
create trigger ausencias_cliente_proteger before update on public.ausencias_cliente
  for each row execute function public.proteger_colunas(
    'id', 'agendamento_id', 'contrato_id', 'pedido_id', 'profissional_id', 'cliente_id', 'chegada_em',
    'criado_em');

drop trigger if exists ausencias_cliente_atualizado_em on public.ausencias_cliente;
create trigger ausencias_cliente_atualizado_em before update on public.ausencias_cliente
  for each row execute function public.definir_atualizado_em();

alter table public.ausencias_cliente enable row level security;
revoke all on table public.ausencias_cliente from public, anon, authenticated, service_role;
grant select, insert, update on table public.ausencias_cliente to service_role;

-- ---------------------------------------------------------------------------
-- 5) exclusividades: suportar exclusividade paga pelo CLIENTE (13.6, I.4)
--    Mantém intactos todos os registros existentes (pagador = 'profissional').
-- ---------------------------------------------------------------------------
alter table public.exclusividades
  add column if not exists pagador text not null default 'profissional',
  add column if not exists orcamento_id uuid references public.orcamentos (id) on delete restrict,
  add column if not exists motivo_encerramento text,
  add column if not exists estornada boolean not null default false,
  add column if not exists estornada_em timestamptz,
  add column if not exists estorno_lancamento_id uuid references public.moedas_lancamentos (id) on delete restrict;

alter table public.exclusividades
  drop constraint if exists exclusividades_pagador_check;
alter table public.exclusividades
  add constraint exclusividades_pagador_check
  check (pagador in ('profissional', 'cliente'));

alter table public.exclusividades
  drop constraint if exists exclusividades_status_check;
alter table public.exclusividades
  add constraint exclusividades_status_check
  check (status in (
    'aguardando_cliente',
    'ativa',
    'recusada',
    'expirada_sem_resposta',
    'concluida',
    'expirada_sem_atendimento',
    'expirada_sem_contratacao',
    'cancelada'
  ));

alter table public.exclusividades
  drop constraint if exists exclusividades_motivo_encerramento_check;
alter table public.exclusividades
  add constraint exclusividades_motivo_encerramento_check
  check (
    motivo_encerramento is null
    or motivo_encerramento in (
      'contratacao_realizada',
      'prazo_expirado_sem_contratacao',
      'falha_trato',
      'desistencia_profissional',
      'cancelamento_cliente',
      'recusa_cliente',
      'expirada_sem_resposta'
    )
  );

-- Cláusula 13.6: na exclusividade do CLIENTE, só devolve Tratinhos por falha do Trato ou desistência do profissional.
alter table public.exclusividades
  drop constraint if exists exclusividades_estorno_cliente_check;
alter table public.exclusividades
  add constraint exclusividades_estorno_cliente_check
  check (
    not estornada
    or pagador <> 'cliente'
    or coalesce(motivo_encerramento, '') in ('falha_trato', 'desistencia_profissional')
  );

alter table public.exclusividades
  drop constraint if exists exclusividades_estorno_timestamp_check;
alter table public.exclusividades
  add constraint exclusividades_estorno_timestamp_check
  check (
    (estornada = false and estornada_em is null and estorno_lancamento_id is null)
    or (estornada = true and estornada_em is not null)
  );

create index if not exists ix_exclusividades_cliente_pagador
  on public.exclusividades (cliente_id, pagador, status);

comment on column public.exclusividades.pagador is
  'Quem pagou os Tratinhos pela exclusividade: ''profissional'' (legado) ou ''cliente'' (Termos v1.2, cláusula 13.6: 100 Tratinhos / 48 h).';
comment on column public.exclusividades.motivo_encerramento is
  'Motivo do encerramento; para pagador=''cliente'', estorno só é permitido em ''falha_trato'' ou ''desistencia_profissional''.';
comment on column public.exclusividades.estorno_lancamento_id is
  'Referência ao lançamento de devolução em public.moedas_lancamentos (preservando a validade original).';

commit;
