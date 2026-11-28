-- ===========================================================================
-- 20261127223100_disputa_resultado_esperado.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, 8.4: o que o cliente espera no Relato de Problema. Coluna opcional
-- (linhas antigas ficam nulas). Gravada só na abertura (INSERT) e imutável depois, como
-- motivo e descricao. Não muda decisao, valores nem os gatilhos existentes. Pedido de
-- informação e encerramento por falta de resposta fora do escopo (falta decisão).
-- Sem grant para authenticated. Só acrescenta; sem UPDATE de dados.
--
-- Depende de 20261029030300 (public.disputas).
--
-- Rollback: supabase/rollback/20261127223100_disputa_resultado_esperado_rollback.sql
-- ===========================================================================

begin;

alter table public.disputas add column if not exists resultado_esperado text;

alter table public.disputas drop constraint if exists disputas_resultado_esperado_check;
alter table public.disputas add constraint disputas_resultado_esperado_check
  check (resultado_esperado is null
         or resultado_esperado in ('retrabalho', 'reembolso_parcial', 'reembolso_total'));

drop trigger if exists disputas_proteger_resultado_esperado on public.disputas;
create trigger disputas_proteger_resultado_esperado before update on public.disputas
  for each row execute function public.proteger_colunas('resultado_esperado');

commit;
