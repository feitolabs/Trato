-- Definições de configuração dos avisos prévios (DB-LOTE-A). RASCUNHO. NÃO aplicado em produção.
-- Rodar na publicação, SÓ COM OK DO JOÃO. Idempotente (definição existente não é alterada).
-- Desfazer: supabase/rollback/seed_config_avisos_previos_rollback.sql
-- Cria SÓ o catálogo. Valores entram pelo painel (nova versão, outra pessoa aprova e publica).
-- Sem valor publicado: avisos prévios = 30 (fixo no backend); vencimento dos Tratinhos = 7 (I.5).
-- tratinhos_aviso_vencimento_dias: mínimo 7 (I.5 pede aviso com [7] dias); o backend também não aceita menos.

begin;

insert into public.config_definicoes
  (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values
  ('aviso_previo_encerramento_dias', 'Aviso antes do encerramento da conta sem falta (20.8; mínimo 30)',
   'dias', 30, 180, array['global'], false),
  ('aviso_previo_termos_dias', 'Aviso antes de mudança relevante dos Termos (23.2; mínimo 30)',
   'dias', 30, 180, array['global'], false),
  ('aviso_previo_tratinhos_dias', 'Aviso antes de mudar ou encerrar os Tratinhos (13.11 e I.12; mínimo 30)',
   'dias', 30, 180, array['global'], false),
  ('aviso_previo_inatividade_dias', 'Aviso antes de inativar conta sem uso (4.9; mínimo 30)',
   'dias', 30, 180, array['global'], false),
  ('tratinhos_aviso_vencimento_dias', 'Aviso antes do vencimento dos Tratinhos (I.5; mínimo e padrão 7)',
   'dias', 7, 30, array['global'], false)
on conflict (chave) do nothing;

commit;
