-- =============================================================================
-- Seed 1 — seed_cidades_categorias
-- Cidade do piloto + 2 ou 3 categorias de baixo risco com perguntas guiadas.
-- Rollback: supabase/rollback/seed_cidades_categorias_rollback.sql
-- Rodar DEPOIS de parametros.sql, na mesma sessão. Só com o OK do João.
--
-- Idempotente: pode rodar duas vezes. Cidade e categoria usam ON CONFLICT DO NOTHING
-- (nada que a equipe já tenha editado é sobrescrito; se o valor do parâmetro for outro,
-- o seed avisa com NOTICE). Pergunta só entra se ainda não existe com o mesmo texto.
-- Fora do piloto, por regra: obra estrutural e gás. O seed recusa nomes assim.
-- =============================================================================
do $seed$
declare
  v_cidade_nome  text;
  v_cidade_uf    text;
  v_cidade_id    uuid;
  v_slot         integer;
  v_incluir      boolean;
  v_nome         text;
  v_slug         text;
  v_garantia     integer;
  v_categoria_id uuid;
  v_inseridas    integer;
  v_novas        integer := 0;
begin
  if to_regclass('pg_temp.seed_param') is null then
    raise exception 'Rode parametros.sql antes, na mesma sessão.';
  end if;

  -- Cidade -------------------------------------------------------------------
  select valor into v_cidade_nome from pg_temp.seed_param where chave = 'cidade_nome';
  select valor into v_cidade_uf   from pg_temp.seed_param where chave = 'cidade_uf';
  if nullif(btrim(v_cidade_nome), '') is null or nullif(btrim(v_cidade_uf), '') is null then
    raise exception 'A DEFINIR PELO JOÃO: cidade_nome e cidade_uf em parametros.sql (P6/P15)';
  end if;

  insert into public.cidades (nome, uf, ativa, centro_lat, centro_lng)
  select btrim(v_cidade_nome), upper(btrim(v_cidade_uf)),
         coalesce((select valor from pg_temp.seed_param where chave = 'cidade_ativa')::boolean, false),
         (select valor from pg_temp.seed_param where chave = 'cidade_lat')::double precision,
         (select valor from pg_temp.seed_param where chave = 'cidade_lng')::double precision
  on conflict (nome, uf) do nothing
  returning id into v_cidade_id;
  if v_cidade_id is null then
    raise notice 'Cidade % já existia: nada alterado', v_cidade_nome;
  end if;

  -- Categorias ---------------------------------------------------------------
  for v_slot in 1..3 loop
    select coalesce(valor::boolean, false) into v_incluir
      from pg_temp.seed_param where chave = format('cat%s_incluir', v_slot);
    continue when not coalesce(v_incluir, false);

    select valor into v_nome from pg_temp.seed_param where chave = format('cat%s_nome', v_slot);
    select valor into v_slug from pg_temp.seed_param where chave = format('cat%s_slug', v_slot);
    select valor::integer into v_garantia from pg_temp.seed_param where chave = format('cat%s_garantia_dias', v_slot);

    if nullif(btrim(v_nome), '') is null or nullif(btrim(v_slug), '') is null then
      raise exception 'Categoria %: nome e slug são obrigatórios em parametros.sql', v_slot;
    end if;
    if v_garantia is null then
      raise exception 'A DEFINIR PELO JOÃO: cat%_garantia_dias em parametros.sql (prazo de garantia/retrabalho da categoria)', v_slot;
    end if;
    -- Piloto: sem obra estrutural, gás nem atividade regulada (P15, Auditoria V2).
    if (v_nome || ' ' || v_slug) ~* '(\mg[aá]s\M|estrutur|funda[cç][aã]o|alvenaria|laje)' then
      raise exception 'Categoria "%" fora do piloto: obra estrutural e gás não entram (P15)', v_nome;
    end if;

    v_categoria_id := null;
    insert into public.categorias (nome, slug, ordem, ativa, garantia_retrabalho_dias)
    values (btrim(v_nome), btrim(v_slug), v_slot, true, v_garantia)
    on conflict (slug) do nothing
    returning id into v_categoria_id;
    if v_categoria_id is null then
      select id into v_categoria_id from public.categorias where slug = btrim(v_slug);
      raise notice 'Categoria % já existia: nada alterado (garantia do parâmetro: % dias)', v_slug, v_garantia;
    end if;

    -- Perguntas guiadas (conteúdo editorial; o João revisa o texto). Vaga 1 = limpeza,
    -- vaga 2 = montagem de móveis, vaga 3 = pintura interna. Vaga 0 = triagem de risco, em todas.
    insert into public.categoria_perguntas (categoria_id, texto, tipo, opcoes, obrigatoria, ordem)
    select v_categoria_id, p.texto, p.tipo, p.opcoes::jsonb, p.obrigatoria, p.ordem
      from (values
        -- vaga 1: limpeza residencial
        (1, 1, 'Qual é o tipo de imóvel?', 'escolha_unica', '["Apartamento","Casa","Outro"]', true),
        (1, 2, 'Quantos cômodos precisam de limpeza?', 'numero', null, true),
        (1, 3, 'Que tipo de limpeza você precisa?', 'escolha_unica', '["Leve (manutenção)","Pesada","Pós-obra"]', true),
        (1, 4, 'Há animais de estimação no imóvel?', 'sim_nao', null, false),
        -- vaga 2: montagem de móveis
        (2, 1, 'Quais móveis precisam ser montados?', 'texto', null, true),
        (2, 2, 'Quantos móveis são?', 'numero', null, true),
        (2, 3, 'Os móveis já estão no local e com todas as peças?', 'sim_nao', null, true),
        (2, 4, 'Algum móvel precisa ser fixado na parede?', 'sim_nao', null, false),
        -- vaga 3: pintura interna
        (3, 1, 'Qual a área aproximada a pintar, em m²?', 'numero', null, true),
        (3, 2, 'O que será pintado?', 'multipla', '["Paredes","Teto","Portas e rodapés"]', true),
        (3, 3, 'As paredes precisam de reparo (massa, rachaduras) antes?', 'sim_nao', null, true),
        (3, 4, 'O pé-direito passa de 3 metros (exige andaime)?', 'sim_nao', null, false),
        -- triagem de risco, todas as categorias
        (0, 99, 'O serviço envolve obra estrutural ou instalação de gás?', 'sim_nao', null, true)
      ) as p(vaga, ordem, texto, tipo, opcoes, obrigatoria)
     where p.vaga in (0, v_slot)
       and not exists (select 1 from public.categoria_perguntas q
                        where q.categoria_id = v_categoria_id and q.texto = p.texto);
    get diagnostics v_inseridas = row_count;
    v_novas := v_novas + v_inseridas;
  end loop;

  raise notice 'seed_cidades_categorias: % pergunta(s) nova(s)', v_novas;
end
$seed$;
