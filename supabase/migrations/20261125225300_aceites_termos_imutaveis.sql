-- ===========================================================================
-- 20261125225300_aceites_termos_imutaveis.sql
-- RASCUNHO (TERMOS-DB5, 1/5). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2, 1.4: versão aceita, data, hora e IP do aceite.
--
-- Não cria tabela: o aceite já é gravado em public.lgpd_consentimentos
--   (usuario_id, finalidade = documento, aceito, versao_texto = versão,
--    registrado_em = data e hora, ip). O backend usa finalidade 'termos_de_uso'.
-- Esta migration só torna o registro imutável: bloqueia update, delete e truncate, e
-- deixa o service_role com select e insert. Nenhum dado é alterado.
--
-- CONFERÊNCIA (somente leitura). Esperado: 2 gatilhos; upd = f, del = f, ins = t.
-- select tgname from pg_trigger where tgrelid = 'public.lgpd_consentimentos'::regclass and not tgisinternal order by 1;
-- select has_table_privilege('service_role', 'public.lgpd_consentimentos', 'insert') as ins,
--        has_table_privilege('service_role', 'public.lgpd_consentimentos', 'update') as upd,
--        has_table_privilege('service_role', 'public.lgpd_consentimentos', 'delete') as del;
--
-- Rollback: supabase/rollback/20261125225300_aceites_termos_imutaveis_rollback.sql
-- ===========================================================================

begin;

drop trigger if exists lgpd_consentimentos_imutavel on public.lgpd_consentimentos;
create trigger lgpd_consentimentos_imutavel before update or delete on public.lgpd_consentimentos
  for each row execute function public.bloquear_alteracao();
drop trigger if exists lgpd_consentimentos_sem_truncate on public.lgpd_consentimentos;
create trigger lgpd_consentimentos_sem_truncate before truncate on public.lgpd_consentimentos
  for each statement execute function public.bloquear_alteracao();

alter table public.lgpd_consentimentos enable row level security;
revoke all on table public.lgpd_consentimentos from public, anon, authenticated, service_role;
grant select, insert on table public.lgpd_consentimentos to service_role;

commit;
