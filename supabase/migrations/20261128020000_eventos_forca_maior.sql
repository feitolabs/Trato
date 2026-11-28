-- ===========================================================================
-- 20261128020000_eventos_forca_maior.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, cláusulas 7.8 e 22.6: registra pedidos de isenção por evento
-- externo / força maior vinculados a um Pedido (reagendamento sem custo ou
-- cancelamento com reembolso integral sem multa), com análise e decisão da equipe.
--
-- Nada aqui cancela, reagenda ou movimenta dinheiro sozinho: o Backend coordena
-- a transição do Pedido e eventual estorno junto com a decisão.
--
-- Só acrescenta; sem UPDATE de dados.
-- Depende de: F3.2 (usuarios, equipe, bloquear_alteracao), F3.3 (pedidos).
-- Rollback: supabase/rollback/20261128020000_eventos_forca_maior_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.pedidos') is null then
    raise exception 'Aplique antes a migration 20261029030000_f33_pedidos_orcamentos_contratos.sql (public.pedidos)';
  end if;
end $$;

create table if not exists public.eventos_forca_maior (
  id                    uuid primary key default gen_random_uuid(),
  pedido_id             uuid not null references public.pedidos (id) on delete restrict,
  solicitante_id        uuid not null references public.usuarios (id) on delete restrict,
  solicitante_papel     text not null
                          constraint eventos_forca_maior_papel_check
                          check (solicitante_papel in ('cliente', 'profissional')),
  acao_solicitada       text not null
                          constraint eventos_forca_maior_acao_check
                          check (acao_solicitada in ('reagendar', 'cancelar')),
  descricao             text not null
                          constraint eventos_forca_maior_descricao_check
                          check (char_length(btrim(descricao)) >= 10 and char_length(descricao) <= 1000),
  comprovantes          text[] not null default '{}'
                          constraint eventos_forca_maior_comprovantes_check
                          check (
                            (array_ndims(comprovantes) is null or array_ndims(comprovantes) = 1)
                            and array_position(comprovantes, null) is null
                          ),
  status                text not null default 'pendente'
                          constraint eventos_forca_maior_status_check
                          check (status in ('pendente', 'aprovado', 'recusado')),
  criado_em             timestamptz not null default now(),
  analista_id           uuid references public.equipe (usuario_id) on delete restrict,
  justificativa_decisao text
                          constraint eventos_forca_maior_justificativa_check
                          check (
                            justificativa_decisao is null
                            or (char_length(btrim(justificativa_decisao)) >= 10
                                and char_length(justificativa_decisao) <= 500)
                          ),
  decidido_em           timestamptz,
  chave_idempotencia    text
                          constraint eventos_forca_maior_idempotencia_check
                          check (chave_idempotencia is null or btrim(chave_idempotencia) <> ''),
  constraint eventos_forca_maior_decisao_completa_check
    check (num_nulls(analista_id, justificativa_decisao, decidido_em) in (0, 3)),
  constraint eventos_forca_maior_status_decisao_check
    check (
      (status = 'pendente' and decidido_em is null)
      or (status in ('aprovado', 'recusado') and decidido_em is not null)
    ),
  constraint eventos_forca_maior_decidido_em_check
    check (decidido_em is null or decidido_em >= criado_em)
);

create unique index if not exists eventos_forca_maior_idempotencia_uidx
  on public.eventos_forca_maior (chave_idempotencia)
  where chave_idempotencia is not null;
create index if not exists eventos_forca_maior_pedido_idx
  on public.eventos_forca_maior (pedido_id, criado_em desc);
create index if not exists eventos_forca_maior_pendentes_idx
  on public.eventos_forca_maior (criado_em)
  where status = 'pendente';
create index if not exists eventos_forca_maior_analista_idx
  on public.eventos_forca_maior (analista_id)
  where analista_id is not null;

create or replace function public.eventos_forca_maior_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if old.status <> 'pendente' then
      raise exception 'forca_maior_imutavel: evento já decidido não pode ser alterado'
        using errcode = 'restrict_violation';
    end if;

    if (new.id, new.pedido_id, new.solicitante_id, new.solicitante_papel,
        new.acao_solicitada, new.descricao, new.criado_em)
       is distinct from
       (old.id, old.pedido_id, old.solicitante_id, old.solicitante_papel,
        old.acao_solicitada, old.descricao, old.criado_em)
       or (old.chave_idempotencia is not null and new.chave_idempotencia is distinct from old.chave_idempotencia) then
      raise exception 'forca_maior_imutavel: dado inicial do evento não pode ser alterado'
        using errcode = 'restrict_violation';
    end if;
  end if;

  if new.status <> 'pendente' and new.analista_id is not null and (tg_op = 'INSERT' or old.status = 'pendente') then
    if not exists (
      select 1 from public.equipe e
       where e.usuario_id = new.analista_id
         and e.ativo
         and e.revogado_em is null
    ) then
      raise exception 'forca_maior_analista_inativo: analista precisa estar ativo na equipe'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end $$;
revoke all on function public.eventos_forca_maior_validar() from public, anon, authenticated, service_role;

drop trigger if exists eventos_forca_maior_validar_trg on public.eventos_forca_maior;
create trigger eventos_forca_maior_validar_trg
  before insert or update on public.eventos_forca_maior
  for each row execute function public.eventos_forca_maior_validar();

drop trigger if exists eventos_forca_maior_sem_delete on public.eventos_forca_maior;
create trigger eventos_forca_maior_sem_delete
  before delete on public.eventos_forca_maior
  for each row execute function public.bloquear_alteracao();

drop trigger if exists eventos_forca_maior_sem_truncate on public.eventos_forca_maior;
create trigger eventos_forca_maior_sem_truncate
  before truncate on public.eventos_forca_maior
  for each statement execute function public.bloquear_alteracao();

alter table public.eventos_forca_maior enable row level security;
revoke all on table public.eventos_forca_maior from public, anon, authenticated, service_role;
grant select, insert, update on table public.eventos_forca_maior to service_role;

commit;
