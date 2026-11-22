-- =============================================================================
-- Seed — seed_cidade_divinopolis
-- RASCUNHO. NÃO aplicado no Supabase. Só roda com o OK do João.
--
-- Cadastra Divinópolis/MG em public.cidades como INATIVA (ativa = false), no
-- mesmo padrão de Belo Horizonte em parametros.sql + seed_cidades_categorias.sql.
--
-- Observações de esquema:
--   - Não existe tabela separada de bairros: o bairro fica em texto livre opcional
--     em public.profissional_regioes(bairro).
--   - Categorias são globais (public.categorias), já cobertas por
--     seed_cidades_categorias.sql e seed_categorias_completas.sql.
--
-- Idempotente:
--   - Usa ON CONFLICT (nome, uf) DO NOTHING.
--   - Também evita duplicar caso já exista 'Divinopolis' (sem acento) em MG,
--     como ocorre no Supabase de produção em 2026-11-22 (id d54b518b-6ed2-4de5-b8e4-8ebac0e92d90).
--   - Sem UPDATE de dados: para ativar a cidade, corrigir acento ou preencher
--     coordenadas em produção, rode o comando separado apenas com OK do João:
--       -- update public.cidades
--       --    set nome = 'Divinópolis', centro_lat = -20.1386, centro_lng = -44.8839
--       --  where id = 'd54b518b-6ed2-4de5-b8e4-8ebac0e92d90';
--       -- update public.cidades set ativa = true  where nome = 'Divinópolis' and uf = 'MG';
--       -- update public.cidades set ativa = false where nome = 'Divinópolis' and uf = 'MG';
--
-- Rollback: supabase/rollback/seed_cidade_divinopolis_rollback.sql
-- =============================================================================

begin;

do $seed$
declare
  v_existente_id   uuid;
  v_existente_nome text;
  v_inserido_id    uuid;
begin
  select id, nome
    into v_existente_id, v_existente_nome
    from public.cidades
   where upper(uf) = 'MG'
     and lower(nome) in ('divinópolis', 'divinopolis')
   limit 1;

  if v_existente_id is not null then
    raise notice 'seed_cidade_divinopolis: cidade "%" (MG, id %) já existe — nada alterado.',
      v_existente_nome, v_existente_id;
    return;
  end if;

  insert into public.cidades (nome, uf, ativa, centro_lat, centro_lng)
  values ('Divinópolis', 'MG', false, -20.1386, -44.8839)
  on conflict (nome, uf) do nothing
  returning id into v_inserido_id;

  if v_inserido_id is null then
    raise notice 'seed_cidade_divinopolis: Divinópolis/MG já existia — nada alterado.';
  else
    raise notice 'seed_cidade_divinopolis: Divinópolis/MG inserida inativa (id %).', v_inserido_id;
  end if;
end
$seed$;

commit;