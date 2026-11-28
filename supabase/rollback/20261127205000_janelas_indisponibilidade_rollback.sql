-- ===========================================================================
-- Rollback de 20261127205000_janelas_indisponibilidade.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Remove a tabela `public.janelas_indisponibilidade` (índices e triggers junto) e a
-- função `public.janelas_indisponibilidade_proteger()`.
--
-- SEGURO: se houver qualquer linha registrada em `public.janelas_indisponibilidade`,
-- o rollback trava com erro claro e desfaz toda a transação, sem apagar nem alterar dados.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint := 0;
begin
  if to_regprocedure('public.orcamento_validade_vigente(timestamptz,timestamptz,timestamptz)') is not null then
    raise exception 'Rollback bloqueado: desfaça antes a 20261127220000 (validade do orçamento usa a tabela).';
  end if;
  if to_regprocedure('public.exclusividade_prazo_resposta(timestamptz,timestamptz)') is not null then
    raise exception 'Rollback bloqueado: desfaça antes a 20261127213000 (prazo de exclusividade usa a tabela).';
  end if;
  if to_regclass('public.janelas_indisponibilidade') is not null then
    lock table public.janelas_indisponibilidade in access exclusive mode;
    execute 'select count(*) from public.janelas_indisponibilidade' into v_qtd;
    if v_qtd > 0 then
      raise exception
        'Rollback bloqueado: existem % janela(s) registrada(s) em public.janelas_indisponibilidade. Exporte ou trate os registros antes de remover a tabela.',
        v_qtd;
    end if;
  end if;
end $$;

drop table if exists public.janelas_indisponibilidade;
drop function if exists public.janelas_indisponibilidade_proteger();

commit;