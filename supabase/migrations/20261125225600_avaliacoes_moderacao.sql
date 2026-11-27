-- ===========================================================================
-- 20261125225600_avaliacoes_moderacao.sql
-- RASCUNHO (TERMOS-DB5, 4/5). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2: 12.6 (ocultar só depois de análise, com motivo), 12.7 (pedido de revisão
-- com prazo) e 20.5 (contestação por outro Analista sempre que possível).
-- Depende de 20261125224500_sac_chamados (gerador de protocolo).
--
-- Reaproveita public.avaliacoes (resposta pública e status já existem). Ocultar põe o
-- status em 'descartada'; reverter volta ao status anterior; a nota pública é recalculada. Aceitar uma revisão NÃO oculta nem
-- reverte sozinho: o backend registra a ocultação ou a reversão.
-- O banco exige: pedido nasce aberto; quem oculta, reverte ou analisa é da equipe ativa
-- (mediador, lider_suporte, seguranca ou administrador); avaliação oculta só volta por reversão.
-- RLS ligada, sem policy; só service_role; sem delete. Só acrescenta.
--
-- PRAZO (o backend calcula responder_ate). NÃO executado aqui; rodar só com OK do João:
--   insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao) values
--     ('avaliacao_revisao_resposta_dias_uteis', 'Prazo de resposta ao pedido de revisão de avaliação (12.7)', 'dias_uteis', 1, 5, array['global'], false)
--   on conflict (chave) do nothing;
--   -- valor do Anexo II: 5.
--
-- Rollback: supabase/rollback/20261125225600_avaliacoes_moderacao_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
                  and table_name = 'avaliacoes' and column_name = 'nota_decimal') then
    raise exception 'Aplique antes a migration 20261122100000_avaliacao_nota_decimal';
  end if;
end;
$$;

