-- ===========================================================================
-- 20261125225700_lgpd_pedidos_titular.sql
-- RASCUNHO (TERMOS-DB5, 5/5). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2: 14.9 (direitos do titular, com prazo e explicação) e 14.10 (revisão por
-- pessoa de decisão automatizada, informando os critérios).
-- Depende de 20261125224500_sac_chamados (gerador de protocolo).
--
-- public.lgpd_pedidos_exclusao continua sendo o fluxo de exclusão da conta; um pedido aqui
-- pode apontar para ele. RLS ligada, sem policy; só service_role; sem delete. Só acrescenta.
-- O pedido nasce 'aberto' e sem analista; responder_ate vai no máximo até o fim do 15º dia
-- (Brasília). Quem atende: dpo ou administrador; revisão de decisão automatizada aceita
-- também seguranca. Anonimizar: só dpo ou administrador.
--
-- PRAZO (o backend calcula responder_ate). NÃO executado aqui; rodar só com OK do João:
--   insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao) values
--     ('lgpd_pedido_resposta_dias', 'Prazo de resposta a pedido sobre dados pessoais (14.9)', 'dias', 1, 15, array['global'], false)
--   on conflict (chave) do nothing;
--   -- valor do Anexo II: 15. Mesma regra da chave chamado_dados_pessoais_resposta_dias
--   -- comentada na 20261125224500: use só uma (esta).
--
-- Rollback: supabase/rollback/20261125225700_lgpd_pedidos_titular_rollback.sql
-- ===========================================================================

begin;

create sequence if not exists public.lgpd_pedidos_titular_protocolo_seq;
revoke all on sequence public.lgpd_pedidos_titular_protocolo_seq from public, anon, authenticated, service_role;

create table if not exists public.lgpd_pedidos_titular (
  id                    uuid primary key default gen_random_uuid(),
  protocolo             text not null unique check (protocolo ~ '^LGPD-[0-9]{4}-[0-9]{6,}$'),
  usuario_id            uuid references public.usuarios (id) on delete restrict,
  contato               text check (contato is null or char_length(contato) <= 320),
  tipo                  text not null check (tipo in ('confirmacao', 'acesso', 'correcao',
                          'anonimizacao_bloqueio_eliminacao', 'portabilidade', 'eliminacao_consentimento',
                          'compartilhamento', 'nao_consentir', 'revogacao_consentimento',
                          'revisao_decisao_automatizada')),
  decisao_automatizada  text check (decisao_automatizada is null or decisao_automatizada in
                          ('ocultacao_contato', 'documentos_rosto', 'alerta_fraude',
                           'ordem_resultados', 'outra')),
  referencia_tipo       text,
  referencia_id         uuid,
  descricao             text not null default '',
  canal                 text not null check (canal in ('app', 'email', 'sac', 'painel')),
  exclusao_id           uuid references public.lgpd_pedidos_exclusao (id) on delete restrict,
  aberto_em             timestamptz not null default now(),
  responder_ate         timestamptz not null,
  status                text not null default 'aberto'
                          check (status in ('aberto', 'em_analise', 'aguardando_titular', 'atendido',
                                            'atendido_parcial', 'negado')),
  analista_id           uuid references public.equipe (usuario_id) on delete restrict,
  resposta              text,
  motivo_nao_atendido   text,
  criterios_informados  text,
  respondido_em         timestamptz,
  constraint lgpd_titular_identificacao_check check (
    usuario_id is not null or btrim(coalesce(contato, '')) <> ''),
  constraint lgpd_titular_automatizada_check check (
    (tipo = 'revisao_decisao_automatizada') = (decisao_automatizada is not null)),
  constraint lgpd_titular_referencia_check check ((referencia_tipo is null) = (referencia_id is null)),
  constraint lgpd_titular_prazo_check check (responder_ate > aberto_em),
  constraint lgpd_titular_resposta_check check (
    case when status in ('atendido', 'atendido_parcial', 'negado')
         then analista_id is not null and btrim(coalesce(resposta, '')) <> '' and respondido_em is not null
         else respondido_em is null end),
  constraint lgpd_titular_motivo_check check (
    status not in ('atendido_parcial', 'negado') or btrim(coalesce(motivo_nao_atendido, '')) <> ''),
  constraint lgpd_titular_criterios_check check (
    tipo <> 'revisao_decisao_automatizada'
    or status not in ('atendido', 'atendido_parcial', 'negado')
    or btrim(coalesce(criterios_informados, '')) <> '')
);
create index if not exists ix_lgpd_titular_status_prazo on public.lgpd_pedidos_titular (status, responder_ate);
create index if not exists ix_lgpd_titular_usuario on public.lgpd_pedidos_titular (usuario_id, aberto_em desc)
  where usuario_id is not null;

