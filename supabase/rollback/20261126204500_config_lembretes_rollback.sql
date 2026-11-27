-- Rollback de 20261126204500_config_lembretes.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: definição já usada em alguma versão de configuração fica.

begin;

delete from public.config_definicoes d
 where d.chave in ('lembrete_confirmacao_antecedencia_horas', 'lembrete_resposta_disputa_antecedencia_horas')
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
