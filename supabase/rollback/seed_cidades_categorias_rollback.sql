-- Desfaz seed_cidades_categorias (supabase/seeds/seed_cidades_categorias.sql).
-- ATENÇÃO: só com OK do João. Roda na mesma sessão de parametros.sql (usa cidade e categorias de lá).
-- Falha de propósito (nada é apagado) se já houver pedido, profissional ou outra coisa ligada à
-- cidade ou às categorias: as chaves estrangeiras são RESTRICT. Nesse caso, desative em vez de apagar
-- (update ... set ativa = false).
do $rb$
declare
  v_slot integer;
  v_slug text;
begin
  if to_regclass('pg_temp.seed_param') is null then
    raise exception 'Rode parametros.sql antes, na mesma sessão.';
  end if;

  for v_slot in 1..3 loop
    select btrim(valor) into v_slug from pg_temp.seed_param where chave = format('cat%s_slug', v_slot);
    -- só o que o seed pode ter criado (vaga marcada como incluída)
    continue when v_slug is null
      or coalesce((select valor::boolean from pg_temp.seed_param where chave = format('cat%s_incluir', v_slot)), false) = false;
    delete from public.categoria_perguntas
     where categoria_id = (select id from public.categorias where slug = v_slug);
    delete from public.categorias where slug = v_slug;
  end loop;

  delete from public.cidades
   where (nome, uf) = ((select btrim(valor) from pg_temp.seed_param where chave = 'cidade_nome'),
                       (select upper(btrim(valor)) from pg_temp.seed_param where chave = 'cidade_uf'));
end
$rb$;
