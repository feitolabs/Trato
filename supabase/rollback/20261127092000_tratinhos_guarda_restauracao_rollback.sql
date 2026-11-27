-- Rollback de 20261127092000_tratinhos_guarda_restauracao.sql
-- RASCUNHO (DB-GUARDA-TRATINHOS). NÃO aplicado no Supabase de produção.
-- Preserva dados: trava se houver restauração no livro ou encerramento marcado sem falta.
-- Rodar ANTES dos rollbacks de 20261126213500 e 20261125150000.

begin;

do $$
declare
  v_tem boolean;
begin
  lock table public.medidas_conta, public.moedas_lancamentos in access exclusive mode;
  if exists (select 1 from public.moedas_lancamentos where tipo = 'restauracao') then
    raise exception 'Rollback travado: há restaurações de Tratinhos no livro';
  end if;
  if exists (select 1 from pg_attribute where attrelid = 'public.medidas_conta'::regclass
              and attname = 'sem_falta' and not attisdropped) then
    execute 'select exists (select 1 from public.medidas_conta where sem_falta)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há encerramentos marcados como sem falta';
    end if;
  end if;
end;
$$;

drop trigger if exists moedas_restauracao_validar_trg on public.moedas_lancamentos;
drop trigger if exists medidas_conta_sem_falta_trg on public.medidas_conta;
drop function if exists public.moedas_restauracao_validar();
drop function if exists public.moedas_restauracao_devida(uuid, text, timestamptz);
drop function if exists public.medidas_conta_sem_falta_proteger();

alter table public.moedas_lancamentos drop constraint if exists moedas_lancamentos_restauracao_check;
alter table public.moedas_lancamentos drop constraint if exists moedas_lancamentos_tipo_check;
alter table public.moedas_lancamentos add constraint moedas_lancamentos_tipo_check
  check (tipo in ('bonus_avaliacao', 'estorno', 'uso', 'ajuste', 'bonus_avaliacao_profissional',
                  'exclusividade_uso', 'exclusividade_estorno', 'bonus_indicacao'));

alter table public.medidas_conta drop constraint if exists medidas_conta_sem_falta_check;
alter table public.medidas_conta drop column if exists sem_falta;

commit;
