-- ===========================================================================
-- 20261125224600_medidas_conta.sql
-- RASCUNHO (TERMOS-DB4, 2/3). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2: 20.2 (decisão humana), 20.4 (aviso e motivo), 20.5 (contestação).
-- Depende de 20261125224500_sac_chamados.
--
-- Cria public.medidas_conta e public.medida_contestacoes, e a FK chamados.medida_id.
-- Os limites de 72 h (medida automática) e 7 dias (suspensão) são dos Termos e estão em
-- CHECK: mudar exige nova migration. Prazos de contestação e resposta vêm de configuração.
-- RLS ligada, sem policy; só service_role; sem delete. Só acrescenta.
--
-- CONFIGURAÇÃO (NÃO executada aqui; rodar só com OK do João):
--   insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao) values
--     ('medida_contestacao_prazo_dias',          'Prazo para contestar medida, a partir do aviso (20.5)', 'dias',       30, 90, array['global'], false),
--     ('medida_contestacao_resposta_dias_uteis', 'Prazo de resposta da contestação de medida (20.5)',     'dias_uteis',  1, 10, array['global'], false)
--   on conflict (chave) do nothing;
--   -- valores do Anexo II: 30 e 10.
--
-- Rollback: supabase/rollback/20261125224600_medidas_conta_rollback.sql
-- ===========================================================================

begin;

create sequence if not exists public.medidas_conta_protocolo_seq;
create sequence if not exists public.medida_contestacoes_protocolo_seq;
revoke all on sequence public.medidas_conta_protocolo_seq, public.medida_contestacoes_protocolo_seq
  from public, anon, authenticated, service_role;

create table if not exists public.medidas_conta (
  id                      uuid primary key default gen_random_uuid(),
  protocolo               text not null unique check (protocolo ~ '^MED-[0-9]{4}-[0-9]{6,}$'),
  usuario_id              uuid not null references public.usuarios (id) on delete restrict,
  tipo                    text not null check (tipo in ('aviso', 'restricao', 'suspensao', 'encerramento',
                                                        'bloqueio_preventivo', 'trava_saque',
                                                        'remocao_conteudo')),
  motivo_usuario          text not null check (btrim(motivo_usuario) <> ''),
  nota_interna            text,
  clausulas               text[] not null,
  inicio_em               timestamptz not null default now(),
  fim_em                  timestamptz,
  efeito_pedidos_valores  text not null check (btrim(efeito_pedidos_valores) <> ''),
  como_contestar          text not null check (btrim(como_contestar) <> ''),
  detalhe_adiado          boolean not null default false,
  justificativa_adiamento text,
  aviso_adiado            boolean not null default false,
  avisado_em              timestamptz,
  contestavel_ate         timestamptz,
  origem                  text not null check (origem in ('analista', 'automatica')),
  aplicada_por            uuid references public.equipe (usuario_id) on delete restrict,
  revertida_em            timestamptz,
  revertida_por           uuid references public.equipe (usuario_id) on delete restrict,
  conteudo_tipo           text,
  conteudo_id             uuid,
  criado_em               timestamptz not null default now(),
  constraint medidas_conta_clausulas_check check (
    cardinality(clausulas) > 0 and array_position(clausulas, null) is null
    and array_position(clausulas, '') is null),
  constraint medidas_conta_periodo_check check (fim_em is null or fim_em > inicio_em),
  constraint medidas_conta_automatica_check check (
    origem <> 'automatica'
    or (fim_em is not null and fim_em <= inicio_em + interval '72 hours' and aplicada_por is null)),
  constraint medidas_conta_analista_check check (origem <> 'analista' or aplicada_por is not null),
  -- 20.2: encerramento e suspensão acima de 7 dias (ou sem fim) são decididos por Analista
  constraint medidas_conta_decisao_humana_check check (
    not (tipo = 'encerramento'
         or (tipo = 'suspensao' and (fim_em is null or fim_em > inicio_em + interval '7 days')))
    or (origem = 'analista' and aplicada_por is not null)),
  constraint medidas_conta_adiamento_check check (
    not (detalhe_adiado or aviso_adiado) or btrim(coalesce(justificativa_adiamento, '')) <> ''),
  constraint medidas_conta_reversao_check check ((revertida_em is null) = (revertida_por is null)),
  constraint medidas_conta_conteudo_check check ((conteudo_tipo is null) = (conteudo_id is null))
);
create index if not exists ix_medidas_conta_usuario on public.medidas_conta (usuario_id, criado_em desc);
create index if not exists ix_medidas_conta_vigentes on public.medidas_conta (usuario_id, tipo, fim_em)
  where revertida_em is null;

create table if not exists public.medida_contestacoes (
  id                            uuid primary key default gen_random_uuid(),
  protocolo                     text not null unique check (protocolo ~ '^CMD-[0-9]{4}-[0-9]{6,}$'),
  medida_id                     uuid not null unique references public.medidas_conta (id) on delete restrict,
  usuario_id                    uuid not null references public.usuarios (id) on delete restrict,
  versao_usuario                text not null check (btrim(versao_usuario) <> ''),
  anexos                        jsonb not null default '[]'::jsonb check (jsonb_typeof(anexos) = 'array'),
  canal                         text not null check (canal in ('app', 'sac')),
  aberta_em                     timestamptz not null default now(),
  responder_ate                 timestamptz not null,
  status                        text not null default 'aberta'
                                  check (status in ('aberta', 'em_analise', 'mantida', 'alterada', 'revertida')),
  analista_id                   uuid references public.equipe (usuario_id) on delete restrict,
  resposta                      text,
  mesmo_analista_justificativa  text,
  decidida_em                   timestamptz,
  constraint medida_contestacoes_decisao_check check (
    case when status in ('mantida', 'alterada', 'revertida')
         then analista_id is not null and btrim(coalesce(resposta, '')) <> '' and decidida_em is not null
         else decidida_em is null end)
);
create index if not exists ix_medida_contestacoes_status_prazo
  on public.medida_contestacoes (status, responder_ate);

