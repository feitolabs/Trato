-- ===========================================================================
-- 20261127061100_nota_peso_recente.sql
-- RASCUNHO (DB-TERMOS-100). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 12.3 (média com peso maior para as avaliações mais recentes; removidas não
-- entram) e 12.6. Depende de 20261125225600_avaliacoes_moderacao.
--
-- FÓRMULA (o texto não define; PROPOSTA, confirmar com o João):
--   as N avaliações publicadas MAIS RECENTES pesam P; as demais pesam 1.
--   N = nota_avaliacoes_recentes_quantidade (padrão 5); P = nota_avaliacoes_recentes_peso
--   (padrão 2; 1 = média simples). Só 'publicada', direção cliente -> profissional, nota decimal
--   quando houver. Não depende do relógio: a nota só muda quando as avaliações mudam.
--   Limite: com N avaliações ou menos, todas pesam igual.
--
-- public.nota_publica_profissional(id) é a fonte única. Em recalcular_perfil_profissional só o
-- trecho da nota é trocado (o filtro de contrato da 20261127004000, se houver, fica).
-- ORDEM: se a 20261125225600 for rodada de novo depois, rodar esta de novo (idempotente).
-- Não recalcula quem já existe. Depois de aplicar, ou de publicar outro N ou P, rodar com OK:
--   select public.recalcular_perfil_profissional(usuario_id) from public.perfis_profissional;
--
-- Rollback: supabase/rollback/20261127061100_nota_peso_recente_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.avaliacao_ocultacoes') is null then
    raise exception 'Aplique antes a migration 20261125225600_avaliacoes_moderacao';
  end if;
end;
$$;

create or replace function public.nota_publica_profissional(p_id uuid)
returns numeric
language sql stable security definer set search_path = ''
as $$
  with cfg as (
    select coalesce(max(p.valor) filter (where p.chave = 'nota_avaliacoes_recentes_quantidade'), 5) as n,
           coalesce(max(p.valor) filter (where p.chave = 'nota_avaliacoes_recentes_peso'), 2) as peso
      from public.config_parametros p
      join public.config_versoes v on v.id = p.versao_id and v.status = 'vigente'
     where p.escopo_tipo = 'global'
  ),
  notas as (
    select coalesce(a.nota_decimal, a.nota_geral::numeric) as nota,
           row_number() over (order by a.criada_em desc, a.id desc) as posicao
      from public.avaliacoes a
     where a.avaliado_id = p_id and a.direcao = 'cliente_para_profissional' and a.status = 'publicada'
  )
  select round(sum(x.nota * case when x.posicao <= cfg.n then cfg.peso else 1 end)
               / nullif(sum(case when x.posicao <= cfg.n then cfg.peso else 1 end), 0), 2)
    from notas x cross join cfg;
$$;
revoke all on function public.nota_publica_profissional(uuid) from public, anon, authenticated;
grant execute on function public.nota_publica_profissional(uuid) to service_role;

do $$
declare
  v_def  text := pg_get_functiondef('public.recalcular_perfil_profissional(uuid)'::regprocedure);
  v_novo text;
begin
  if position('nota_publica_profissional' in v_def) > 0 then
    return;
  end if;
  v_novo := regexp_replace(v_def, 'nota_publica = \(.*\)(\s+where p\.usuario_id = p_id)',
                           'nota_publica = public.nota_publica_profissional(p_id)\1');
  if v_novo = v_def or position('a.status = ''publicada''' in v_def) = 0 then
    raise exception 'recalcular_perfil_profissional mudou: revisar esta migration';
  end if;
  execute v_novo;
end;
$$;

commit;
