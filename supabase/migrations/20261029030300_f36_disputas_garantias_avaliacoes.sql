-- F3.6 — Disputas, evidências, garantias, retrabalhos e avaliações.
-- Fonte: docs/modelo-de-dados.md, seção 8.1 a 8.4 (aprovado pelo João em 28/10/2026).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Só DDL. RLS ligado e sem policy (F3.8). anon/authenticated sem acesso até a F3.8.
-- Depende da F3.5. Fecha as FKs repasses.congelado_por_disputa_id e lancamentos.disputa_id.
-- Reversão: supabase/rollback/F3.6_rollback.sql

-- ---------------------------------------------------------------------------
-- 8.1 disputas
-- ---------------------------------------------------------------------------
create table public.disputas (
  id                      uuid primary key default gen_random_uuid(),
  contrato_id             uuid not null references public.contratos (id) on delete restrict,
  pedido_id               uuid not null references public.pedidos (id) on delete restrict,
  aberta_por              uuid not null references public.usuarios (id) on delete restrict,
  motivo                  text not null
                            check (motivo in ('abandono', 'mal_feito', 'dano', 'cobranca_extra',
                                              'nao_compareceu', 'diferente_combinado')),
  descricao               text not null check (btrim(descricao) <> ''),
  status                  text not null default 'aberta'
                            check (status in ('aberta', 'aguardando_profissional', 'em_analise', 'acordo',
                                              'decidida', 'cancelada')),
  valor_congelado_centavos bigint not null default 0 check (valor_congelado_centavos >= 0),  -- D7
  resposta_ate            timestamptz,  -- +48 h (configuração)
  decisao_ate             timestamptz,  -- +5 dias úteis (configuração)
  decisao                 text check (decisao in ('liberar_tudo', 'reembolso_total', 'reembolso_parcial',
                                                  'nova_visita')),
  valor_reembolso_centavos bigint check (valor_reembolso_centavos is null or valor_reembolso_centavos >= 0),
  procedente              boolean,
  relato_ma_fe            boolean,
  decidida_por            uuid references public.equipe (usuario_id) on delete restrict,
  aprovada_por            uuid references public.equipe (usuario_id) on delete restrict,
  justificativa           text,
  aberta_em               timestamptz not null default now(),
  decidida_em             timestamptz,
  check (valor_reembolso_centavos is null or valor_reembolso_centavos <= valor_congelado_centavos),
  check (decidida_por is distinct from aprovada_por or decidida_por is null),
  check (status <> 'decidida' or (decisao is not null and decidida_por is not null
                                  and decidida_em is not null and btrim(coalesce(justificativa, '')) <> '')),
  check (decisao is distinct from 'reembolso_parcial' or valor_reembolso_centavos is not null)
);
create index disputas_contrato_idx on public.disputas (contrato_id);
create index disputas_pedido_idx on public.disputas (pedido_id);
create index disputas_decisao_ate_idx on public.disputas (decisao_ate)
  where status in ('aberta', 'aguardando_profissional', 'em_analise');
-- Uma disputa ativa por contrato.
create unique index disputas_uma_ativa_idx on public.disputas (contrato_id)
  where status in ('aberta', 'aguardando_profissional', 'em_analise');
create trigger disputas_proteger before update on public.disputas
  for each row execute function public.proteger_colunas(
    'contrato_id', 'pedido_id', 'aberta_por', 'motivo', 'descricao', 'aberta_em');
create trigger disputas_sem_delete before delete on public.disputas
  for each row execute function public.bloquear_alteracao();
create trigger disputas_sem_truncate before truncate on public.disputas
  for each statement execute function public.bloquear_alteracao();
alter table public.disputas enable row level security;

-- Regras de alçada (escopo 18.5): quem decide é o mediador; estorno acima do teto dele exige uma
-- segunda pessoa (líder de suporte ou administrador), diferente de quem decidiu.
-- Valor em jogo = o que sai do cliente de volta (reembolso). PROVISÓRIO: confirmar com o João.
-- Teto nulo vale como zero (sem alçada = sempre exige 2ª pessoa).
create or replace function public.disputas_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ctr public.contratos%rowtype;
  decisor public.equipe%rowtype;
  aprovador public.equipe%rowtype;
  valor_em_jogo bigint;
