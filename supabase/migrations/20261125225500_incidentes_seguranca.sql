-- ===========================================================================
-- 20261125225500_incidentes_seguranca.sql
-- RASCUNHO (TERMOS-DB5, 3/5). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2: 9.3 (canal de segurança), 9.4, 9.5 (pessoa diferente), 9.6 (cautela em 24 h).
-- Depende de 20261125224500_sac_chamados e 20261125224600_medidas_conta.
--
-- public.alertas_risco continua sendo a fila de risco do painel; não é alterada.
-- Suspender conta exige uma linha em medidas_conta (regras de 20.2 e 20.4).
-- Estas tabelas não cancelam pedido nem movem dinheiro (o backend faz).
-- RLS ligada, sem policy; só service_role; sem delete; medidas só recebem inserção.
-- O incidente nasce 'aberto', sem cautela nem desfecho. Responsável e autor de medida:
-- equipe ativa com papel mediador, lider_suporte, seguranca ou administrador.
-- Cautela exige medida registrada antes. Datas e pedido, depois de gravados, não mudam.
--
-- PRAZO: cautela_ate é calculado pelo backend (chave incidente_seguranca_cautela_horas,
-- comentada na 20261125224500); o CHECK impede passar de 24 h da abertura (9.6).
--
-- Rollback: supabase/rollback/20261125225500_incidentes_seguranca_rollback.sql
-- ===========================================================================

begin;

create sequence if not exists public.incidentes_seguranca_protocolo_seq;
revoke all on sequence public.incidentes_seguranca_protocolo_seq
  from public, anon, authenticated, service_role;

create table if not exists public.incidentes_seguranca (
  id                      uuid primary key default gen_random_uuid(),
  protocolo               text not null unique check (protocolo ~ '^INC-[0-9]{4}-[0-9]{6,}$'),
  relator_id              uuid references public.usuarios (id) on delete restrict,
  contato                 text check (contato is null or char_length(contato) <= 320),
  canal                   text not null check (canal in ('app', 'telefone', 'whatsapp', 'email', 'painel')),
  tipo                    text not null check (tipo in ('furto_roubo', 'agressao_ameaca_assedio',
                            'acidente_dano', 'pessoa_diferente', 'comportamento_suspeito',
                            'pagamento_por_fora', 'outro')),
  descricao               text not null default '',
  anexos                  jsonb not null default '[]'::jsonb check (jsonb_typeof(anexos) = 'array'),
  pedido_id               uuid references public.pedidos (id) on delete restrict,
  envolvido_id            uuid references public.usuarios (id) on delete restrict,
  aberto_em               timestamptz not null default now(),
  confirmado_em           timestamptz,
  cautela_ate             timestamptz not null,
  cautela_adotada_em      timestamptz,
  status                  text not null default 'aberto'
                            check (status in ('aberto', 'cautela_adotada', 'em_apuracao', 'encerrado')),
  responsavel_id          uuid references public.equipe (usuario_id) on delete restrict,
  desfecho                text,
  desfecho_comunicado_em  timestamptz,
  encerrado_em            timestamptz,
  constraint incidentes_relator_check check (relator_id is not null or btrim(coalesce(contato, '')) <> ''),
  constraint incidentes_pessoa_diferente_check check (tipo <> 'pessoa_diferente' or pedido_id is not null),
  constraint incidentes_prazo_check check (
    cautela_ate > aberto_em and cautela_ate <= aberto_em + interval '24 hours'),
  constraint incidentes_cautela_check check (status <> 'cautela_adotada' or cautela_adotada_em is not null),
  constraint incidentes_encerramento_check check (
    case when status = 'encerrado'
         then encerrado_em is not null and responsavel_id is not null and btrim(coalesce(desfecho, '')) <> ''
         else encerrado_em is null end)
);
create index if not exists ix_incidentes_status_prazo on public.incidentes_seguranca (status, cautela_ate);
create index if not exists ix_incidentes_pedido on public.incidentes_seguranca (pedido_id)
  where pedido_id is not null;
create index if not exists ix_incidentes_envolvido on public.incidentes_seguranca (envolvido_id)
  where envolvido_id is not null;

