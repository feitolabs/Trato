-- Definição do prazo do Check-out sem código (Termos 5.7; DB-CHECKOUT-SEM-CODIGO-57). NÃO aplicado em produção.
-- Rodar na publicação, SÓ COM OK DO JOÃO. Idempotente (definição existente não é alterada).
-- Desfazer: supabase/rollback/seed_config_checkout_sem_codigo_rollback.sql
-- Cria SÓ o catálogo. Valor entra pelo painel (nova versão, outra pessoa aprova e publica).
-- Sem valor publicado: o backend usa 5. Mínimo 5 (nunca menos que o texto).

begin;

insert into public.config_definicoes
  (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values
  ('checkout_sem_codigo_resposta_dias_uteis',
   'Check-out sem o Código Final: prazo do Cliente para responder ao Trato (5.7; mínimo 5)',
   'dias_uteis', 5, 30, array['global'], false)
on conflict (chave) do nothing;

commit;