begin
  select * into ctr from public.contratos where id = new.contrato_id;

  if tg_op = 'INSERT' then
    if new.pedido_id is distinct from ctr.pedido_id then
      raise exception 'O pedido da disputa não é o pedido do contrato' using errcode = 'check_violation';
    end if;
    if new.aberta_por not in (ctr.cliente_id, ctr.profissional_id) then
      raise exception 'Só uma das partes do contrato abre disputa' using errcode = 'check_violation';
    end if;
  else
    if old.status in ('decidida', 'cancelada') then
      raise exception 'Disputa % não pode mais mudar', old.status using errcode = 'restrict_violation';
    end if;
  end if;

  if new.status = 'decidida' then
    select * into decisor from public.equipe where usuario_id = new.decidida_por;
    if not found or not decisor.ativo or decisor.revogado_em is not null or decisor.papel <> 'mediador' then
      raise exception 'Só um mediador ativo decide a disputa' using errcode = 'check_violation';
    end if;
    valor_em_jogo := case new.decisao
                       when 'reembolso_total' then new.valor_congelado_centavos
                       when 'reembolso_parcial' then coalesce(new.valor_reembolso_centavos, 0)
                       else 0 end;
    if valor_em_jogo > coalesce(decisor.alcada_centavos, 0) then
      select * into aprovador from public.equipe where usuario_id = new.aprovada_por;
      if not found or not aprovador.ativo or aprovador.revogado_em is not null
         or aprovador.papel not in ('lider_suporte', 'administrador')
         or aprovador.usuario_id = new.decidida_por then
        raise exception 'Valor acima da alçada: exige aprovação de outra pessoa (líder de suporte ou administrador)'
          using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$$;
create trigger disputas_validar_trg before insert or update on public.disputas
  for each row execute function public.disputas_validar();

-- Fecha as FKs que dependiam desta tabela.
alter table public.repasses
  add constraint repasses_disputa_fk foreign key (congelado_por_disputa_id)
  references public.disputas (id) on delete restrict;
alter table public.lancamentos
  add constraint lancamentos_disputa_fk foreign key (disputa_id)
  references public.disputas (id) on delete restrict;

-- ---------------------------------------------------------------------------
-- 8.2 disputa_evidencias — provas e respostas (append-only)
-- ---------------------------------------------------------------------------
create table public.disputa_evidencias (
  id                uuid primary key default gen_random_uuid(),
  disputa_id        uuid not null references public.disputas (id) on delete restrict,
  autor_id          uuid not null references public.usuarios (id) on delete restrict,
  tipo              text not null
                      check (tipo in ('relato', 'resposta', 'proposta_retorno', 'foto', 'documento',
                                      'nota_interna')),
  texto             text,
  midia_id          uuid references public.midias (id) on delete restrict,
  visivel_as_partes boolean not null default true,
  criado_em         timestamptz not null default now(),
  check (tipo <> 'nota_interna' or not visivel_as_partes),
  check (texto is not null or midia_id is not null)
);
create index disputa_evidencias_disputa_idx on public.disputa_evidencias (disputa_id, criado_em);
create trigger disputa_evidencias_imutavel before update or delete on public.disputa_evidencias
  for each row execute function public.bloquear_alteracao();
create trigger disputa_evidencias_sem_truncate before truncate on public.disputa_evidencias
  for each statement execute function public.bloquear_alteracao();
alter table public.disputa_evidencias enable row level security;

-- Nota interna só da equipe; as demais só das partes ou da equipe; mídia do mesmo pedido.
create or replace function public.disputa_evidencias_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  d public.disputas%rowtype;
  ctr public.contratos%rowtype;
  e_equipe boolean;
  midia_pedido uuid;
begin
  select * into d from public.disputas where id = new.disputa_id;
  select * into ctr from public.contratos where id = d.contrato_id;
  select exists (select 1 from public.equipe where usuario_id = new.autor_id and ativo and revogado_em is null)
    into e_equipe;
  if new.tipo = 'nota_interna' and not e_equipe then
    raise exception 'Nota interna só pode ser escrita pela equipe' using errcode = 'check_violation';
  end if;
  if not e_equipe and new.autor_id not in (ctr.cliente_id, ctr.profissional_id) then
    raise exception 'Só as partes ou a equipe acrescentam evidência' using errcode = 'check_violation';
  end if;
  if new.midia_id is not null then
    select pedido_id into midia_pedido from public.midias where id = new.midia_id;
    if midia_pedido is distinct from d.pedido_id then
      raise exception 'A mídia é de outro pedido' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
