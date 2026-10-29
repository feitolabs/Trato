-- =============================================================================
-- Seed 3 — seed_contas_ledger
-- Contas de SISTEMA do ledger no caminho A (D15): o ledger só ESPELHA o que o provedor de
-- pagamento liquida. O Trato não guarda saldo próprio nem faz saque.
-- Rollback: supabase/rollback/seed_contas_ledger_rollback.sql
-- Rodar DEPOIS de parametros.sql, na mesma sessão. Só com o OK do João.
--
-- >>> DEPENDE DO P7 (parceiro de pagamento e custódia). <<<
-- Os códigos abaixo valem para o caminho A, mas só devem entrar no banco real depois que o João
-- responder o P7. Por isso o seed exige ledger_p7_confirmado = 'true' em parametros.sql.
-- Nenhum nome é específico de um provedor (nada de "stripe" no código da conta).
--
--   a_receber_do_provedor  ativo    o que o provedor ainda vai repassar ao Trato / aos profissionais
--   receita_taxa           receita  a taxa do Trato sobre cada serviço
--   custo_provedor         despesa  o custo de processamento cobrado pelo provedor
--   estornos_reembolsos    despesa  reembolsos e estornos que o Trato absorve (uso a confirmar no P7)
--
-- NÃO criados aqui (nascem sob demanda, pelo backend, no primeiro uso):
--   a_pagar_profissional   passivo  UMA POR PROFISSIONAL (usuario_id preenchido): líquido a pagar a ele.
--   Contas por usuário nunca entram em seed.
--
-- Idempotente: cada conta de sistema só entra se ainda não existe (codigo + usuario_id nulo).
-- =============================================================================
do $seed$
declare
  v_inseridas integer;
begin
  if to_regclass('pg_temp.seed_param') is null then
    raise exception 'Rode parametros.sql antes, na mesma sessão.';
  end if;
  if coalesce((select valor from pg_temp.seed_param where chave = 'ledger_p7_confirmado'), 'false') <> 'true' then
    raise exception 'A DEFINIR PELO JOÃO: responder o P7 (parceiro e custódia, caminho A) e marcar ledger_p7_confirmado = ''true'' em parametros.sql';
  end if;

  insert into public.contas_ledger (codigo, natureza, usuario_id)
  select c.codigo, c.natureza, null
    from (values
      ('a_receber_do_provedor', 'ativo'),
      ('receita_taxa',          'receita'),
      ('custo_provedor',        'despesa'),
      ('estornos_reembolsos',   'despesa')
    ) as c(codigo, natureza)
   where not exists (select 1 from public.contas_ledger x
                      where x.codigo = c.codigo and x.usuario_id is null);
  get diagnostics v_inseridas = row_count;

  raise notice 'seed_contas_ledger: % conta(s) de sistema nova(s)', v_inseridas;
end
$seed$;
