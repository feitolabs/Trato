-- Desfaz 20261108120000_financeiro_contestacoes_fechamento.sql.
-- ATENÇÃO: apaga as contestações e os fechamentos gravados. Só rode com o OK do João e depois de
-- exportar as duas tabelas (o histórico dos webhooks continua em eventos_webhook).

begin;

drop trigger if exists lancamentos_mes_fechado on public.lancamentos;
drop function if exists public.recusar_lancamento_em_mes_fechado();

drop table if exists public.fechamentos_mensais;
drop table if exists public.contestacoes;

-- A definição só sai se nenhuma versão de configuração a usa.
delete from public.config_definicoes d
 where d.chave = 'alerta_pagamento_parado_minutos'
   and not exists (select 1 from public.config_parametros p where p.chave = d.chave);

commit;
