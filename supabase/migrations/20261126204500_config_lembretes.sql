-- ===========================================================================
-- 20261126204500_config_lembretes.sql
-- RASCUNHO (TERMOS-DB-PRAZOS). NÃO aplicada no Supabase de produção. Aguarda OK do João.
--
-- Duas definições de configuração (só o catálogo; nenhum valor é gravado):
--   lembrete_confirmacao_antecedencia_horas     horas antes do fim do prazo de confirmação
--   lembrete_resposta_disputa_antecedencia_horas horas antes do fim do prazo de resposta ao relato
-- 0 desliga. Sem valor publicado, o backend usa 12. Para mudar o valor: nova versão pelo
-- painel (criar, enviar, aprovar por outra pessoa e publicar). Idempotente.
--
-- Rollback: supabase/rollback/20261126204500_config_lembretes_rollback.sql
-- ===========================================================================

begin;

insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values
  ('lembrete_confirmacao_antecedencia_horas',
   'Lembrete antes do fim do prazo de confirmação do cliente (0 desliga)', 'horas', 0, 168, array['global'], false),
  ('lembrete_resposta_disputa_antecedencia_horas',
   'Lembrete antes do fim do prazo de resposta ao relato (0 desliga)', 'horas', 0, 168, array['global'], false)
on conflict (chave) do nothing;

commit;