-- Não nasce respondido; respondido não muda; contato e descrição só mudam pela anonimização.
-- SECURITY INVOKER de propósito, para enxergar quem altera.
create or replace function public.lgpd_pedidos_titular_validar()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status in ('atendido', 'atendido_parcial', 'negado') or new.respondido_em is not null
       or new.resposta is not null or new.motivo_nao_atendido is not null
       or new.criterios_informados is not null then
      raise exception 'Pedido de titular não nasce respondido' using errcode = 'check_violation';
    end if;
    return new;
  end if;
  if coalesce(current_setting('trato.anonimizando', true), '') = 'sim'
            and current_user = (select pg_get_userbyid(f.proowner) from pg_catalog.pg_proc f
                                 where f.oid = to_regprocedure('public.anonimizar_pedido_titular(uuid,uuid,text)'))
     and (to_jsonb(new) - 'contato' - 'descricao' - 'resposta' - 'motivo_nao_atendido' - 'criterios_informados')
       = (to_jsonb(old) - 'contato' - 'descricao' - 'resposta' - 'motivo_nao_atendido' - 'criterios_informados') then
    return new;
  end if;
  if old.status in ('atendido', 'atendido_parcial', 'negado') then
    raise exception 'Pedido já respondido não pode mudar' using errcode = 'restrict_violation';
  end if;
  if (new.contato, new.descricao) is distinct from (old.contato, old.descricao) then
    raise exception 'Contato e descrição não mudam' using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

-- Regras que consultam equipe e pedidos de exclusão (SECURITY DEFINER).
create or replace function public.lgpd_pedidos_titular_checar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'aberto' or new.analista_id is not null then
      raise exception 'Pedido de titular nasce aberto e sem analista: não nasce respondido' using errcode = 'check_violation';
    end if;
    if new.aberto_em > now() + interval '5 minutes' then
      raise exception 'Abertura do pedido não pode ser no futuro' using errcode = 'check_violation';
    end if;
    if new.responder_ate >= (((new.aberto_em at time zone interval '-3 hours')::date + 16)::timestamp
                              at time zone interval '-3 hours') then
      raise exception 'Prazo de resposta passa de 15 dias' using errcode = 'check_violation';
    end if;
  else
    if (old.exclusao_id is not null and new.exclusao_id is distinct from old.exclusao_id)
       or new.tipo is distinct from old.tipo
       or new.decisao_automatizada is distinct from old.decisao_automatizada
       or (old.referencia_id is not null
           and (new.referencia_tipo, new.referencia_id) is distinct from (old.referencia_tipo, old.referencia_id)) then
      raise exception 'Dado já gravado (tipo, decisão, referência ou exclusão ligada) não pode ser alterado' using errcode = 'restrict_violation';
    end if;
    if new.respondido_em is distinct from old.respondido_em and new.respondido_em < new.aberto_em then
      raise exception 'Resposta não pode ser antes da abertura' using errcode = 'check_violation';
    end if;
  end if;
  if new.exclusao_id is not null
     and (tg_op = 'INSERT' or new.exclusao_id is distinct from old.exclusao_id)
     and not exists (select 1 from public.lgpd_pedidos_exclusao e
                      where e.id = new.exclusao_id and e.usuario_id = new.usuario_id) then
    raise exception 'Pedido de exclusão é de outra pessoa' using errcode = 'check_violation';
  end if;
  if new.analista_id is not null
     and (tg_op = 'INSERT'
          or new.analista_id is distinct from old.analista_id
          or new.status is distinct from old.status)
     and not exists (select 1 from public.equipe q
                      where q.usuario_id = new.analista_id and q.ativo and q.revogado_em is null
                        and (q.papel in ('dpo', 'administrador')
                             or (new.tipo = 'revisao_decisao_automatizada' and q.papel = 'seguranca'))) then
    raise exception 'Analista sem papel para este pedido' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- LGPD: apaga contato e textos de um pedido RESPONDIDO, sem apagar a linha, com auditoria.
