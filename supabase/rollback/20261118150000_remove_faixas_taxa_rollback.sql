-- Desfaz 20261118150000_remove_faixas_taxa.sql: recria `config_faixas_taxa` VAZIA.
-- Os dados apagados NÃO voltam (restaure de backup, se precisar). Só rodar com OK do João.
-- Estrutura copiada da F3.2 (4.4) e da F3.8b (grants e policy).

create table public.config_faixas_taxa (
  id           uuid primary key default gen_random_uuid(),
  versao_id    uuid not null references public.config_versoes (id) on delete restrict,
  de_centavos  bigint not null check (de_centavos >= 0),
  ate_centavos bigint,  -- exclusivo; null = sem teto
  taxa_bps     integer not null check (taxa_bps between 0 and 10000),
  escopo_tipo  text not null default 'global'
                 check (escopo_tipo in ('global', 'cidade', 'categoria', 'nivel')),
  escopo_id    uuid,
  escopo_texto text,
  check (ate_centavos is null or ate_centavos > de_centavos),
  check (
    (escopo_tipo = 'global'    and escopo_id is null     and escopo_texto is null) or
    (escopo_tipo in ('cidade', 'categoria') and escopo_id is not null and escopo_texto is null) or
    (escopo_tipo = 'nivel'     and escopo_id is null     and escopo_texto is not null)
  ),
  exclude using gist (
    versao_id with =,
    escopo_tipo with =,
    (coalesce(escopo_id, '00000000-0000-0000-0000-000000000000'::uuid)) with =,
    (coalesce(escopo_texto, '')) with =,
    int8range(de_centavos, ate_centavos) with &&
  )
);
alter table public.config_faixas_taxa enable row level security;

create or replace function public.config_faixas_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  status_versao text;
begin
  if tg_op = 'DELETE' then
    select status into status_versao from public.config_versoes where id = old.versao_id;
  else
    select status into status_versao from public.config_versoes where id = new.versao_id;
  end if;
  if status_versao not in ('rascunho', 'aguardando_aprovacao') then
    raise exception 'Versão de configuração já aprovada: faixas de taxa não podem mudar';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
create trigger config_faixas_proteger_trg
  before insert or update or delete on public.config_faixas_taxa
  for each row execute function public.config_faixas_proteger();

revoke all on table public.config_faixas_taxa from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.config_faixas_taxa to service_role;
create policy config_faixas_taxa_select on public.config_faixas_taxa for select to authenticated
  using (privado.eh_equipe('financeiro', 'juridico', 'administrador'));
