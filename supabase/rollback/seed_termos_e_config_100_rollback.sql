-- Desfaz supabase/seeds/seed_termos_e_config_100.sql. RASCUNHO. Só com OK do João.
-- Apaga só definições que nenhuma versão de configuração usa. Versão dos Termos em vigor não se
-- apaga (23.7): a linha 1.1 permanece. Idempotente.

begin;

delete from public.config_definicoes d
 where d.chave in ('nota_avaliacoes_recentes_quantidade', 'nota_avaliacoes_recentes_peso',
                   'acessos_conta_retencao_meses')
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
