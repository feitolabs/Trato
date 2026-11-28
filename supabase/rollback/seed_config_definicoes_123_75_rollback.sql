-- Desfaz supabase/seeds/seed_config_definicoes_123_75.sql. Só com OK do João.
-- Apaga só definições que nenhuma versão de configuração usa. Idempotente.
-- Usar somente se, antes do seed, as chaves não existiam.

begin;

delete from public.config_definicoes d
 where d.chave in ('nota_minimo_avaliacoes', 'reagendamento_antecedencia_horas')
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
