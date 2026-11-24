-- ===========================================================================
-- Rollback de 20261124003000_moedas_tipo_indicacao.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
--
-- Restaura `moedas_lancamentos_tipo_check` em `public.moedas_lancamentos` ao
-- conjunto anterior de 7 tipos (sem `'bonus_indicacao'`).
--
-- SEGURO: se já existir linha com `tipo = 'bonus_indicacao'`, o rollback falha
-- e desfaz tudo (o livro de moedas é imutável).
-- Para forçar mesmo assim (bloqueando apenas novos lançamentos `'bonus_indicacao'`
-- via constraint NOT VALID, sem tocar nas linhas existentes), na mesma sessão:
--   set trato.forcar_rollback_moedas_tipo_indicacao = 'sim';
-- ===========================================================================

begin;

do $$
declare
  tem_dados boolean := false;
begin
  if to_regclass('public.moedas_lancamentos') is not null then
    execute 'select exists (select 1 from public.moedas_lancamentos where tipo = ''bonus_indicacao'')'
      into tem_dados;
  end if;

  if tem_dados
     and coalesce(current_setting('trato.forcar_rollback_moedas_tipo_indicacao', true), '') <> 'sim' then
    raise exception
      'Há lançamentos com tipo = ''bonus_indicacao'' em public.moedas_lancamentos. Para forçar (NOT VALID): set trato.forcar_rollback_moedas_tipo_indicacao = ''sim'';';
  end if;

  alter table public.moedas_lancamentos
    drop constraint if exists moedas_lancamentos_tipo_check;

  if tem_dados then
    alter table public.moedas_lancamentos
      add constraint moedas_lancamentos_tipo_check
      check (tipo in (
        'bonus_avaliacao',
        'estorno',
        'uso',
        'ajuste',
        'bonus_avaliacao_profissional',
        'exclusividade_uso',
        'exclusividade_estorno'
      )) not valid;
  else
    alter table public.moedas_lancamentos
      add constraint moedas_lancamentos_tipo_check
      check (tipo in (
        'bonus_avaliacao',
        'estorno',
        'uso',
        'ajuste',
        'bonus_avaliacao_profissional',
        'exclusividade_uso',
        'exclusividade_estorno'
      ));
  end if;
end $$;

commit;
