-- B2 (revisão de segurança): concessão de leitura POR COLUNA nas tabelas do dinheiro.
-- Antes: `grant select` na tabela inteira expunha colunas internas ao app (authenticated).
-- Só DDL de privilégio; nenhum dado lido ou escrito. Rollback: supabase/rollback/b2_grants_por_coluna_rollback.sql
-- O backend usa service_role/postgres e não é afetado; a RLS continua filtrando as linhas.

revoke select on public.aditivos, public.lancamentos, public.repasses, public.retrabalhos,
  public.eventos_webhook from authenticated;

-- Sem decidido_por (id interno de quem decidiu).
grant select (id, contrato_id, criado_por, motivo, valor_centavos, taxa_bps_aplicada,
              taxa_trato_centavos, status, decidido_em, criado_em)
  on public.aditivos to authenticated;
-- Sem criado_por e descricao (texto interno do ledger).
grant select (id, contrato_id, pagamento_id, repasse_id, disputa_id, evento_webhook_id, tipo,
              estorna_id, chave_idempotencia, ocorrido_em, criado_em)
  on public.lancamentos to authenticated;
-- Sem provedor_transferencia_id nem congelado_por_disputa_id.
grant select (id, contrato_id, etapa_id, profissional_id, valor_bruto_centavos, taxa_centavos,
              valor_liquido_centavos, gatilho, status, liberar_em, lancamento_id,
              chave_idempotencia, criado_em, liberado_em)
  on public.repasses to authenticated;
-- Sem custo_centavos (custo interno do retrabalho).
grant select (id, garantia_id, aberto_por, descricao, status, atender_ate, atendido_em,
              outro_profissional_id, aberto_em)
  on public.retrabalhos to authenticated;
-- Sem payload (corpo bruto do provedor) nem erro.
grant select (id, provedor, evento_id, tipo, assinatura_valida, recebido_em, processado_em)
  on public.eventos_webhook to authenticated;
