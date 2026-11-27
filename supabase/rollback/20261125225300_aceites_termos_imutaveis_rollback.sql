-- Rollback de 20261125225300_aceites_termos_imutaveis.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Remove só os 2 gatilhos. Nenhum dado é apagado. Os privilégios ficam em select e insert
-- (os que a 20261101180000 concedeu); não devolve update nem delete a ninguém.

begin;

drop trigger if exists lgpd_consentimentos_imutavel on public.lgpd_consentimentos;
drop trigger if exists lgpd_consentimentos_sem_truncate on public.lgpd_consentimentos;

commit;
