-- Desfaz 20261120100000_moedas_orcamento.sql.
-- ATENÇÃO: apaga o controle de uso do orçamento (mês e dia), as moedas pendentes de liberação e os 5 limites da config.
-- Só rode com o OK do João.

begin;
drop function if exists public.moedas_devolver_orcamento(date, date, integer);
drop function if exists public.moedas_reservar_orcamento(date, date, integer, integer, integer);
-- assinaturas antigas (caso uma versão anterior tenha sido aplicada):
drop function if exists public.moedas_devolver_orcamento(date, integer);
drop function if exists public.moedas_reservar_orcamento(date, integer, integer);
drop index if exists public.moedas_lancamentos_usuario_tipo_idx;
drop table if exists public.moedas_pendentes;
drop table if exists public.moedas_orcamento_diario;
drop table if exists public.moedas_orcamento_mensal;
alter table public.moedas_config
  drop column if exists dias_liberacao_bonus,
  drop column if exists teto_diario_desconto_centavos,
  drop column if exists teto_desconto_cliente_mes_centavos,
  drop column if exists aviso_percentual,
  drop column if exists orcamento_mensal_desconto_centavos;
commit;
