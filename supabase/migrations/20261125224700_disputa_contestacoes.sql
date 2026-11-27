-- ===========================================================================
-- 20261125224700_disputa_contestacoes.sql
-- RASCUNHO (TERMOS-DB4, 3/3). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2: 8.7 (contestação da decisão, por outro Analista).
-- Depende de 20261125224500_sac_chamados (gerador de protocolo).
-- NÃO usa public.contestacoes, que é chargeback.
--
-- Uma contestação por parte e por disputa decidida. Analista e aprovador são diferentes
-- entre si e de quem decidiu ou aprovou a disputa. Efeito financeiro exige aprovador e o
-- reembolso não passa do valor congelado na disputa. Esta tabela só registra: não move
-- dinheiro nem muda a disputa. RLS ligada, sem policy; só service_role; sem delete.
--
-- CONFIGURAÇÃO (NÃO executada aqui; rodar só com OK do João):
--   insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao) values
--     ('disputa_contestacao_prazo_dias_uteis',    'Prazo para contestar a decisão da disputa (8.7)', 'dias_uteis', 5, 30, array['global'], false),
--     ('disputa_contestacao_resposta_dias_uteis', 'Prazo de resposta da contestação (8.7)',          'dias_uteis', 1, 10, array['global'], false)
--   on conflict (chave) do nothing;
--   -- valores do Anexo II: 5 e 10. Dias úteis consideram feriados nacionais e de Belo Horizonte.
--
-- Rollback: supabase/rollback/20261125224700_disputa_contestacoes_rollback.sql
-- ===========================================================================

begin;

create sequence if not exists public.disputa_contestacoes_protocolo_seq;
revoke all on sequence public.disputa_contestacoes_protocolo_seq
  from public, anon, authenticated, service_role;

create table if not exists public.disputa_contestacoes (
  id                             uuid primary key default gen_random_uuid(),
  protocolo                      text not null unique check (protocolo ~ '^CDS-[0-9]{4}-[0-9]{6,}$'),
  disputa_id                     uuid not null references public.disputas (id) on delete restrict,
  pedido_id                      uuid not null references public.pedidos (id) on delete restrict,
  contestante_id                 uuid not null references public.usuarios (id) on delete restrict,
  o_que_faltou                   text not null check (btrim(o_que_faltou) <> ''),
  anexos                         jsonb not null default '[]'::jsonb check (jsonb_typeof(anexos) = 'array'),
  canal                          text not null check (canal in ('app', 'sac')),
  aberta_em                      timestamptz not null default now(),
  contestar_ate                  timestamptz not null,
  responder_ate                  timestamptz not null,
  status                         text not null default 'aberta'
                                   check (status in ('aberta', 'em_analise', 'aguardando_aprovacao',
                                                     'mantida', 'alterada', 'revertida')),
  analista_id                    uuid references public.equipe (usuario_id) on delete restrict,
  resposta                       text,
  nova_decisao                   text check (nova_decisao is null or nova_decisao in
                                   ('liberar_tudo', 'reembolso_total', 'reembolso_parcial', 'nova_visita')),
  novo_valor_reembolso_centavos  bigint check (novo_valor_reembolso_centavos is null
                                               or novo_valor_reembolso_centavos >= 0),
  aprovada_por                   uuid references public.equipe (usuario_id) on delete restrict,
  decidida_em                    timestamptz,
  efeito_financeiro              text not null default 'nenhum'
                                   check (efeito_financeiro in ('nenhum', 'pendente_financeiro', 'executado')),
  constraint disputa_contestacoes_unica unique (disputa_id, contestante_id),
  constraint disputa_contestacoes_prazo_check check (aberta_em <= contestar_ate),
  constraint disputa_contestacoes_pessoas_check check (
    analista_id is null or aprovada_por is null or analista_id <> aprovada_por),
  constraint disputa_contestacoes_analista_check check (
    status in ('aberta', 'em_analise') or analista_id is not null),
  constraint disputa_contestacoes_decisao_check check (
    case when status in ('mantida', 'alterada', 'revertida')
         then btrim(coalesce(resposta, '')) <> '' and decidida_em is not null
         else decidida_em is null end),
  constraint disputa_contestacoes_valor_check check (
    nova_decisao is distinct from 'reembolso_parcial' or novo_valor_reembolso_centavos is not null),
  constraint disputa_contestacoes_efeito_check check (
    efeito_financeiro = 'nenhum'
    or (status in ('alterada', 'revertida') and aprovada_por is not null))
);
create index if not exists ix_disputa_contestacoes_status_prazo
  on public.disputa_contestacoes (status, responder_ate);
