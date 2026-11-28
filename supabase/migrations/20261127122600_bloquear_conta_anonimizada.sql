-- ===========================================================================
-- 20261127122600_bloquear_conta_anonimizada.sql
-- RASCUNHO (DB-LOTE-A). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Conta anonimizada (usuarios.status = 'anonimizado') não ganha pedido nem contrato novo.
-- Só no INSERT: pedido e contrato já existentes continuam podendo mudar (cancelar, estornar,
-- disputar). Pagamentos, ordens de estorno e livro não são tocados.
-- Erro: SQLSTATE 23514, mensagem começando com 'conta_anonimizada'.
--
-- Rollback: supabase/rollback/20261127122600_bloquear_conta_anonimizada_rollback.sql
-- ===========================================================================

begin;

-- FOR SHARE: uma anonimização em andamento termina antes de o status ser lido.
create or replace function public.recusar_conta_anonimizada()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_ids uuid[] := array[new.cliente_id];
begin
  if tg_table_name = 'contratos' then
    v_ids := v_ids || (to_jsonb(new) ->> 'profissional_id')::uuid;
  end if;
  perform 1 from public.usuarios u where u.id = any (v_ids) order by u.id for share;
  if exists (select 1 from public.usuarios u where u.id = any (v_ids) and u.status = 'anonimizado') then
    raise exception 'conta_anonimizada: não é possível criar registro em % para conta anonimizada', tg_table_name
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.recusar_conta_anonimizada() from public, anon, authenticated, service_role;

drop trigger if exists pedidos_conta_anonimizada_trg on public.pedidos;
create trigger pedidos_conta_anonimizada_trg before insert on public.pedidos
  for each row execute function public.recusar_conta_anonimizada();
drop trigger if exists contratos_conta_anonimizada_trg on public.contratos;
create trigger contratos_conta_anonimizada_trg before insert on public.contratos
  for each row execute function public.recusar_conta_anonimizada();

commit;