create table if not exists public.incidente_medidas (
  id               uuid primary key default gen_random_uuid(),
  incidente_id     uuid not null references public.incidentes_seguranca (id) on delete restrict,
  tipo             text not null check (tipo in ('suspender_conta', 'bloquear_contato',
                     'preservar_registros', 'reter_valor', 'cancelar_pedido_reembolso', 'outro')),
  descricao        text not null check (btrim(descricao) <> ''),
  origem           text not null check (origem in ('analista', 'automatica')),
  aplicada_por     uuid references public.equipe (usuario_id) on delete restrict,
  medida_conta_id  uuid references public.medidas_conta (id) on delete restrict,
  aplicada_em      timestamptz not null default now(),
  constraint incidente_medidas_autor_check check ((origem = 'analista') = (aplicada_por is not null)),
  constraint incidente_medidas_conta_check check (tipo <> 'suspender_conta' or medida_conta_id is not null)
);
create index if not exists ix_incidente_medidas_incidente
  on public.incidente_medidas (incidente_id, aplicada_em);

-- Nasce aberto; datas coerentes e gravadas uma vez; encerrado não reabre nem é reescrito
-- (só se registra a comunicação do desfecho, uma vez).
create or replace function public.incidentes_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'aberto' or new.cautela_adotada_em is not null or new.desfecho is not null
       or new.desfecho_comunicado_em is not null or new.encerrado_em is not null then
      raise exception 'Incidente nasce aberto, sem cautela, desfecho ou comunicação' using errcode = 'check_violation';
    end if;
    -- abertura no futuro esticaria as 24 h de 9.6 (5 min de folga para o relógio)
    if new.aberto_em > now() + interval '5 minutes' then
      raise exception 'Abertura do incidente não pode ser no futuro' using errcode = 'check_violation';
    end if;
  elsif old.status = 'encerrado'
     and ((to_jsonb(new) - 'desfecho_comunicado_em') is distinct from (to_jsonb(old) - 'desfecho_comunicado_em')
          or (old.desfecho_comunicado_em is not null
              and new.desfecho_comunicado_em is distinct from old.desfecho_comunicado_em)) then
    raise exception 'Incidente encerrado não pode ser reaberto nem reescrito' using errcode = 'restrict_violation';
  end if;
  if tg_op = 'UPDATE' then
    if new.envolvido_id is distinct from old.envolvido_id
       and exists (select 1 from public.incidente_medidas im
                    where im.incidente_id = old.id and im.medida_conta_id is not null) then
      raise exception 'Há medida de conta ligada: o envolvido não muda' using errcode = 'restrict_violation';
    end if;
    if (old.cautela_adotada_em is not null and new.cautela_adotada_em is distinct from old.cautela_adotada_em)
       or (old.confirmado_em is not null and new.confirmado_em is distinct from old.confirmado_em)
       or (old.pedido_id is not null and new.pedido_id is distinct from old.pedido_id)
       or (old.status <> 'aberto' and new.status = 'aberto' and old.status <> 'encerrado') then
      raise exception 'Dado já gravado (cautela, confirmação, pedido ou andamento) não pode ser alterado' using errcode = 'restrict_violation';
    end if;
    if new.cautela_adotada_em is not null and old.cautela_adotada_em is null then
      if new.cautela_adotada_em < new.aberto_em then
        raise exception 'Cautela não pode ser antes da abertura' using errcode = 'check_violation';
      end if;
      if not exists (select 1 from public.incidente_medidas im where im.incidente_id = new.id) then
        raise exception 'Cautela sem medida registrada' using errcode = 'check_violation';
      end if;
    end if;
    if new.encerrado_em is distinct from old.encerrado_em and new.encerrado_em < new.aberto_em then
      raise exception 'Encerramento não pode ser antes da abertura' using errcode = 'check_violation';
    end if;
    if new.desfecho_comunicado_em is not null and new.status <> 'encerrado' then
      raise exception 'Desfecho é comunicado só depois de encerrar' using errcode = 'check_violation';
    end if;
  end if;
  -- papel conferido quando o responsável é indicado ou o andamento muda
  if new.responsavel_id is not null
     and (tg_op = 'INSERT'
          or new.responsavel_id is distinct from old.responsavel_id
          or new.status is distinct from old.status)
     and not exists (select 1 from public.equipe q
                      where q.usuario_id = new.responsavel_id and q.ativo and q.revogado_em is null
                        and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')) then
    raise exception 'Responsável sem papel de análise ativo' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- Medida só em incidente não encerrado, por equipe com papel de análise (ou automática).
-- medida_conta ligada é sempre do envolvido; suspender_conta exige suspensão vigente.
create or replace function public.incidente_medidas_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_status    text;
  v_envolvido uuid;
begin
  -- trava a linha: encerramento simultâneo espera, e vice-versa
  select i.status, i.envolvido_id into v_status, v_envolvido
    from public.incidentes_seguranca i where i.id = new.incidente_id for share;
  if v_status = 'encerrado' then
    raise exception 'Incidente encerrado não recebe medida' using errcode = 'restrict_violation';
  end if;
  if new.aplicada_por is not null
     and not exists (select 1 from public.equipe q
                      where q.usuario_id = new.aplicada_por and q.ativo and q.revogado_em is null
                        and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')) then
    raise exception 'Autor da medida sem papel de análise ativo' using errcode = 'check_violation';
  end if;
  if new.medida_conta_id is not null
     and not exists (select 1 from public.medidas_conta mc
                      where mc.id = new.medida_conta_id and mc.usuario_id = v_envolvido) then
    raise exception 'A medida precisa ser uma suspensão do envolvido no incidente ou outra medida do envolvido'
      using errcode = 'check_violation';
  end if;
  if new.tipo = 'suspender_conta'
     and not exists (select 1 from public.incidentes_seguranca i
                       join public.medidas_conta mc on mc.usuario_id = i.envolvido_id
                      where i.id = new.incidente_id and mc.id = new.medida_conta_id
                        and mc.tipo = 'suspensao' and mc.revertida_em is null
                        and (mc.fim_em is null or mc.fim_em > greatest(new.aplicada_em, now()))) then
    raise exception 'A medida precisa ser uma suspensão do envolvido no incidente' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.incidentes_validar() from public, anon, authenticated, service_role;
revoke all on function public.incidente_medidas_validar() from public, anon, authenticated, service_role;
drop trigger if exists incidentes_validar_trg on public.incidentes_seguranca;
create trigger incidentes_validar_trg before insert or update on public.incidentes_seguranca
  for each row execute function public.incidentes_validar();
drop trigger if exists incidente_medidas_validar_trg on public.incidente_medidas;
create trigger incidente_medidas_validar_trg before insert on public.incidente_medidas
  for each row execute function public.incidente_medidas_validar();

drop trigger if exists incidentes_protocolo on public.incidentes_seguranca;
create trigger incidentes_protocolo before insert on public.incidentes_seguranca
  for each row execute function public.sac_gerar_protocolo('INC', 'incidentes_seguranca_protocolo_seq');
drop trigger if exists incidentes_proteger on public.incidentes_seguranca;
create trigger incidentes_proteger before update on public.incidentes_seguranca
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'relator_id', 'contato', 'canal', 'descricao', 'anexos', 'aberto_em', 'cautela_ate');
drop trigger if exists incidentes_sem_delete on public.incidentes_seguranca;
create trigger incidentes_sem_delete before delete on public.incidentes_seguranca
  for each row execute function public.bloquear_alteracao();
drop trigger if exists incidentes_sem_truncate on public.incidentes_seguranca;
create trigger incidentes_sem_truncate before truncate on public.incidentes_seguranca
  for each statement execute function public.bloquear_alteracao();

drop trigger if exists incidente_medidas_imutavel on public.incidente_medidas;
create trigger incidente_medidas_imutavel before update or delete on public.incidente_medidas
  for each row execute function public.bloquear_alteracao();
drop trigger if exists incidente_medidas_sem_truncate on public.incidente_medidas;
create trigger incidente_medidas_sem_truncate before truncate on public.incidente_medidas
  for each statement execute function public.bloquear_alteracao();

alter table public.incidentes_seguranca enable row level security;
alter table public.incidente_medidas enable row level security;
revoke all on table public.incidentes_seguranca, public.incidente_medidas
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.incidentes_seguranca to service_role;
grant select, insert on table public.incidente_medidas to service_role;

commit;
