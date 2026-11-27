-- ===========================================================================
-- 20261126061100_ausencia_foto_chegada.sql
-- RASCUNHO (TERMOS-DB-86). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2, 7.6 (cliente ausente): guarda a foto da chegada, e não só o horário.
-- Depende de 20261125141500 (public.ausencias_cliente).
--
-- public.ausencias_cliente.foto_chegada_midia_id -> public.midias. A foto tem de ser do mesmo
-- pedido, enviada pelo profissional, com finalidade 'checkin'. Gravada uma vez (na criação ou
-- enquanto 'aguardando_espera') e não muda depois. Nula em serviço remoto e em linhas antigas.
-- Só acrescenta; nenhum dado é alterado.
--
-- Rollback: supabase/rollback/20261126061100_ausencia_foto_chegada_rollback.sql
-- ===========================================================================

begin;

alter table public.ausencias_cliente
  add column if not exists foto_chegada_midia_id uuid references public.midias (id) on delete restrict;

comment on column public.ausencias_cliente.foto_chegada_midia_id is
  'Mídia (finalidade checkin) enviada pelo profissional ao registrar a chegada. Gravada uma vez.';

create index if not exists ix_ausencias_cliente_foto_chegada
  on public.ausencias_cliente (foto_chegada_midia_id) where foto_chegada_midia_id is not null;

create or replace function public.ausencias_cliente_foto_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.foto_chegada_midia_id is not distinct from old.foto_chegada_midia_id then
      return new;
    end if;
    if old.foto_chegada_midia_id is not null or old.status <> 'aguardando_espera' then
      raise exception 'A foto da chegada é gravada uma vez, durante a espera, e não muda'
        using errcode = 'restrict_violation';
    end if;
  end if;
  if new.foto_chegada_midia_id is not null
     and not exists (select 1 from public.midias m
                      where m.id = new.foto_chegada_midia_id and m.pedido_id = new.pedido_id
                        and m.enviada_por = new.profissional_id and m.finalidade = 'checkin') then
    raise exception 'A foto da chegada deve ser uma mídia checkin deste pedido, enviada pelo profissional'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.ausencias_cliente_foto_validar() from public, anon, authenticated, service_role;

drop trigger if exists ausencias_cliente_foto_validar_trg on public.ausencias_cliente;
create trigger ausencias_cliente_foto_validar_trg before insert or update on public.ausencias_cliente
  for each row execute function public.ausencias_cliente_foto_validar();

commit;
