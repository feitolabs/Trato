-- Desfaz supabase/seeds/seed_config_retencao.sql. RASCUNHO. Só com OK do João.
-- Apaga a definição só se nenhuma versão de configuração a usa. Idempotente.

begin;

delete from public.config_definicoes d
 where d.chave = 'retencao_registros_pedido_anos'
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