create trigger disputa_evidencias_validar_trg before insert on public.disputa_evidencias
  for each row execute function public.disputa_evidencias_validar();

-- ---------------------------------------------------------------------------
-- 8.3 garantias e retrabalhos
-- ---------------------------------------------------------------------------
create table public.garantias (
  id          uuid primary key default gen_random_uuid(),
  contrato_id uuid not null unique references public.contratos (id) on delete restrict,
  inicio_em   timestamptz not null,
  fim_em      timestamptz not null,
  dias        integer not null check (dias > 0),  -- da categoria ou do padrão, congelado
  status      text not null default 'ativa' check (status in ('ativa', 'expirada', 'encerrada')),
  criado_em   timestamptz not null default now(),
  check (fim_em > inicio_em)
);
create index garantias_ativas_idx on public.garantias (fim_em) where status = 'ativa';
create trigger garantias_proteger before update on public.garantias
  for each row execute function public.proteger_colunas('contrato_id', 'inicio_em', 'fim_em', 'dias', 'criado_em');
create trigger garantias_sem_delete before delete on public.garantias
  for each row execute function public.bloquear_alteracao();
alter table public.garantias enable row level security;

create table public.retrabalhos (
  id                   uuid primary key default gen_random_uuid(),
  garantia_id          uuid not null references public.garantias (id) on delete restrict,
  aberto_por           uuid not null references public.usuarios (id) on delete restrict,
  descricao            text not null check (btrim(descricao) <> ''),
  status               text not null default 'aberto'
                         check (status in ('aberto', 'aceito', 'em_execucao', 'resolvido', 'nao_atendido',
                                           'reatribuido')),
  atender_ate          timestamptz,  -- +7 dias (configuração)
  atendido_em          timestamptz,
  outro_profissional_id uuid references public.perfis_profissional (usuario_id) on delete restrict,
  custo_centavos       bigint check (custo_centavos is null or custo_centavos >= 0),  -- quem paga: P8 / N6
  aberto_em            timestamptz not null default now()
);
create index retrabalhos_garantia_idx on public.retrabalhos (garantia_id);
create index retrabalhos_prazo_idx on public.retrabalhos (atender_ate) where status in ('aberto', 'aceito');
create trigger retrabalhos_proteger before update on public.retrabalhos
  for each row execute function public.proteger_colunas('garantia_id', 'aberto_por', 'descricao', 'aberto_em');
create trigger retrabalhos_sem_delete before delete on public.retrabalhos
  for each row execute function public.bloquear_alteracao();
alter table public.retrabalhos enable row level security;

-- Retrabalho só enquanto a garantia está ativa e dentro do prazo, aberto pelo cliente do contrato.
create or replace function public.retrabalhos_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  g public.garantias%rowtype;
  ctr public.contratos%rowtype;
begin
  select * into g from public.garantias where id = new.garantia_id;
  select * into ctr from public.contratos where id = g.contrato_id;
  if g.status <> 'ativa' or now() > g.fim_em then
    raise exception 'Garantia fora do prazo ou encerrada' using errcode = 'check_violation';
  end if;
  if new.aberto_por is distinct from ctr.cliente_id then
    raise exception 'Só o cliente do contrato aciona a garantia' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger retrabalhos_validar_trg before insert on public.retrabalhos
  for each row execute function public.retrabalhos_validar();