create or replace function public.anonimizar_pedido_titular(p_pedido uuid, p_analista uuid, p_motivo text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_status text;
begin
  if p_pedido is null or p_analista is null or p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'pedido, analista e motivo são obrigatórios';
  end if;
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = p_analista and q.ativo and q.revogado_em is null
                    and q.papel in ('dpo', 'administrador')) then
    return 'analista_invalido';
  end if;
  select t.status into v_status from public.lgpd_pedidos_titular t where t.id = p_pedido for update;
  if not found then
    return 'nao_encontrado';
  end if;
  if v_status not in ('atendido', 'atendido_parcial', 'negado') then
    return 'nao_respondido';
  end if;
  perform set_config('trato.anonimizando', 'sim', true);
  update public.lgpd_pedidos_titular
     set contato = case when contato is null then null else '[anonimizado]' end,
         descricao = '[anonimizado]',
         resposta = case when resposta is null then null else '[anonimizado]' end,
         motivo_nao_atendido = case when motivo_nao_atendido is null then null else '[anonimizado]' end,
         criterios_informados = case when criterios_informados is null then null else '[anonimizado]' end
   where id = p_pedido;
  perform set_config('trato.anonimizando', '', true);
  perform public.registrar_auditoria(
    p_analista, 'equipe', 'dado_pessoal.anonimizacao_pedido_titular', 'lgpd_pedido_titular', p_pedido,
    null, null, btrim(p_motivo), null, null, null);
  return 'ok';
end;
$$;
revoke all on function public.anonimizar_pedido_titular(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.anonimizar_pedido_titular(uuid, uuid, text) to service_role;
revoke all on function public.lgpd_pedidos_titular_validar() from public, anon, authenticated, service_role;
revoke all on function public.lgpd_pedidos_titular_checar() from public, anon, authenticated, service_role;

drop trigger if exists lgpd_titular_protocolo on public.lgpd_pedidos_titular;
create trigger lgpd_titular_protocolo before insert on public.lgpd_pedidos_titular
  for each row execute function public.sac_gerar_protocolo('LGPD', 'lgpd_pedidos_titular_protocolo_seq');
drop trigger if exists lgpd_titular_proteger on public.lgpd_pedidos_titular;
create trigger lgpd_titular_proteger before update on public.lgpd_pedidos_titular
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'usuario_id', 'canal', 'aberto_em', 'responder_ate');
drop trigger if exists lgpd_titular_validar_trg on public.lgpd_pedidos_titular;
create trigger lgpd_titular_validar_trg before insert or update on public.lgpd_pedidos_titular
  for each row execute function public.lgpd_pedidos_titular_validar();
-- depois de lgpd_titular_validar_trg (ordem alfabética): "já respondido" vem primeiro
drop trigger if exists lgpd_titular_validar_z_checar_trg on public.lgpd_pedidos_titular;
create trigger lgpd_titular_validar_z_checar_trg before insert or update on public.lgpd_pedidos_titular
  for each row execute function public.lgpd_pedidos_titular_checar();
drop trigger if exists lgpd_titular_sem_delete on public.lgpd_pedidos_titular;
create trigger lgpd_titular_sem_delete before delete on public.lgpd_pedidos_titular
  for each row execute function public.bloquear_alteracao();
drop trigger if exists lgpd_titular_sem_truncate on public.lgpd_pedidos_titular;
create trigger lgpd_titular_sem_truncate before truncate on public.lgpd_pedidos_titular
  for each statement execute function public.bloquear_alteracao();

alter table public.lgpd_pedidos_titular enable row level security;
revoke all on table public.lgpd_pedidos_titular from public, anon, authenticated, service_role;
grant select, insert, update on table public.lgpd_pedidos_titular to service_role;

commit;
