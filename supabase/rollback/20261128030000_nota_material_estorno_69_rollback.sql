-- Rollback de 20261128030000_nota_material_estorno_69.sql
-- Trava se já houver execução, dívida de material ou data de aprovação gravada (livro não se apaga).
-- Rodar ANTES dos rollbacks de 20261126195000, 20261126061000 e 20261125225400.
-- Pode rodar de novo.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.nota_material_execucoes') is not null then
    lock table public.nota_material_execucoes in access exclusive mode;
    execute 'select exists (select 1 from public.nota_material_execucoes)' into v_tem;
    if v_tem then
      raise exception 'Rollback bloqueado: há execuções de estorno de material';
    end if;
  end if;
  if to_regclass('public.compensacoes_dividas') is not null then
    lock table public.compensacoes_dividas in share row exclusive mode;
    if exists (select 1 from public.compensacoes_dividas where origem_tipo = 'nota_material_contestacao') then
      raise exception 'Rollback bloqueado: há dívidas de contestação de material';
    end if;
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'nota_material_contestacoes'
                and column_name = 'aprovada_em') then
    lock table public.nota_material_contestacoes in access exclusive mode;
    execute 'select exists (select 1 from public.nota_material_contestacoes where aprovada_em is not null)'
      into v_tem;
    if v_tem then
      raise exception 'Rollback bloqueado: há datas de aprovação gravadas';
    end if;
  end if;
end;
$$;

drop function if exists public.nota_material_executar_estorno(uuid, bigint, bigint, text, uuid);
do $$
begin
  if to_regclass('public.nota_material_contestacoes') is not null then
    drop trigger if exists nota_contestacoes_z_efeito_trg on public.nota_material_contestacoes;
    alter table public.nota_material_contestacoes drop column if exists aprovada_em;
  end if;
  if to_regclass('public.compensacoes_dividas') is not null then
    alter table public.compensacoes_dividas drop constraint if exists compensacoes_dividas_nota_material_check;
    alter table public.compensacoes_dividas drop constraint if exists compensacoes_dividas_origem_tipo_check;
    alter table public.compensacoes_dividas add constraint compensacoes_dividas_origem_tipo_check
      check (origem_tipo in ('disputa', 'disputa_contestacao', 'regresso'));
  end if;
end;
$$;
drop function if exists public.nota_material_contestacoes_efeito();
drop table if exists public.nota_material_execucoes;

commit;
