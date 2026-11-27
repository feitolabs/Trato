-- Rollback de 20261127061100_nota_peso_recente.sql
-- RASCUNHO (DB-TERMOS-100). NÃO aplicado no Supabase de produção.
-- Volta a média simples da 20261125225600 e mantém o resto da função. Não apaga dados.
-- As notas já gravadas só voltam no próximo recálculo (rodar com OK):
--   select public.recalcular_perfil_profissional(usuario_id) from public.perfis_profissional;
-- Rodar ANTES do rollback de 20261125225600.

begin;

do $$
declare
  v_def text := pg_get_functiondef('public.recalcular_perfil_profissional(uuid)'::regprocedure);
begin
  if position('public.nota_publica_profissional(p_id)' in v_def) > 0 then
    execute replace(v_def, 'public.nota_publica_profissional(p_id)',
      '(select round(avg(coalesce(a.nota_decimal, a.nota_geral::numeric)), 2) from public.avaliacoes a '
      || 'where a.avaliado_id = p_id and a.direcao = ''cliente_para_profissional'' '
      || 'and a.status = ''publicada'')');
  end if;
end;
$$;
drop function if exists public.nota_publica_profissional(uuid);

commit;