-- A nota pública só conta avaliação 'publicada'. Mesma função da 20261122100000 mais o filtro.
-- Não recalcula quem já existe; se houver avaliação oculta antiga, rodar com OK do João:
--   select public.recalcular_perfil_profissional(usuario_id) from public.perfis_profissional;
create or replace function public.recalcular_perfil_profissional(p_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.perfis_profissional p
     set servicos_concluidos = (
           select count(*)
             from public.contratos c
             join public.pedidos x on x.id = c.pedido_id
            where c.profissional_id = p_id and x.status = 'concluido'),
         nota_publica = (
           select round(avg(coalesce(a.nota_decimal, a.nota_geral::numeric)), 2)
             from public.avaliacoes a
            where a.avaliado_id = p_id and a.direcao = 'cliente_para_profissional'
              and a.status = 'publicada')
   where p.usuario_id = p_id;
$$;
revoke all on function public.recalcular_perfil_profissional(uuid) from public, anon, authenticated;

-- recalcula em qualquer mudança de status (ocultar, reverter ou moderação direta)
drop trigger if exists avaliacoes_status_recalcula_perfil on public.avaliacoes;
create trigger avaliacoes_status_recalcula_perfil after update of status on public.avaliacoes
  for each row when (old.status is distinct from new.status)
  execute function public.avaliacao_recalcula_perfil();

create sequence if not exists public.avaliacao_revisoes_protocolo_seq;
revoke all on sequence public.avaliacao_revisoes_protocolo_seq from public, anon, authenticated, service_role;

create table if not exists public.avaliacao_ocultacoes (
  id                 uuid primary key default gen_random_uuid(),
  avaliacao_id       uuid not null references public.avaliacoes (id) on delete restrict,
  motivo             text not null check (motivo in ('ofensa_ou_ilegal', 'dados_pessoais',
                       'sem_pedido_real_ou_falsa', 'nao_participou', 'ordem_judicial')),
  explicacao         text not null check (btrim(explicacao) <> ''),
  analista_id        uuid not null references public.equipe (usuario_id) on delete restrict,
  ocultada_em        timestamptz not null default now(),
  status_anterior    text not null  -- preenchido pelo banco; a reversão volta a ele
                       check (status_anterior in ('publicada', 'em_revisao', 'descartada')),
  autor_avisado_em   timestamptz,
  revertida_em       timestamptz,
  revertida_por      uuid references public.equipe (usuario_id) on delete restrict,
  constraint avaliacao_ocultacoes_reversao_check check ((revertida_em is null) = (revertida_por is null))
);
create unique index if not exists ux_avaliacao_ocultacoes_ativa
  on public.avaliacao_ocultacoes (avaliacao_id) where revertida_em is null;

create table if not exists public.avaliacao_revisoes (
  id                            uuid primary key default gen_random_uuid(),
  protocolo                     text not null unique check (protocolo ~ '^REV-[0-9]{4}-[0-9]{6,}$'),
  avaliacao_id                  uuid not null references public.avaliacoes (id) on delete restrict,
  tipo                          text not null check (tipo in ('revisao', 'contestacao_ocultacao')),
  ocultacao_id                  uuid references public.avaliacao_ocultacoes (id) on delete restrict,
  solicitante_id                uuid not null references public.usuarios (id) on delete restrict,
  justificativa                 text not null check (btrim(justificativa) <> ''),
  anexos                        jsonb not null default '[]'::jsonb check (jsonb_typeof(anexos) = 'array'),
  canal                         text not null check (canal in ('app', 'sac')),
  aberta_em                     timestamptz not null default now(),
  responder_ate                 timestamptz not null,
  status                        text not null default 'aberta'
                                  check (status in ('aberta', 'em_analise', 'aceita', 'recusada')),
  analista_id                   uuid references public.equipe (usuario_id) on delete restrict,
  resposta                      text,
  mesmo_analista_justificativa  text,
  decidida_em                   timestamptz,
  constraint avaliacao_revisoes_ocultacao_check check (
    (tipo = 'contestacao_ocultacao') = (ocultacao_id is not null)),
  constraint avaliacao_revisoes_prazo_check check (responder_ate > aberta_em),
  constraint avaliacao_revisoes_decisao_check check (
    case when status in ('aceita', 'recusada')
         then analista_id is not null and btrim(coalesce(resposta, '')) <> '' and decidida_em is not null
         else decidida_em is null end)
);
create unique index if not exists ux_avaliacao_revisoes_aberta
  on public.avaliacao_revisoes (avaliacao_id, solicitante_id) where status in ('aberta', 'em_analise');
create index if not exists ix_avaliacao_revisoes_status_prazo
  on public.avaliacao_revisoes (status, responder_ate);

create or replace function public.avaliacao_ocultacoes_aplicar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_quem uuid;
begin
  -- depois de gravada a reversão (a trava de avaliacoes já não vê ocultação ativa)
  if tg_when = 'AFTER' then
    update public.avaliacoes set status = old.status_anterior where id = new.avaliacao_id;
    return null;
  end if;
  if tg_op = 'INSERT' then
    if new.revertida_em is not null or new.revertida_por is not null then
      raise exception 'A ocultação nasce sem reversão' using errcode = 'check_violation';
    end if;
    if new.ocultada_em > now() + interval '5 minutes' then
      raise exception 'Data de ocultação no futuro não é permitida' using errcode = 'check_violation';
    end if;
    if new.autor_avisado_em is not null
       and (new.autor_avisado_em < new.ocultada_em or new.autor_avisado_em > now() + interval '5 minutes') then
      raise exception 'Data de aviso ao autor inválida' using errcode = 'check_violation';
    end if;
    v_quem := new.analista_id;
  elsif old.revertida_em is null and new.revertida_em is not null then
    if new.revertida_em < old.ocultada_em or new.revertida_em > now() + interval '5 minutes' then
      raise exception 'Data de reversão deve estar entre a ocultação e o momento atual'
        using errcode = 'check_violation';
    end if;
    v_quem := new.revertida_por;
  end if;
  if v_quem is not null
     and not exists (select 1 from public.equipe q
                      where q.usuario_id = v_quem and q.ativo and q.revogado_em is null
                        and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')) then
    raise exception 'Ocultar e reverter exigem equipe ativa com papel de análise'
      using errcode = 'check_violation';
  end if;
  if tg_op = 'INSERT' then
    select a.status into new.status_anterior from public.avaliacoes a
     where a.id = new.avaliacao_id for update;
    update public.avaliacoes set status = 'descartada' where id = new.avaliacao_id;
    return new;
  end if;
  if old.revertida_em is not null
     and (new.revertida_em, new.revertida_por) is distinct from (old.revertida_em, old.revertida_por) then
    raise exception 'Reversão já registrada não pode mudar' using errcode = 'restrict_violation';
  end if;
  if old.autor_avisado_em is not null and new.autor_avisado_em is distinct from old.autor_avisado_em then
    raise exception 'Data de aviso ao autor já registrada não pode mudar' using errcode = 'restrict_violation';
  end if;
  if old.autor_avisado_em is null and new.autor_avisado_em is not null
     and (new.autor_avisado_em < old.ocultada_em or new.autor_avisado_em > now() + interval '5 minutes') then
    raise exception 'Data de aviso ao autor inválida' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- avaliação com ocultação ativa só volta pela reversão registrada
create or replace function public.avaliacoes_travar_ocultada()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status <> 'descartada'
     and exists (select 1 from public.avaliacao_ocultacoes o
                  where o.avaliacao_id = new.id and o.revertida_em is null) then
    raise exception 'Avaliação oculta: registre a reversão da ocultação'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create or replace function public.avaliacao_revisoes_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_aval record;
  v_ocu  record;
begin
  if tg_op = 'UPDATE' and old.status in ('aceita', 'recusada') then
    raise exception 'Pedido já decidido não pode mudar' using errcode = 'restrict_violation';
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'aberta'
       or num_nonnulls(new.analista_id, new.resposta, new.mesmo_analista_justificativa, new.decidida_em) > 0 then
      raise exception 'O pedido nasce aberto, sem análise ou decisão' using errcode = 'check_violation';
    end if;
    if new.aberta_em > now() + interval '5 minutes' then
      raise exception 'Data de abertura no futuro não é permitida' using errcode = 'check_violation';
    end if;
  else
    if old.status = 'em_analise' and new.status = 'aberta' then
      raise exception 'Pedido em análise não volta para aberto' using errcode = 'check_violation';
    end if;
    if new.status = 'aberta'
       and num_nonnulls(new.analista_id, new.resposta, new.mesmo_analista_justificativa, new.decidida_em) > 0 then
      raise exception 'Pedido aberto não pode ter análise ou decisão' using errcode = 'check_violation';
    end if;
    if new.status = 'em_analise' and new.analista_id is null then
      raise exception 'Pedido em análise exige analista' using errcode = 'check_violation';
    end if;
    if new.decidida_em is not null
       and (new.decidida_em < old.aberta_em or new.decidida_em > now() + interval '5 minutes') then
      raise exception 'Data de decisão deve estar entre a abertura e o momento atual'
        using errcode = 'check_violation';
    end if;
    if new.analista_id is not null
       and (new.analista_id is distinct from old.analista_id or new.status is distinct from old.status)
       and not exists (select 1 from public.equipe q
                        where q.usuario_id = new.analista_id and q.ativo and q.revogado_em is null
                          and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')) then
      raise exception 'Analista precisa ser da equipe ativa com papel de análise'
        using errcode = 'check_violation';
    end if;
  end if;
  select a.avaliador_id, a.avaliado_id into v_aval from public.avaliacoes a where a.id = new.avaliacao_id;
  if new.tipo = 'revisao' then
    if new.solicitante_id is distinct from v_aval.avaliado_id then
      raise exception 'Só quem foi avaliado pede a revisão' using errcode = 'check_violation';
    end if;
  else
    if new.solicitante_id is distinct from v_aval.avaliador_id then
      raise exception 'Só quem escreveu contesta a ocultação' using errcode = 'check_violation';
    end if;
    if new.ocultacao_id is null then
      return new;  -- o CHECK da tabela recusa
    end if;
    select o.avaliacao_id, o.analista_id into v_ocu
      from public.avaliacao_ocultacoes o where o.id = new.ocultacao_id;
    if v_ocu.avaliacao_id is distinct from new.avaliacao_id then
      raise exception 'A ocultação é de outra avaliação' using errcode = 'check_violation';
    end if;
    if new.analista_id = v_ocu.analista_id
       and btrim(coalesce(new.mesmo_analista_justificativa, '')) = '' then
      raise exception 'Mesmo analista da ocultação: justificativa obrigatória' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.avaliacao_ocultacoes_aplicar() from public, anon, authenticated, service_role;
revoke all on function public.avaliacao_revisoes_validar() from public, anon, authenticated, service_role;
revoke all on function public.avaliacoes_travar_ocultada() from public, anon, authenticated, service_role;

drop trigger if exists avaliacoes_travar_ocultada_trg on public.avaliacoes;
create trigger avaliacoes_travar_ocultada_trg before update of status on public.avaliacoes
  for each row when (old.status is distinct from new.status)
  execute function public.avaliacoes_travar_ocultada();
drop trigger if exists avaliacao_ocultacoes_reverter_trg on public.avaliacao_ocultacoes;
create trigger avaliacao_ocultacoes_reverter_trg after update on public.avaliacao_ocultacoes
  for each row when (old.revertida_em is null and new.revertida_em is not null)
  execute function public.avaliacao_ocultacoes_aplicar();

drop trigger if exists avaliacao_ocultacoes_proteger on public.avaliacao_ocultacoes;
create trigger avaliacao_ocultacoes_proteger before update on public.avaliacao_ocultacoes
  for each row execute function public.proteger_colunas(
    'id', 'avaliacao_id', 'motivo', 'explicacao', 'analista_id', 'ocultada_em', 'status_anterior');
drop trigger if exists avaliacao_ocultacoes_aplicar_trg on public.avaliacao_ocultacoes;
create trigger avaliacao_ocultacoes_aplicar_trg before insert or update on public.avaliacao_ocultacoes
  for each row execute function public.avaliacao_ocultacoes_aplicar();
drop trigger if exists avaliacao_ocultacoes_sem_delete on public.avaliacao_ocultacoes;
create trigger avaliacao_ocultacoes_sem_delete before delete on public.avaliacao_ocultacoes
  for each row execute function public.bloquear_alteracao();
drop trigger if exists avaliacao_ocultacoes_sem_truncate on public.avaliacao_ocultacoes;
create trigger avaliacao_ocultacoes_sem_truncate before truncate on public.avaliacao_ocultacoes
  for each statement execute function public.bloquear_alteracao();

drop trigger if exists avaliacao_revisoes_protocolo on public.avaliacao_revisoes;
create trigger avaliacao_revisoes_protocolo before insert on public.avaliacao_revisoes
  for each row execute function public.sac_gerar_protocolo('REV', 'avaliacao_revisoes_protocolo_seq');
drop trigger if exists avaliacao_revisoes_proteger on public.avaliacao_revisoes;
create trigger avaliacao_revisoes_proteger before update on public.avaliacao_revisoes
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'avaliacao_id', 'tipo', 'ocultacao_id', 'solicitante_id', 'justificativa',
    'anexos', 'canal', 'aberta_em', 'responder_ate');
drop trigger if exists avaliacao_revisoes_validar_trg on public.avaliacao_revisoes;
create trigger avaliacao_revisoes_validar_trg before insert or update on public.avaliacao_revisoes
  for each row execute function public.avaliacao_revisoes_validar();
drop trigger if exists avaliacao_revisoes_sem_delete on public.avaliacao_revisoes;
create trigger avaliacao_revisoes_sem_delete before delete on public.avaliacao_revisoes
  for each row execute function public.bloquear_alteracao();
drop trigger if exists avaliacao_revisoes_sem_truncate on public.avaliacao_revisoes;
create trigger avaliacao_revisoes_sem_truncate before truncate on public.avaliacao_revisoes
  for each statement execute function public.bloquear_alteracao();

alter table public.avaliacao_ocultacoes enable row level security;
alter table public.avaliacao_revisoes enable row level security;
revoke all on table public.avaliacao_ocultacoes, public.avaliacao_revisoes
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.avaliacao_ocultacoes, public.avaliacao_revisoes to service_role;

commit;
