-- Rollback de seed_categorias_completas.sql
-- Remove só as categorias criadas pelo seed, e só se nenhuma tiver pedido ou orçamento.
-- Se alguma estiver em uso, o delete falha (on delete restrict) e nada é perdido: desative
-- com `update public.categorias set ativa = false where slug = '...'`.
delete from public.categoria_perguntas
 where categoria_id in (select id from public.categorias where slug in (
  'eletricista','encanador','reparos-gerais','ar-condicionado','eletrodomesticos','chaveiro',
  'jardinagem','diarista','marcenaria','vidraceiro','serralheria','gesso-drywall',
  'pisos-revestimentos','impermeabilizacao','cameras-seguranca','informatica-redes',
  'mudanca-frete','cortinas-persianas','limpeza-especial'));

delete from public.categorias where slug in (
  'eletricista','encanador','reparos-gerais','ar-condicionado','eletrodomesticos','chaveiro',
  'jardinagem','diarista','marcenaria','vidraceiro','serralheria','gesso-drywall',
  'pisos-revestimentos','impermeabilizacao','cameras-seguranca','informatica-redes',
  'mudanca-frete','cortinas-persianas','limpeza-especial');
