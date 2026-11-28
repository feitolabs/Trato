-- ===========================================================================
-- Rollback de 20261127201500_usuarios_status_inativo.sql
-- STATUS: PREPARADO, NÃO APLICADO. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Restaura usuarios_status_check em public.usuarios ao conjunto anterior de
-- 4 estados ('ativo', 'restrito', 'bloqueado', 'anonimizado'), sem 'inativo'.
--
-- SEGURO: se ainda existir qualquer linha em public.usuarios com status = 'inativo',
-- o rollback trava com erro claro e desfaz toda a transação, sem apagar nem alterar dados.
-- ===========================================================================

begin;

do $$
declare
  v_qtd bigint := 0;
begin
  if to_regclass('public.usuarios') is null then
    raise exception 'Tabela public.usuarios não existe.';
  end if;

  select count(*) into v_qtd
    from public.usuarios
   where status = 'inativo';

  if v_qtd > 0 then
    raise exception
      'Rollback bloqueado: existem % usuário(s) com status = ''inativo'' em public.usuarios. Reative ou trate essas contas antes de desfazer a migration.',
      v_qtd;
  end if;

  alter table public.usuarios
    drop constraint if exists usuarios_status_check;

  alter table public.usuarios
    add constraint usuarios_status_check
    check (status in ('ativo', 'restrito', 'bloqueado', 'anonimizado'));
end $$;

commit;