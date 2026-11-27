-- Rollback de 20261126061000_compensacao_repasses.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Preserva dados: TRAVA (sem opção de forçar) se houver dívida de compensação registrada; o
-- livro é imutável e os lançamentos dependem destas tabelas para fazer sentido.

begin;

do $$
declare
  v_tem boolean;
begin
  if to_regclass('public.compensacoes_dividas') is not null then
    lock table public.compensacoes_dividas in access exclusive mode;
    execute 'select exists (select 1 from public.compensacoes_dividas)' into v_tem;
    if v_tem then
      raise exception 'Rollback travado: há compensações registradas';
    end if;
  end if;
end;
$$;

drop function if exists public.compensacao_registrar_disputa(uuid, uuid, bigint, text, uuid);
drop function if exists public.compensacao_registrar_disputa(uuid, uuid, bigint, text);
drop function if exists public.compensacao_registrar_regresso(uuid, uuid, bigint, text, uuid, uuid);
drop function if exists public.compensacao_avisar(uuid);
drop function if exists public.compensacao_aplicar(uuid, text);
drop function if exists public.compensacao_cancelar(uuid, uuid, text);
drop function if exists public.compensacao_criar_divida(text, uuid, uuid, uuid, bigint, bigint, text, uuid, uuid, uuid);
drop function if exists public.compensacao_criar_divida(text, uuid, uuid, uuid, bigint, bigint, text, uuid, uuid);
drop table if exists public.compensacoes_aplicadas;
drop table if exists public.compensacoes_dividas;
drop function if exists public.compensacoes_dividas_validar();
drop function if exists public.compensacao_lancar(uuid, text, uuid, uuid, bigint, text, text, uuid, uuid, uuid);
drop function if exists public.compensacao_conta(text, uuid);
drop function if exists public.compensacao_compensado(uuid);
drop function if exists public.compensacao_liberado_desde(uuid, uuid, timestamptz);
drop function if exists public.compensacao_saldo(uuid, text, uuid);
drop function if exists public.compensacao_origem_revista(uuid);
drop function if exists public.compensacao_reembolso(text, bigint, bigint);
drop function if exists public.compensacao_compensavel_desde(uuid, uuid, timestamptz);
drop function if exists public.compensacao_pago_por_payout(uuid, uuid);
drop function if exists public.compensacao_eh_payout(text, uuid);

commit;
