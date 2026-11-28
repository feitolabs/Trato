-- ===========================================================================
-- 20261127205000_janelas_indisponibilidade.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Objetivo (Termos v1.2, cláusula 22.3 — Prazos durante falhas):
-- criar a tabela `public.janelas_indisponibilidade` para registrar janelas de
-- indisponibilidade do aplicativo (`'app'`) ou do Parceiro de Pagamento
-- (`'pagamento'`), com início, fim opcional enquanto aberta, origem e motivo.
-- A tabela só registra: nenhum prazo é prorrogado pelo banco.
--
-- Histórico preservado: DELETE e TRUNCATE são recusados. O único UPDATE aceito é
-- encerrar uma janela aberta, uma única vez (fim_em + encerrada_por; encerrada_em
-- é preenchida com now() se não vier). Janela já encerrada não muda nem reabre.
--
-- Mudança aditiva e idempotente (`create table if not exists`,
-- `create index if not exists`), em transação única, sem UPDATE de dados.
-- RLS ligada e sem policy para o app; grants restritos a `service_role`.
-- Sem dependência de migrations anteriores (apenas `gen_random_uuid()` nativo).
--
-- Rollback: supabase/rollback/20261127205000_janelas_indisponibilidade_rollback.sql
-- ===========================================================================

begin;

create table if not exists public.janelas_indisponibilidade (
  id            uuid primary key default gen_random_uuid(),
  origem        text not null
                  constraint janelas_indisponibilidade_origem_check
                  check (origem in ('app', 'pagamento')),
  inicio_em     timestamptz not null,
  fim_em        timestamptz null,
  motivo        text not null
                  constraint janelas_indisponibilidade_motivo_check
                  check (length(trim(motivo)) >= 10),
  criada_por    text not null
                  constraint janelas_indisponibilidade_criada_por_check
                  check (length(trim(criada_por)) > 0),
  encerrada_por text null
                  constraint janelas_indisponibilidade_encerrada_por_check
                  check (encerrada_por is null or length(trim(encerrada_por)) > 0),
  criada_em     timestamptz not null default now(),
  encerrada_em  timestamptz null,
  constraint janelas_indisponibilidade_intervalo_check
    check (fim_em is null or fim_em > inicio_em),
  constraint janelas_indisponibilidade_encerramento_check
    check ((fim_em is null) = (encerrada_por is null)
       and (fim_em is null) = (encerrada_em is null))
);

create index if not exists ix_janelas_indisponibilidade_periodo
  on public.janelas_indisponibilidade (inicio_em, fim_em);

create index if not exists ix_janelas_indisponibilidade_abertas
  on public.janelas_indisponibilidade (inicio_em)
  where fim_em is null;

create or replace function public.janelas_indisponibilidade_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'janela_indisponibilidade_imutavel: o histórico não pode ser apagado'
      using errcode = 'P0001';
  end if;

  if tg_op = 'UPDATE' then
    if old.fim_em is not null then
      raise exception 'janela_indisponibilidade_imutavel: janela já encerrada não pode ser alterada'
        using errcode = 'P0001';
    end if;
    if new.fim_em is null
       or (new.id, new.origem, new.inicio_em, new.motivo, new.criada_por, new.criada_em)
          is distinct from
          (old.id, old.origem, old.inicio_em, old.motivo, old.criada_por, old.criada_em) then
      raise exception 'janela_indisponibilidade_imutavel: só é permitido encerrar a janela'
        using errcode = 'P0001';
    end if;
  end if;

  -- INSERT já encerrado (registro retroativo) ou encerramento de janela aberta.
  if new.fim_em is not null and new.encerrada_em is null then
    new.encerrada_em := now();
  end if;
  return new;
end $$;

revoke all on function public.janelas_indisponibilidade_proteger() from public, anon, authenticated;
grant execute on function public.janelas_indisponibilidade_proteger() to service_role;

drop trigger if exists janelas_indisponibilidade_validar on public.janelas_indisponibilidade;
create trigger janelas_indisponibilidade_validar
  before insert or update on public.janelas_indisponibilidade
  for each row execute function public.janelas_indisponibilidade_proteger();

drop trigger if exists janelas_indisponibilidade_sem_delete on public.janelas_indisponibilidade;
create trigger janelas_indisponibilidade_sem_delete
  before delete on public.janelas_indisponibilidade
  for each row execute function public.janelas_indisponibilidade_proteger();

drop trigger if exists janelas_indisponibilidade_sem_truncate on public.janelas_indisponibilidade;
create trigger janelas_indisponibilidade_sem_truncate
  before truncate on public.janelas_indisponibilidade
  for each statement execute function public.janelas_indisponibilidade_proteger();

alter table public.janelas_indisponibilidade enable row level security;

-- revoga também do service_role: o padrão do Supabase daria DELETE e TRUNCATE.
revoke all on table public.janelas_indisponibilidade from public, anon, authenticated, service_role;
grant select, insert, update on table public.janelas_indisponibilidade to service_role;

commit;