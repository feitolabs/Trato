-- ===========================================================================
-- Rollback de 20261125141500_termos_v12_cancelamento_ausencia_exclusividade.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
--
-- Desfaz apenas o que a migration criou:
--   - Novas colunas/constraints/índice em `public.exclusividades` (preserva a tabela e dados legados)
--   - Tabelas `public.ausencias_cliente` e `public.cancelamentos_pedido`
--   - Colunas `consentimento_execucao_imediata*` em `public.contratos`
--   - Unidade `'minutos'` em `public.config_definicoes` (se não houver chave usando `'minutos'`)
--
-- SEGURO: recusa rodar se houver registros em `ausencias_cliente`/`cancelamentos_pedido`,
-- contratos com `consentimento_execucao_imediata = true`, exclusividades com `pagador = 'cliente'`
-- ou `config_definicoes` com `unidade = 'minutos'`.
-- Para forçar mesmo assim, na mesma sessão:
--   set trato.forcar_rollback_termos_v12 = 'sim';
-- ===========================================================================

begin;

do $$
declare
  tem_dados boolean := false;
  tem_minutos boolean := false;
begin
  -- TRAVA DE ORDEM (sem opção de forçar): a 20261125223000 usa as colunas desta migration.
  if to_regprocedure('public.orcamentos_exclusividade_cliente()') is not null then
    raise exception 'Rode antes o rollback da 20261125223000_exclusividade_cliente';
  end if;

  if to_regclass('public.ausencias_cliente') is not null then
    execute 'select exists (select 1 from public.ausencias_cliente)' into tem_dados;
  end if;
  if not tem_dados and to_regclass('public.cancelamentos_pedido') is not null then
    execute 'select exists (select 1 from public.cancelamentos_pedido)' into tem_dados;
  end if;
  if not tem_dados and exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'contratos' and column_name = 'consentimento_execucao_imediata'
  ) then
    execute 'select exists (select 1 from public.contratos where consentimento_execucao_imediata = true or consentimento_execucao_imediata_em is not null)' into tem_dados;
  end if;
  if not tem_dados and exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'exclusividades' and column_name = 'pagador'
  ) then
    execute $q$
      select exists (
        select 1 from public.exclusividades
         where pagador = 'cliente'
            or status = 'expirada_sem_contratacao'
            or orcamento_id is not null
            or motivo_encerramento is not null
            or estornada = true
      )
    $q$ into tem_dados;
  end if;
  if to_regclass('public.config_definicoes') is not null then
    execute 'select exists (select 1 from public.config_definicoes where unidade = ''minutos'')' into tem_minutos;
  end if;

  if (tem_dados or tem_minutos)
     and coalesce(current_setting('trato.forcar_rollback_termos_v12', true), '') <> 'sim' then
    raise exception
      'Há dados novos dos Termos v1.2 gravados no banco. Para forçar: set trato.forcar_rollback_termos_v12 = ''sim'';';
  end if;

  -- 5) exclusividades (preserva tabela e dados legados do profissional)
  drop index if exists public.ix_exclusividades_cliente_pagador;
  alter table public.exclusividades
    drop constraint if exists exclusividades_estorno_timestamp_check,
    drop constraint if exists exclusividades_estorno_cliente_check,
    drop constraint if exists exclusividades_motivo_encerramento_check,
    drop constraint if exists exclusividades_pagador_check;

  alter table public.exclusividades
    drop constraint if exists exclusividades_status_check;
  if tem_dados then
    alter table public.exclusividades
      add constraint exclusividades_status_check
      check (status in ('aguardando_cliente', 'ativa', 'recusada', 'expirada_sem_resposta',
                        'concluida', 'expirada_sem_atendimento', 'cancelada')) not valid;
  else
    alter table public.exclusividades
      add constraint exclusividades_status_check
      check (status in ('aguardando_cliente', 'ativa', 'recusada', 'expirada_sem_resposta',
                        'concluida', 'expirada_sem_atendimento', 'cancelada'));
  end if;

  alter table public.exclusividades
    drop column if exists estorno_lancamento_id,
    drop column if exists estornada_em,
    drop column if exists estornada,
    drop column if exists motivo_encerramento,
    drop column if exists orcamento_id,
    drop column if exists pagador;

  -- 4) ausencias_cliente
  drop index if exists public.ix_ausencias_cliente_pedido;
  drop index if exists public.ix_ausencias_cliente_status_prazo;
  drop table if exists public.ausencias_cliente;
  drop function if exists public.ausencias_cliente_validar();

  -- 3) cancelamentos_pedido
  drop index if exists public.ix_cancelamentos_pedido_status;
  drop index if exists public.ix_cancelamentos_pedido_contrato;
  drop index if exists public.ix_cancelamentos_pedido_pedido;
  drop table if exists public.cancelamentos_pedido;
  drop function if exists public.cancelamentos_pedido_validar();

  -- 2) contratos
  drop trigger if exists contratos_consentimento_unico_trg on public.contratos;
  drop function if exists public.contratos_consentimento_unico();
  alter table public.contratos
    drop constraint if exists contratos_consentimento_execucao_check;
  alter table public.contratos
    drop column if exists consentimento_execucao_imediata_em,
    drop column if exists consentimento_execucao_imediata;

  -- 1) config_definicoes
  alter table public.config_definicoes
    drop constraint if exists config_definicoes_unidade_check;
  if tem_minutos then
    alter table public.config_definicoes
      add constraint config_definicoes_unidade_check
      check (unidade in ('centavos', 'bps', 'horas', 'dias', 'dias_uteis', 'quantidade')) not valid;
  else
    alter table public.config_definicoes
      add constraint config_definicoes_unidade_check
      check (unidade in ('centavos', 'bps', 'horas', 'dias', 'dias_uteis', 'quantidade'));
  end if;
end $$;

commit;