-- 20.2: medidas automáticas não se emendam. Nova automática só se, junto das automáticas do
-- mesmo usuário encerradas há menos de 72 h, o total não passar de 72 h.
create or replace function public.medidas_conta_encadeamento()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.origem <> 'automatica' then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('medida_automatica:' || new.usuario_id::text, 0));
  if exists (select 1 from public.medidas_conta m
              where m.usuario_id = new.usuario_id and m.origem = 'automatica' and m.id <> new.id
                and m.fim_em > new.inicio_em - interval '72 hours'
                and m.inicio_em < new.fim_em + interval '72 hours'
                and greatest(m.fim_em, new.fim_em) - least(m.inicio_em, new.inicio_em) > interval '72 hours') then
    raise exception 'Medidas automáticas encadeadas passariam de 72 h: exige decisão de Analista'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.medidas_conta_encadeamento() from public, anon, authenticated, service_role;

create or replace function public.medida_contestacoes_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_medida record;
begin
  if tg_op = 'UPDATE' and old.status in ('mantida', 'alterada', 'revertida') then
    raise exception 'Contestação já decidida não pode mudar' using errcode = 'restrict_violation';
  end if;
  select m.usuario_id, m.aplicada_por into v_medida from public.medidas_conta m where m.id = new.medida_id;
  if v_medida.usuario_id is distinct from new.usuario_id then
    raise exception 'Só o usuário da medida pode contestá-la' using errcode = 'check_violation';
  end if;
  -- 20.5: outro analista sempre que possível; se for o mesmo, justificar
  if new.analista_id is not null and new.analista_id = v_medida.aplicada_por
     and btrim(coalesce(new.mesmo_analista_justificativa, '')) = '' then
    raise exception 'Mesmo analista da medida: justificativa obrigatória' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.medida_contestacoes_validar() from public, anon, authenticated, service_role;

drop trigger if exists medidas_conta_protocolo on public.medidas_conta;
create trigger medidas_conta_protocolo before insert on public.medidas_conta
  for each row execute function public.sac_gerar_protocolo('MED', 'medidas_conta_protocolo_seq');
drop trigger if exists medidas_conta_proteger on public.medidas_conta;
create trigger medidas_conta_proteger before update on public.medidas_conta
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'usuario_id', 'tipo', 'clausulas', 'origem', 'aplicada_por', 'inicio_em', 'criado_em');
drop trigger if exists medidas_conta_encadeamento_trg on public.medidas_conta;
create trigger medidas_conta_encadeamento_trg before insert or update on public.medidas_conta
  for each row execute function public.medidas_conta_encadeamento();
drop trigger if exists medidas_conta_sem_delete on public.medidas_conta;
create trigger medidas_conta_sem_delete before delete on public.medidas_conta
  for each row execute function public.bloquear_alteracao();
drop trigger if exists medidas_conta_sem_truncate on public.medidas_conta;
create trigger medidas_conta_sem_truncate before truncate on public.medidas_conta
  for each statement execute function public.bloquear_alteracao();

drop trigger if exists medida_contestacoes_protocolo on public.medida_contestacoes;
create trigger medida_contestacoes_protocolo before insert on public.medida_contestacoes
  for each row execute function public.sac_gerar_protocolo('CMD', 'medida_contestacoes_protocolo_seq');
drop trigger if exists medida_contestacoes_proteger on public.medida_contestacoes;
create trigger medida_contestacoes_proteger before update on public.medida_contestacoes
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'medida_id', 'usuario_id', 'versao_usuario', 'anexos', 'canal', 'aberta_em',
    'responder_ate');
drop trigger if exists medida_contestacoes_validar_trg on public.medida_contestacoes;
create trigger medida_contestacoes_validar_trg before insert or update on public.medida_contestacoes
  for each row execute function public.medida_contestacoes_validar();
drop trigger if exists medida_contestacoes_sem_delete on public.medida_contestacoes;
create trigger medida_contestacoes_sem_delete before delete on public.medida_contestacoes
  for each row execute function public.bloquear_alteracao();
drop trigger if exists medida_contestacoes_sem_truncate on public.medida_contestacoes;
create trigger medida_contestacoes_sem_truncate before truncate on public.medida_contestacoes
  for each statement execute function public.bloquear_alteracao();

alter table public.chamados drop constraint if exists chamados_medida_fk;
alter table public.chamados add constraint chamados_medida_fk
  foreign key (medida_id) references public.medidas_conta (id) on delete restrict;

alter table public.medidas_conta enable row level security;
alter table public.medida_contestacoes enable row level security;
revoke all on table public.medidas_conta, public.medida_contestacoes
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.medidas_conta, public.medida_contestacoes to service_role;

commit;
