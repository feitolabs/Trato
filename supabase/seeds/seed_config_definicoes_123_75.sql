-- Definições de configuração dos Termos 12.3 e 7.5 (DB-DEFINICOES-123-75). RASCUNHO. NÃO aplicado em produção.
-- Rodar na publicação, SÓ COM OK DO JOÃO. Idempotente (definição existente não é alterada).
-- Desfazer: supabase/rollback/seed_config_definicoes_123_75_rollback.sql
-- Cria SÓ o catálogo: não cria versão, não grava valor, não aprova e não publica. O número
-- de nota_minimo_avaliacoes é decisão do João. Valores entram pelo painel (nova versão a
-- partir da vigente, enviar, aprovar por OUTRA pessoa e publicar).
-- Sem valor publicado: nota_minimo_avaliacoes = 1 (padrão do backend).
-- ausencia_retencao_max_bps NÃO está aqui: já é definida em seed_config_definicoes_termos.sql
-- (bps, 0..3000, dupla aprovação).

begin;

insert into public.config_definicoes
  (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values
  ('nota_minimo_avaliacoes', 'Mínimo de avaliações publicadas para exibir a nota (12.3; sem valor: 1)',
   'quantidade', 1, 100, array['global'], false),
  ('reagendamento_antecedencia_horas', 'Antecedência para reagendar sem custo (7.5; máximo 24)',
   'horas', 1, 24, array['global'], false)
on conflict (chave) do nothing;

commit;
