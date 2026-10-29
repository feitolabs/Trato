-- Desfaz seed_contas_ledger (supabase/seeds/seed_contas_ledger.sql).
-- ATENÇÃO: só com OK do João. O ledger é imutável: contas_ledger tem trigger que bloqueia DELETE.
-- Este rollback só vale ANTES de qualquer lançamento. Se alguma partida usa uma dessas contas,
-- ele ABORTA sem apagar nada (correção de ledger é por estorno, nunca por apagar).
-- Para apagar, desliga o trigger só dentro da transação e religa em seguida (precisa ser o dono).
do $rb$
declare
  v_codigos constant text[] := array['a_receber_do_provedor', 'receita_taxa', 'custo_provedor', 'estornos_reembolsos'];
begin
  if exists (select 1 from public.partidas p join public.contas_ledger c on c.id = p.conta_id
              where c.codigo = any (v_codigos) and c.usuario_id is null) then
    raise exception 'Há partidas nas contas do seed: o ledger é imutável, não dá para apagar. Use estorno.';
  end if;

  alter table public.contas_ledger disable trigger contas_ledger_sem_delete;
  delete from public.contas_ledger where codigo = any (v_codigos) and usuario_id is null;
  alter table public.contas_ledger enable trigger contas_ledger_sem_delete;
end
$rb$;
