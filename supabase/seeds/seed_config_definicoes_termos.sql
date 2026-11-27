-- =============================================================================
-- Seed à parte: definições de configuração dos Termos v1.2 (DB-CONFIGS)
-- RASCUNHO. NÃO aplicado no Supabase de produção. Rodar na publicação, SÓ COM OK DO JOÃO.
-- Rodar depois de 20261125141500 (unidade 'minutos'). Antes, rodar a pré-checagem:
--   supabase/consultas/pre_checagem_config_termos.sql
-- Desfazer: supabase/rollback/seed_config_definicoes_termos_rollback.sql
--
-- Cria SÓ o catálogo (public.config_definicoes). Não cria versão, não grava valor, não aprova e
-- não publica. Os valores entram pelo painel: nova versão a partir da vigente, enviar, aprovar
-- por OUTRA pessoa e publicar (o banco exige criada_por <> aprovada_por).
-- Idempotente (on conflict do nothing): definição que já existe não é alterada.
--
-- Nomes: valem os que o backend procura. Quando o comentário da migration usava outro nome, o
-- nome antigo está ao lado. Limites: os do comentário (SAC geral: 5, porque o backend corta em 5).
--
-- FICARAM DE FORA (o backend não lê; criar daria um campo sem efeito no painel):
--   cancelamento_sem_retencao_horas             (141500)
--   medida_contestacao_prazo_dias               (224600; o backend usa 30 fixo)
--   medida_contestacao_resposta_dias_uteis      (224600; o backend usa 10 fixo)
-- ATENÇÃO: avaliacao_revisao_resposta_dias_uteis e lgpd_pedido_resposta_dias entram, mas o
-- backend ainda não lê o valor publicado (falta o método parametro_inteiro): vale o padrão fixo.
-- =============================================================================

begin;

do $seed$
declare
  r   record;
  v_n integer;
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = to_regclass('public.config_definicoes')
                    and conname = 'config_definicoes_unidade_check'
                    and pg_get_constraintdef(oid) like '%''minutos''%') then
    raise exception 'Aplique antes a migration 20261125141500 (config_definicoes com unidade minutos)';
  end if;

  create temp table seed_definicoes (
    chave text primary key, descricao text, unidade text, minimo bigint, maximo bigint, dupla boolean
  ) on commit drop;

  insert into pg_temp.seed_definicoes values
    -- 20261125141500
    ('arrependimento_dias', 'Prazo legal de arrependimento (CDC art. 49)', 'dias', 7, 30, false),
    -- antes: espera_cliente_ausente_minutos
    ('ausencia_espera_minutos', 'Tempo mínimo de espera após check-in antes de ausência', 'minutos', 20, 120, false),
    -- antes: justificativa_cliente_ausente_horas
    ('ausencia_justificativa_horas', 'Prazo para o cliente justificar ausência após aviso', 'horas', 24, 168, false),
    -- antes: retencao_cancelamento_max_bps (o backend aplica este teto na retenção por ausência)
    ('ausencia_retencao_max_bps', 'Teto de retenção por custos comprovados (3000 = 30%)', 'bps', 0, 3000, true),
    -- 20261125224500; antes: chamado_resposta_dias_uteis
    ('sac_resposta_dias_uteis', 'SAC: prazo geral de resposta (25.4)', 'dias_uteis', 1, 5, false),
    -- antes: chamado_dados_pessoais_resposta_dias
    ('sac_dados_pessoais_dias', 'SAC: resposta a pedido sobre dados pessoais (14.9)', 'dias', 1, 15, false),
    ('incidente_seguranca_cautela_horas', 'Medidas de cautela após relato de segurança (9.6)', 'horas', 1, 24, false),
    -- 20261125224700
    ('disputa_contestacao_prazo_dias_uteis', 'Prazo para contestar a decisão da disputa (8.7)', 'dias_uteis', 5, 30, false),
    ('disputa_contestacao_resposta_dias_uteis', 'Prazo de resposta da contestação (8.7)', 'dias_uteis', 1, 10, false),
    -- 20261125225600
    ('avaliacao_revisao_resposta_dias_uteis', 'Prazo de resposta ao pedido de revisão de avaliação (12.7)', 'dias_uteis', 1, 5, false),
    -- 20261125225700
    ('lgpd_pedido_resposta_dias', 'Prazo de resposta a pedido sobre dados pessoais (14.9)', 'dias', 1, 15, false);

  insert into public.config_definicoes
    (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
  select s.chave, s.descricao, s.unidade, s.minimo, s.maximo, array['global'], s.dupla
    from pg_temp.seed_definicoes s
  on conflict (chave) do nothing;
  get diagnostics v_n = row_count;
  raise notice 'seed_config_definicoes_termos: % definição(ões) criada(s)', v_n;

  for r in
    select d.chave
      from public.config_definicoes d join pg_temp.seed_definicoes s using (chave)
     where (d.unidade, d.minimo, d.maximo, d.escopos_permitidos, d.exige_dupla_aprovacao)
           is distinct from (s.unidade, s.minimo, s.maximo, array['global'], s.dupla)
  loop
    raise notice 'Definição % já existia diferente do esperado: nada alterado, conferir', r.chave;
  end loop;
end
$seed$;

commit;
