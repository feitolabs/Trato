-- Definição do prazo de guarda (DB-RETENCAO). RASCUNHO. NÃO aplicado em produção.
-- Rodar na publicação, SÓ COM OK DO JOÃO. Idempotente. Cria só o catálogo; valor pelo painel.
-- Sem valor publicado vale 5 (14.8 e 16.3). O prazo de acessos (acessos_conta_retencao_meses,
-- mínimo 6) está em seed_termos_e_config_100.sql.
-- Desfazer: supabase/rollback/seed_config_retencao_rollback.sql

begin;

insert into public.config_definicoes
  (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values
  ('retencao_registros_pedido_anos', 'Anos de guarda dos registros após a conclusão do Pedido (14.8 e 16.3)',
   'quantidade', 5, 30, array['global'], true)
on conflict (chave) do nothing;

commit;
