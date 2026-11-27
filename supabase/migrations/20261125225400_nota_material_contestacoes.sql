-- ===========================================================================
-- 20261125225400_nota_material_contestacoes.sql
-- RASCUNHO (TERMOS-DB5, 2/5). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2, 6.9: o cliente contesta material não comprovado ou diferente do combinado.
-- Depende de 20261125224500_sac_chamados (gerador de protocolo).
--
-- Reaproveita public.notas_material e nota_material_itens. Ao abrir a contestação, a nota
-- passa a status 'contestada' (valor que já existia). Esta tabela não move dinheiro.
-- RLS ligada, sem policy; só service_role; sem delete. Só acrescenta.
--
-- O banco exige: nascer aberta; analista ativo (mediador, lider_suporte, seguranca ou
-- administrador); aprovador ativo lider_suporte ou administrador, diferente do analista.
--
-- PRAZO: o backend calcula responder_ate (SAC, chave chamado_resposta_dias_uteis da
-- 20261125224500). Os Termos não fixam prazo para o cliente contestar.
--
-- Rollback: supabase/rollback/20261125225400_nota_material_contestacoes_rollback.sql
-- ===========================================================================

begin;

create sequence if not exists public.nota_material_contestacoes_protocolo_seq;
revoke all on sequence public.nota_material_contestacoes_protocolo_seq
  from public, anon, authenticated, service_role;

