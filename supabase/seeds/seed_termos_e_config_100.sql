-- Dados de configuração do DB-TERMOS-100. RASCUNHO. Rodar na publicação, SÓ COM OK DO JOÃO,
-- depois das migrations 20261127061000 a 20261127061200. Idempotente.
-- Desfazer: supabase/rollback/seed_termos_e_config_100_rollback.sql
-- Não cria versão de configuração nem grava valor: valores entram pelo painel (outra pessoa aprova).

begin;

-- VERSÕES DOS TERMOS: este seed NÃO grava nenhuma. A vigência não foi confirmada pelo João.
-- ATENÇÃO, IRREVERSÍVEL: versão com data de hoje ou passada não muda nem se apaga, e passa a
-- ser gravada nos contratos confirmados. Datas só INDICADAS no repositório, a confirmar:
--   1.0 = 31/10/2026 (Anexo III dos Termos e rotas_legal.py; sem texto em backend/src/trato/legal)
--   1.1 = 22/11/2026 (backend/src/trato/legal/__init__.py; o Anexo III diz "documento não publicado")
-- Só com OK do João para cada data, rodar à parte (descomentar e conferir):
--   insert into public.termos_versoes (versao, vigente_desde)
--   values ('1.0', date '2026-10-31'), ('1.1', date '2026-11-22')
--   on conflict (versao) do nothing;
-- Enquanto não houver versão cadastrada, contratos.termos_versao fica nulo.
-- Quando a 1.2 for publicada (trocar a data pela real):
--   insert into public.termos_versoes (versao, vigente_desde) values ('1.2', date 'AAAA-MM-DD');

insert into public.config_definicoes
  (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
values
  ('nota_avaliacoes_recentes_quantidade', 'Quantas avaliações recentes pesam mais na nota (12.3)',
   'quantidade', 1, 100, array['global'], false),
  ('nota_avaliacoes_recentes_peso', 'Peso das avaliações recentes na nota; 1 = média simples (12.3)',
   'quantidade', 1, 10, array['global'], false),
  ('acessos_conta_retencao_meses', 'Meses de guarda dos registros de acesso (14.8; mínimo legal 6)',
   'quantidade', 6, 60, array['global'], true)
on conflict (chave) do nothing;

commit;
