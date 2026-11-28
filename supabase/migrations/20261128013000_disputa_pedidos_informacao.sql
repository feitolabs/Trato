-- ===========================================================================
-- 20261128013000_disputa_pedidos_informacao.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, cláusula 8.4: registra pedidos de informação adicional feitos
-- pela equipe em uma disputa (prazo mínimo de 10 dias úteis em Brasília),
-- a resposta da parte solicitada ou o encerramento sem resposta após o prazo.
--
-- Nada aqui encerra a disputa ou movimenta dinheiro sozinho: o Backend coordena
-- a transição da disputa e a prorrogação por indisponibilidade (22.3).
--
-- Só acrescenta; sem UPDATE de dados.
-- Depende de: F3.2 (equipe, bloquear_alteracao), F3.6 (disputas).
-- Rollback: supabase/rollback/20261128013000_disputa_pedidos_informacao_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.disputas') is null then
    raise exception 'Aplique antes a migration 20261029030300_f36_disputas_garantias_avaliacoes.sql (public.disputas)';
  end if;
end $$;

create table if not exists public.disputa_pedidos_informacao (
  id                        uuid primary key default gen_random_uuid(),
  disputa_id                uuid not null references public.disputas (id) on delete restrict,
  solicitante_id            uuid not null references public.equipe (usuario_id) on delete restrict,
  destinatario_papel        text not null
                              constraint disputa_pedidos_informacao_destinatario_check
                              check (destinatario_papel in ('cliente', 'profissional')),
  mensagem                  text not null
                              constraint disputa_pedidos_informacao_mensagem_check
                              check (char_length(btrim(mensagem)) >= 10 and char_length(mensagem) <= 1000),
  solicitado_em             timestamptz not null default now(),
  responder_ate             timestamptz not null,
  respondido_em             timestamptz,
  resposta_texto            text
                              constraint disputa_pedidos_informacao_resposta_texto_check
                              check (resposta_texto is null or btrim(resposta_texto) <> ''),
  encerrado_sem_resposta_em timestamptz,
  constraint disputa_pedidos_informacao_prazo_check
    check (responder_ate > solicitado_em),
  constraint disputa_pedidos_informacao_resposta_completa_check
    check (num_nulls(respondido_em, resposta_texto) in (0, 2)),
  constraint disputa_pedidos_informacao_desfecho_mutuo_check
    check (not (respondido_em is not null and encerrado_sem_resposta_em is not null)),
  constraint disputa_pedidos_informacao_respondido_em_check
    check (respondido_em is null or respondido_em >= solicitado_em),
  constraint disputa_pedidos_informacao_encerrado_em_check
    check (encerrado_sem_resposta_em is null or encerrado_sem_resposta_em > responder_ate)
);

create index if not exists disputa_pedidos_informacao_disputa_idx
  on public.disputa_pedidos_informacao (disputa_id, solicitado_em desc);
create index if not exists disputa_pedidos_informacao_pendentes_idx
  on public.disputa_pedidos_informacao (responder_ate)
  where respondido_em is null and encerrado_sem_resposta_em is null;
create index if not exists disputa_pedidos_informacao_solicitante_idx
  on public.disputa_pedidos_informacao (solicitante_id);

create or replace function public.disputa_pedidos_informacao_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_status text;
  v_dias   integer;
begin
  if tg_op = 'INSERT' then
    select d.status into v_status
      from public.disputas d
     where d.id = new.disputa_id
       for share;
    if v_status is null or v_status not in ('aberta', 'aguardando_profissional', 'em_analise') then
      raise exception 'disputa_pedido_info_status_invalido: disputa não aceita novo pedido de informação'
        using errcode = 'check_violation';
    end if;

    if not exists (
      select 1 from public.equipe e
       where e.usuario_id = new.solicitante_id
         and e.ativo
         and e.revogado_em is null
    ) then
      raise exception 'disputa_pedido_info_solicitante_inativo: solicitante precisa estar ativo na equipe'
        using errcode = 'check_violation';
    end if;

    select count(*) into v_dias
      from generate_series(
             (new.solicitado_em at time zone interval '-3 hours')::date + 1,
             (new.responder_ate at time zone interval '-3 hours')::date,
             interval '1 day') d
     where extract(isodow from d) < 6;
    if v_dias < 10 then
      raise exception 'disputa_pedido_info_prazo_curto: responder_ate precisa dar ao menos 10 dias úteis (Brasília)'
        using errcode = 'check_violation';
    end if;
  else
    if (new.id, new.disputa_id, new.solicitante_id, new.destinatario_papel,
        new.mensagem, new.solicitado_em, new.responder_ate)
       is distinct from
       (old.id, old.disputa_id, old.solicitante_id, old.destinatario_papel,
        old.mensagem, old.solicitado_em, old.responder_ate)
       or (old.respondido_em is not null and (new.respondido_em, new.resposta_texto)
           is distinct from (old.respondido_em, old.resposta_texto))
       or (old.encerrado_sem_resposta_em is not null and new.encerrado_sem_resposta_em
           is distinct from old.encerrado_sem_resposta_em) then
      raise exception 'disputa_pedido_info_imutavel: dado já registrado não pode ser alterado'
        using errcode = 'restrict_violation';
    end if;

    if new.respondido_em is not null and old.respondido_em is null then
      select d.status into v_status
        from public.disputas d
       where d.id = new.disputa_id
         for share;
      if v_status is null or v_status not in ('aberta', 'aguardando_profissional', 'em_analise') then
        raise exception 'disputa_pedido_info_status_invalido: disputa encerrada não aceita resposta'
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  if new.encerrado_sem_resposta_em is not null and new.encerrado_sem_resposta_em <= new.responder_ate then
    raise exception 'disputa_pedido_info_prazo_aberto: não é possível encerrar sem resposta antes de vencer responder_ate'
      using errcode = 'check_violation';
  end if;

  return new;
end $$;
revoke all on function public.disputa_pedidos_informacao_validar() from public, anon, authenticated, service_role;

drop trigger if exists disputa_pedidos_informacao_validar_trg on public.disputa_pedidos_informacao;
create trigger disputa_pedidos_informacao_validar_trg
  before insert or update on public.disputa_pedidos_informacao
  for each row execute function public.disputa_pedidos_informacao_validar();

drop trigger if exists disputa_pedidos_informacao_sem_delete on public.disputa_pedidos_informacao;
create trigger disputa_pedidos_informacao_sem_delete
  before delete on public.disputa_pedidos_informacao
  for each row execute function public.bloquear_alteracao();

drop trigger if exists disputa_pedidos_informacao_sem_truncate on public.disputa_pedidos_informacao;
create trigger disputa_pedidos_informacao_sem_truncate
  before truncate on public.disputa_pedidos_informacao
  for each statement execute function public.bloquear_alteracao();

alter table public.disputa_pedidos_informacao enable row level security;
revoke all on table public.disputa_pedidos_informacao from public, anon, authenticated, service_role;
grant select, insert, update on table public.disputa_pedidos_informacao to service_role;

commit;
