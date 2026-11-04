-- =============================================================================
-- Seed — seed_categorias_completas
-- Catálogo de categorias de serviços residenciais, além das 3 do piloto.
-- Rollback: supabase/rollback/seed_categorias_completas_rollback.sql
-- Só roda com o OK do João (escreve no banco).
--
-- Idempotente: categoria usa ON CONFLICT (slug) DO NOTHING (nada que a equipe editou é
-- sobrescrito). Pergunta só entra se ainda não existe com o mesmo texto na categoria.
-- Fora do escopo, por regra (P15): obra estrutural, gás e atividade regulada. Nenhuma
-- categoria abaixo cobre isso; todas levam a pergunta de triagem de risco.
-- As 3 categorias do piloto (limpeza-residencial, montagem-de-moveis, pintura-interna)
-- NÃO são recriadas aqui: já existem via seed_cidades_categorias.sql.
-- Garantia (garantia_retrabalho_dias) é conteúdo editorial: o João revisa os prazos.
-- =============================================================================
do $seed$
declare
  c record;
  v_id uuid;
  v_novas integer := 0;
  v_n integer;
begin
  for c in
    select * from (values
      (4,  'Eletricista',                    'eletricista',            90, 'Tomadas, interruptores, chuveiro, luminárias e reparos simples. Sem quadro de força nem rede externa.'),
      (5,  'Encanador',                      'encanador',              90, 'Torneiras, descargas, vazamentos e desentupimentos. Sem rede de gás.'),
      (6,  'Reparos gerais',                 'reparos-gerais',         30, 'Pequenos consertos da casa: portas, dobradiças, prateleiras, cortinas.'),
      (7,  'Ar-condicionado',                'ar-condicionado',        90, 'Instalação, limpeza e manutenção de split.'),
      (8,  'Instalação de eletrodomésticos', 'eletrodomesticos',       30, 'Instalação de fogão elétrico, forno, lava-louças, máquina de lavar e similares. Sem gás.'),
      (9,  'Chaveiro',                       'chaveiro',               30, 'Abertura de portas, troca de fechaduras e cópias de chave.'),
      (10, 'Jardinagem',                     'jardinagem',             30, 'Poda, corte de grama, plantio e manutenção de jardim.'),
      (11, 'Diarista',                       'diarista',               15, 'Diária de limpeza e organização da casa.'),
      (12, 'Marcenaria',                     'marcenaria',             90, 'Móveis planejados, ajustes e reparos em madeira.'),
      (13, 'Vidraceiro',                     'vidraceiro',             60, 'Vidros, espelhos, box de banheiro e janelas.'),
      (14, 'Serralheria',                    'serralheria',            90, 'Portões, grades e corrimãos. Sem estrutura de carga.'),
      (15, 'Gesso e drywall',                'gesso-drywall',          60, 'Forro, sancas, divisórias e acabamentos em gesso.'),
      (16, 'Pisos e revestimentos',          'pisos-revestimentos',    90, 'Assentamento e reparo de piso, azulejo e rodapé.'),
      (17, 'Impermeabilização',              'impermeabilizacao',     180, 'Impermeabilização de banheiros, varandas e áreas molhadas, em reparo ou acabamento.'),
      (18, 'Câmeras e segurança',            'cameras-seguranca',      90, 'Instalação de câmeras, alarmes, interfones e fechaduras eletrônicas.'),
      (19, 'Informática e redes',            'informatica-redes',      30, 'Computador, Wi-Fi, impressora e cabeamento de rede.'),
      (20, 'Mudança e frete',                'mudanca-frete',          15, 'Carretos, mudanças e transporte de móveis.'),
      (21, 'Cortinas e persianas',           'cortinas-persianas',     30, 'Instalação e ajuste de cortinas, trilhos e persianas.'),
      (22, 'Limpeza de estofados e caixa d''água', 'limpeza-especial', 30, 'Sofás, colchões, tapetes e caixa d''água.')
    ) as t(ordem, nome, slug, garantia, descricao)
  loop
    if (c.nome || ' ' || c.slug) ~* '(\mg[aá]s\M|estrutur|funda[cç][aã]o|alvenaria|laje)' then
      raise exception 'Categoria "%" fora do piloto: obra estrutural e gás não entram (P15)', c.nome;
    end if;

    v_id := null;
    insert into public.categorias (nome, slug, ordem, ativa, garantia_retrabalho_dias)
    values (c.nome, c.slug, c.ordem, true, c.garantia)
    on conflict (slug) do nothing
    returning id into v_id;
    if v_id is null then
      select id into v_id from public.categorias where slug = c.slug;
      raise notice 'Categoria % já existia: nada alterado', c.slug;
    end if;

    insert into public.categoria_perguntas (categoria_id, texto, tipo, opcoes, obrigatoria, ordem)
    select v_id, p.texto, p.tipo, p.opcoes::jsonb, p.obrigatoria, p.ordem
      from (values
        (1,  'Descreva o que precisa ser feito.',                           'texto',         null,                                              true),
        (2,  'Qual é o tipo de imóvel?',                                     'escolha_unica', '["Apartamento","Casa","Comércio pequeno"]',      true),
        (3,  'O serviço é urgente (hoje ou amanhã)?',                        'sim_nao',       null,                                              false),
        (99, 'O serviço envolve obra estrutural ou instalação de gás?',      'sim_nao',       null,                                              true)
      ) as p(ordem, texto, tipo, opcoes, obrigatoria)
     where not exists (select 1 from public.categoria_perguntas q
                        where q.categoria_id = v_id and q.texto = p.texto);
    get diagnostics v_n = row_count;
    v_novas := v_novas + v_n;
  end loop;

  raise notice 'seed_categorias_completas: % pergunta(s) nova(s)', v_novas;
end
$seed$;
