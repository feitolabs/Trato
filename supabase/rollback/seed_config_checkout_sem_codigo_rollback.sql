-- Desfaz supabase/seeds/seed_config_checkout_sem_codigo.sql. Só com OK do João.
-- Apaga só a definição que nenhuma versão de configuração usa. Idempotente.
-- Usar somente se, antes do seed, a chave não existia.

begin;

delete from public.config_definicoes d
 where d.chave = 'checkout_sem_codigo_resposta_dias_uteis'
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
