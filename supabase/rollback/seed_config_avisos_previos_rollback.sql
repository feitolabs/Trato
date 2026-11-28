-- Desfaz supabase/seeds/seed_config_avisos_previos.sql. RASCUNHO. Só com OK do João.
-- Apaga só definições que nenhuma versão de configuração usa. Idempotente.
-- Usar somente se, antes do seed, as chaves não existiam.

begin;

delete from public.config_definicoes d
 where d.chave in ('aviso_previo_encerramento_dias', 'aviso_previo_termos_dias', 'aviso_previo_tratinhos_dias', 'aviso_previo_inatividade_dias', 'tratinhos_aviso_vencimento_dias')
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