create index if not exists ix_disputa_contestacoes_pedido on public.disputa_contestacoes (pedido_id);

create or replace function public.disputa_contestacoes_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_disputa record;
begin
  if tg_op = 'UPDATE' and old.status in ('mantida', 'alterada', 'revertida') then
    -- depois de decidida, só o andamento financeiro avança
    if (to_jsonb(new) - 'efeito_financeiro') is distinct from (to_jsonb(old) - 'efeito_financeiro')
       or (old.efeito_financeiro = 'executado' and new.efeito_financeiro <> 'executado')
       or (old.efeito_financeiro = 'pendente_financeiro' and new.efeito_financeiro = 'nenhum') then
      raise exception 'Contestação já decidida: só o efeito financeiro pode avançar'
        using errcode = 'restrict_violation';
    end if;
    return new;
  end if;

  select d.pedido_id, d.status, d.decidida_por, d.aprovada_por, d.valor_congelado_centavos,
         c.cliente_id, c.profissional_id
    into v_disputa
    from public.disputas d join public.contratos c on c.id = d.contrato_id
   where d.id = new.disputa_id;
  if tg_op = 'INSERT' then
    if v_disputa.status is distinct from 'decidida' then
      raise exception 'Só uma disputa decidida pode ser contestada' using errcode = 'check_violation';
    end if;
    if new.pedido_id is distinct from v_disputa.pedido_id then
      raise exception 'O pedido não é o da disputa' using errcode = 'check_violation';
    end if;
    if new.contestante_id is distinct from v_disputa.cliente_id
       and new.contestante_id is distinct from v_disputa.profissional_id then
      raise exception 'Só uma das partes contesta a decisão' using errcode = 'check_violation';
    end if;
  end if;
  if new.novo_valor_reembolso_centavos > v_disputa.valor_congelado_centavos then
    raise exception 'Reembolso maior que o valor congelado na disputa' using errcode = 'check_violation';
  end if;
  if new.analista_id in (v_disputa.decidida_por, v_disputa.aprovada_por)
     or new.aprovada_por in (v_disputa.decidida_por, v_disputa.aprovada_por) then
    raise exception 'Analista e aprovador da contestação não podem ter decidido ou aprovado a disputa'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.disputa_contestacoes_validar() from public, anon, authenticated, service_role;

drop trigger if exists disputa_contestacoes_protocolo on public.disputa_contestacoes;
create trigger disputa_contestacoes_protocolo before insert on public.disputa_contestacoes
  for each row execute function public.sac_gerar_protocolo('CDS', 'disputa_contestacoes_protocolo_seq');
drop trigger if exists disputa_contestacoes_proteger on public.disputa_contestacoes;
create trigger disputa_contestacoes_proteger before update on public.disputa_contestacoes
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'disputa_id', 'pedido_id', 'contestante_id', 'o_que_faltou', 'anexos', 'canal',
    'aberta_em', 'contestar_ate', 'responder_ate');
drop trigger if exists disputa_contestacoes_validar_trg on public.disputa_contestacoes;
create trigger disputa_contestacoes_validar_trg before insert or update on public.disputa_contestacoes
  for each row execute function public.disputa_contestacoes_validar();
drop trigger if exists disputa_contestacoes_sem_delete on public.disputa_contestacoes;
create trigger disputa_contestacoes_sem_delete before delete on public.disputa_contestacoes
  for each row execute function public.bloquear_alteracao();
drop trigger if exists disputa_contestacoes_sem_truncate on public.disputa_contestacoes;
create trigger disputa_contestacoes_sem_truncate before truncate on public.disputa_contestacoes
  for each statement execute function public.bloquear_alteracao();

alter table public.disputa_contestacoes enable row level security;
revoke all on table public.disputa_contestacoes from public, anon, authenticated, service_role;
grant select, insert, update on table public.disputa_contestacoes to service_role;

commit;