-- ---------------------------------------------------------------------------
-- 8.4 avaliacoes e avaliacao_criterios
-- ---------------------------------------------------------------------------
create table public.avaliacoes (
  id           uuid primary key default gen_random_uuid(),
  contrato_id  uuid not null references public.contratos (id) on delete restrict,
  direcao      text not null check (direcao in ('cliente_para_profissional', 'profissional_para_cliente')),
  avaliador_id uuid not null references public.usuarios (id) on delete restrict,
  avaliado_id  uuid not null references public.usuarios (id) on delete restrict,
  nota_geral   smallint not null check (nota_geral between 1 and 5),
  comentario   text,
  etiquetas    text[] not null default '{}',
  resposta     text,  -- resposta do avaliado
  status       text not null default 'publicada' check (status in ('publicada', 'descartada', 'em_revisao')),
  criada_em    timestamptz not null default now(),
  unique (contrato_id, direcao),
  check (avaliador_id <> avaliado_id)
);
create index avaliacoes_avaliado_idx on public.avaliacoes (avaliado_id, criada_em desc);
-- Nota e comentário não se editam; o que muda é a resposta do avaliado e o status (moderação).
create trigger avaliacoes_proteger before update on public.avaliacoes
  for each row execute function public.proteger_colunas(
    'contrato_id', 'direcao', 'avaliador_id', 'avaliado_id', 'nota_geral', 'comentario', 'etiquetas', 'criada_em');
create trigger avaliacoes_sem_delete before delete on public.avaliacoes
  for each row execute function public.bloquear_alteracao();
alter table public.avaliacoes enable row level security;

create or replace function public.avaliacoes_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ctr public.contratos%rowtype;
begin
  select * into ctr from public.contratos where id = new.contrato_id;
  if new.direcao = 'cliente_para_profissional'
     and (new.avaliador_id is distinct from ctr.cliente_id or new.avaliado_id is distinct from ctr.profissional_id) then
    raise exception 'Avaliação do cliente: avaliador e avaliado não batem com o contrato' using errcode = 'check_violation';
  end if;
  if new.direcao = 'profissional_para_cliente'
     and (new.avaliador_id is distinct from ctr.profissional_id or new.avaliado_id is distinct from ctr.cliente_id) then
    raise exception 'Avaliação do profissional: avaliador e avaliado não batem com o contrato' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger avaliacoes_validar_trg before insert on public.avaliacoes
  for each row execute function public.avaliacoes_validar();

create table public.avaliacao_criterios (
  avaliacao_id uuid not null references public.avaliacoes (id) on delete restrict,
  criterio     text not null
                 check (criterio in ('pontualidade', 'qualidade', 'limpeza', 'comunicacao', 'preco_justo',
                                     'respeito', 'clareza', 'acesso', 'presenca', 'pagamento_no_prazo')),
  nota         smallint not null check (nota between 1 and 5),
  primary key (avaliacao_id, criterio)
);
create trigger avaliacao_criterios_imutavel before update or delete on public.avaliacao_criterios
  for each row execute function public.bloquear_alteracao();
alter table public.avaliacao_criterios enable row level security;

-- Critério do cliente só em avaliação do cliente; do profissional, só na dele.
create or replace function public.avaliacao_criterios_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  dir text;
begin
  select direcao into dir from public.avaliacoes where id = new.avaliacao_id;
  if (dir = 'cliente_para_profissional'
      and new.criterio not in ('pontualidade', 'qualidade', 'limpeza', 'comunicacao', 'preco_justo'))
     or (dir = 'profissional_para_cliente'
      and new.criterio not in ('respeito', 'clareza', 'acesso', 'presenca', 'pagamento_no_prazo')) then
    raise exception 'Critério % não existe para esta direção de avaliação', new.criterio
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger avaliacao_criterios_validar_trg before insert on public.avaliacao_criterios
  for each row execute function public.avaliacao_criterios_validar();

-- ---------------------------------------------------------------------------
-- Acesso. Privilégios EXPLÍCITOS, iguais em qualquer padrão da plataforma:
--  * anon e authenticated: nada (a F3.8b concede só SELECT, por coluna);
--  * service_role (backend): só o que a tabela precisa. Nunca TRUNCATE.
--    Tabela imutável recebe apenas SELECT e INSERT.
-- ---------------------------------------------------------------------------
revoke all on table public.disputas, public.disputa_evidencias, public.garantias, public.retrabalhos,
  public.avaliacoes, public.avaliacao_criterios from public, anon, authenticated, service_role;
grant select, insert, update on table public.disputas, public.garantias, public.retrabalhos,
  public.avaliacoes to service_role;
grant select, insert on table public.disputa_evidencias, public.avaliacao_criterios to service_role;
revoke execute on function public.disputas_validar(), public.disputa_evidencias_validar(),
  public.retrabalhos_validar(), public.avaliacoes_validar(), public.avaliacao_criterios_validar()
  from public, anon, authenticated;