create table if not exists public.nota_material_contestacoes (
  id                          uuid primary key default gen_random_uuid(),
  protocolo                   text not null unique check (protocolo ~ '^CNM-[0-9]{4}-[0-9]{6,}$'),
  nota_id                     uuid not null references public.notas_material (id) on delete restrict,
  item_id                     uuid references public.nota_material_itens (id) on delete restrict,
  cliente_id                  uuid not null references public.usuarios (id) on delete restrict,
  motivo                      text not null check (motivo in ('nao_comprovado', 'diferente_do_combinado')),
  descricao                   text not null check (btrim(descricao) <> ''),
  anexos                      jsonb not null default '[]'::jsonb check (jsonb_typeof(anexos) = 'array'),
  valor_contestado_centavos   bigint not null check (valor_contestado_centavos >= 0),
  aberta_em                   timestamptz not null default now(),
  responder_ate               timestamptz not null,
  status                      text not null default 'aberta'
                                check (status in ('aberta', 'em_analise', 'procedente', 'parcial',
                                                  'improcedente')),
  analista_id                 uuid references public.equipe (usuario_id) on delete restrict,
  resposta                    text,
  valor_reconhecido_centavos  bigint check (valor_reconhecido_centavos is null
                                            or valor_reconhecido_centavos >= 0),
  decidida_em                 timestamptz,
  aprovada_por                uuid references public.equipe (usuario_id) on delete restrict,
  efeito_financeiro           text not null default 'nenhum'
                                check (efeito_financeiro in ('nenhum', 'pendente_financeiro', 'executado')),
  constraint nota_contestacoes_prazo_check check (responder_ate > aberta_em),
  constraint nota_contestacoes_decisao_check check (
    case when status in ('procedente', 'parcial', 'improcedente')
         then analista_id is not null and btrim(coalesce(resposta, '')) <> '' and decidida_em is not null
         else decidida_em is null end),
  constraint nota_contestacoes_valor_check check (
    (valor_reconhecido_centavos is null or valor_reconhecido_centavos <= valor_contestado_centavos)
    and (status not in ('procedente', 'parcial')
         or (valor_reconhecido_centavos is not null and valor_reconhecido_centavos > 0))
    and (status <> 'improcedente' or coalesce(valor_reconhecido_centavos, 0) = 0)),
  constraint nota_contestacoes_aprovador_check check (
    aprovada_por is null or aprovada_por is distinct from analista_id),
  constraint nota_contestacoes_efeito_check check (
    efeito_financeiro = 'nenhum'
    or (status in ('procedente', 'parcial') and aprovada_por is not null))
);
-- uma contestação em aberto por nota (inteira) ou por item
create unique index if not exists ux_nota_contestacoes_aberta
  on public.nota_material_contestacoes (nota_id, coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where status in ('aberta', 'em_analise');
create index if not exists ix_nota_contestacoes_status_prazo
  on public.nota_material_contestacoes (status, responder_ate);

create or replace function public.nota_material_contestacoes_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_nota record;
  v_item record;
  v_limite bigint;
  v_usado  bigint;
  v_usado_item bigint;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'aberta' or new.efeito_financeiro <> 'nenhum'
       or num_nonnulls(new.analista_id, new.resposta, new.valor_reconhecido_centavos,
                       new.decidida_em, new.aprovada_por) > 0 then
      raise exception 'A contestação nasce aberta, sem análise, decisão ou aprovação'
        using errcode = 'check_violation';
    end if;
    if new.aberta_em > now() + interval '5 minutes' then
      raise exception 'Data de abertura no futuro não é permitida'
        using errcode = 'check_violation';
    end if;
  else
    if old.status in ('procedente', 'parcial', 'improcedente')
       and ((to_jsonb(new) - 'efeito_financeiro' - 'aprovada_por')
              is distinct from (to_jsonb(old) - 'efeito_financeiro' - 'aprovada_por')
            or (old.aprovada_por is not null and new.aprovada_por is distinct from old.aprovada_por)
            or (old.efeito_financeiro = 'executado' and new.efeito_financeiro <> 'executado')
            or (old.efeito_financeiro = 'pendente_financeiro' and new.efeito_financeiro = 'nenhum')) then
      raise exception 'Contestação já decidida: só o efeito financeiro pode avançar'
        using errcode = 'restrict_violation';
    end if;
    if old.status = 'em_analise' and new.status = 'aberta' then
      raise exception 'Contestação em análise não volta para aberta'
        using errcode = 'check_violation';
    end if;
    if new.status = 'aberta'
       and num_nonnulls(new.analista_id, new.resposta, new.valor_reconhecido_centavos,
                        new.decidida_em, new.aprovada_por) > 0 then
      raise exception 'Contestação aberta não pode ter análise, decisão ou aprovação'
        using errcode = 'check_violation';
    end if;
    if new.status = 'em_analise' and new.analista_id is null then
      raise exception 'Contestação em análise exige analista'
        using errcode = 'check_violation';
    end if;
    if new.aprovada_por is not null and new.status not in ('procedente', 'parcial') then
      raise exception 'Aprovação só se aplica a contestação procedente ou parcial'
        using errcode = 'check_violation';
    end if;
    if new.decidida_em is not null
       and (new.decidida_em < old.aberta_em or new.decidida_em > now() + interval '5 minutes') then
      raise exception 'Data de decisão deve estar entre a abertura e o momento atual'
        using errcode = 'check_violation';
    end if;
    -- analista: pessoa ativa da equipe com papel de análise, ao assumir ou decidir
    if old.status in ('aberta', 'em_analise') and new.analista_id is not null
       and (new.analista_id is distinct from old.analista_id or new.status is distinct from old.status)
       and not exists (select 1 from public.equipe q
                        where q.usuario_id = new.analista_id and q.ativo and q.revogado_em is null
                          and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')) then
      raise exception 'Analista precisa ser da equipe ativa com papel de análise'
        using errcode = 'check_violation';
    end if;
    -- aprovador: alçada de líder de suporte ou administrador
    if new.aprovada_por is not null and new.aprovada_por is distinct from old.aprovada_por
       and not exists (select 1 from public.equipe q
                        where q.usuario_id = new.aprovada_por and q.ativo and q.revogado_em is null
                          and q.papel in ('lider_suporte', 'administrador')) then
      raise exception 'Aprovador precisa ser líder de suporte ou administrador ativo'
        using errcode = 'check_violation';
    end if;
    return new;
  end if;

  select n.total_centavos, c.cliente_id into v_nota
    from public.notas_material n join public.contratos c on c.id = n.contrato_id
   where n.id = new.nota_id
     for update of n;  -- serializa o teto acumulado por nota
  if v_nota.cliente_id is distinct from new.cliente_id then
    raise exception 'Só o cliente do contrato contesta a nota' using errcode = 'check_violation';
  end if;
  if new.item_id is not null then
    select i.nota_id, i.total_centavos into v_item from public.nota_material_itens i where i.id = new.item_id;
    if v_item.nota_id is distinct from new.nota_id then
      raise exception 'O item não é desta nota' using errcode = 'check_violation';
    end if;
  end if;
  if new.item_id is null then
    v_limite := v_nota.total_centavos;
  else
    v_limite := v_item.total_centavos;
  end if;
  if new.valor_contestado_centavos > v_limite then
    raise exception 'Valor contestado maior que o da nota ou do item' using errcode = 'check_violation';
  end if;
  -- a nota inteira e os itens não se sobrepõem (em aberto ou reconhecidos)
  if exists (select 1 from public.nota_material_contestacoes x
              where x.nota_id = new.nota_id and (x.item_id is null) <> (new.item_id is null)
                and x.status in ('aberta', 'em_analise', 'procedente', 'parcial')) then
    raise exception 'Contestação da nota inteira e de item se sobrepõem' using errcode = 'check_violation';
  end if;
  -- reconhecidos + em aberto nunca passam do valor da nota (nem do item)
  select coalesce(sum(case when x.status in ('aberta', 'em_analise') then x.valor_contestado_centavos
                           else coalesce(x.valor_reconhecido_centavos, 0) end), 0),
         coalesce(sum(case when x.status in ('aberta', 'em_analise') then x.valor_contestado_centavos
                           else coalesce(x.valor_reconhecido_centavos, 0) end)
                  filter (where x.item_id = new.item_id), 0)
    into v_usado, v_usado_item
    from public.nota_material_contestacoes x
   where x.nota_id = new.nota_id and x.status <> 'improcedente';
  if v_usado + new.valor_contestado_centavos > v_nota.total_centavos
     or (new.item_id is not null and v_usado_item + new.valor_contestado_centavos > v_limite) then
    raise exception 'Soma contestada passaria do valor da nota ou do item' using errcode = 'check_violation';
  end if;
  update public.notas_material set status = 'contestada' where id = new.nota_id and status <> 'contestada';
  return new;
end;
$$;
revoke all on function public.nota_material_contestacoes_validar() from public, anon, authenticated, service_role;

drop trigger if exists nota_contestacoes_protocolo on public.nota_material_contestacoes;
create trigger nota_contestacoes_protocolo before insert on public.nota_material_contestacoes
  for each row execute function public.sac_gerar_protocolo('CNM', 'nota_material_contestacoes_protocolo_seq');
drop trigger if exists nota_contestacoes_proteger on public.nota_material_contestacoes;
create trigger nota_contestacoes_proteger before update on public.nota_material_contestacoes
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'nota_id', 'item_id', 'cliente_id', 'motivo', 'descricao', 'anexos',
    'valor_contestado_centavos', 'aberta_em', 'responder_ate');
drop trigger if exists nota_contestacoes_validar_trg on public.nota_material_contestacoes;
create trigger nota_contestacoes_validar_trg before insert or update on public.nota_material_contestacoes
  for each row execute function public.nota_material_contestacoes_validar();
drop trigger if exists nota_contestacoes_sem_delete on public.nota_material_contestacoes;
create trigger nota_contestacoes_sem_delete before delete on public.nota_material_contestacoes
  for each row execute function public.bloquear_alteracao();
drop trigger if exists nota_contestacoes_sem_truncate on public.nota_material_contestacoes;
create trigger nota_contestacoes_sem_truncate before truncate on public.nota_material_contestacoes
  for each statement execute function public.bloquear_alteracao();

alter table public.nota_material_contestacoes enable row level security;
revoke all on table public.nota_material_contestacoes from public, anon, authenticated, service_role;
grant select, insert, update on table public.nota_material_contestacoes to service_role;

commit;
