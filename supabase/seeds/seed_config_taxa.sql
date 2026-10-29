-- =============================================================================
-- Seed 2 — seed_config_taxa
-- Primeira versão da configuração, em RASCUNHO. Depende de P1, P2 (e D2/D5 em espera).
-- Rollback: supabase/rollback/seed_config_taxa_rollback.sql
-- Rodar DEPOIS de parametros.sql, na mesma sessão. Só com o OK do João.
--
-- O que cria:
--   * config_definicoes: o catálogo de chaves, com minimo/maximo vindos de parametros.sql;
--   * UMA config_versoes em status 'rascunho' (motivo fixo abaixo, é a marca de idempotência);
--   * config_parametros dessa versão (taxa única em bps + mínimo em centavos, prazos e limites);
--   * config_faixas_taxa (tabela progressiva) só se o João preencher; a tabela fica DESLIGADA
--     (taxa_progressiva_ativa = 0) porque a D2 está em espera até a simulação de margem (P2).
--
-- QUEM APROVA (aprovação dupla, "exige_dupla_aprovacao = true" em taxa e prazos financeiros):
--   1. Cria o rascunho:  pessoa da equipe indicada em config_criada_por (o administrador).
--   2. Aprova:           OUTRA pessoa da equipe (sugestão: financeiro ou jurídico; o João decide).
--                        O banco garante criada_por <> aprovada_por (check em config_versoes).
--   3. Publicar:         aprovada -> vigente, feito pelo backend. Depois disso a versão é
--                        IMUTÁVEL (trigger config_versoes_proteger): erro se corrige com nova versão.
--   Este seed NUNCA aprova nem publica. O rascunho não vale para nenhum contrato.
--
-- Idempotente: definições entram com ON CONFLICT DO NOTHING; a versão só é criada se não existir
-- uma com o mesmo motivo (em qualquer status). Rodar de novo não mexe numa versão já aprovada.
-- =============================================================================
do $seed$
declare
  v_motivo    constant text := 'Seed inicial de configuração (rascunho) — valores de supabase/seeds/parametros.sql';
  v_criada_por uuid;
  v_versao    uuid;
  c           record;
  v_ativa     bigint;
  v_n         integer;
begin
  if to_regclass('pg_temp.seed_config') is null then
    raise exception 'Rode parametros.sql antes, na mesma sessão.';
  end if;

  -- Tudo precisa ter limites; o valor é exigido onde obrigatorio = true.
  for c in select * from pg_temp.seed_config order by chave loop
    if c.minimo is null or c.maximo is null then
      raise exception 'A DEFINIR PELO JOÃO: minimo e maximo de "%" em parametros.sql', c.chave;
    end if;
    if c.valor is null and c.obrigatorio then
      raise exception 'A DEFINIR PELO JOÃO: valor de "%" em parametros.sql', c.chave;
    end if;
  end loop;

  select valor::bigint into v_ativa from pg_temp.seed_config where chave = 'taxa_progressiva_ativa';
  if v_ativa is distinct from 0 then
    raise exception 'taxa_progressiva_ativa deve ser 0: a tabela progressiva (D2) está em espera até a simulação de margem (P2)';
  end if;

  select nullif(valor, '')::uuid into v_criada_por from pg_temp.seed_param where chave = 'config_criada_por';
  if v_criada_por is null then
    raise exception 'A DEFINIR PELO JOÃO: config_criada_por (uuid de quem está em public.equipe) em parametros.sql';
  end if;
  if not exists (select 1 from public.equipe where usuario_id = v_criada_por and ativo) then
    raise exception 'config_criada_por não é uma pessoa ativa da equipe (crie o primeiro administrador antes: seed_equipe_admin.sql)';
  end if;

  -- Catálogo --------------------------------------------------------------------
  -- unidade, escopos e dupla aprovação são estrutura (fixos aqui); minimo/maximo vêm dos parâmetros.
  insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao)
  select d.chave, d.descricao, d.unidade, c2.minimo, c2.maximo, d.escopos, d.dupla
    from (values
      ('taxa_bps',                          'Taxa única do Trato sobre o valor do serviço (bps; 750 = 7,5%)',  'bps',        array['global'],                       true),
      ('taxa_minima_centavos',              'Taxa mínima do Trato por serviço, em centavos (0 = sem mínimo)', 'centavos',   array['global'],                       true),
      ('taxa_progressiva_ativa',            'Liga a tabela progressiva de taxa (0 = desligada, 1 = ligada)',  'quantidade', array['global'],                       true),
      ('prazo_liberacao_dias',              'Prazo para liberar o pagamento ao profissional após o encerramento', 'dias',   array['global'],                       true),
      ('prazo_confirmacao_cliente_horas',   'Prazo para o cliente confirmar o serviço antes da confirmação automática', 'horas', array['global'],                  true),
      ('janela_chargeback_dias',            'Janela de reclamação do cliente (D3)',                            'dias',       array['global'],                       true),
      ('prazo_congelar_disputa_horas',      'Prazo para abrir disputa e congelar o repasse',                   'horas',      array['global'],                       true),
      ('prazo_resposta_disputa_horas',      'Prazo de resposta da outra parte numa disputa',                   'horas',      array['global'],                       true),
      ('prazo_decisao_disputa_dias_uteis',  'Prazo para o Trato decidir uma disputa',                          'dias_uteis', array['global'],                       true),
      ('prazo_retrabalho_atendimento_dias', 'Prazo para o profissional atender um retrabalho',                 'dias',       array['global'],                       true),
      ('garantia_retrabalho_dias_padrao',   'Garantia de retrabalho padrão (categoria pode ter a sua)',        'dias',       array['global', 'categoria'],          true),
      ('valor_minimo_servico_centavos',     'Valor mínimo de um serviço, em centavos',                         'centavos',   array['global', 'cidade'],             false),
      ('limite_orcamentos_por_pedido',      'Máximo de orçamentos recebidos por pedido',                       'quantidade', array['global'],                       false)
    ) as d(chave, descricao, unidade, escopos, dupla)
    join pg_temp.seed_config c2 on c2.chave = d.chave
  on conflict (chave) do nothing;

  for c in
    select d.chave, d.minimo, d.maximo, s.minimo as p_min, s.maximo as p_max
      from public.config_definicoes d join pg_temp.seed_config s using (chave)
     where (d.minimo, d.maximo) is distinct from (s.minimo, s.maximo)
  loop
    raise notice 'Definição % já existia com limites %..% (parâmetros pedem %..%): nada alterado',
      c.chave, c.minimo, c.maximo, c.p_min, c.p_max;
  end loop;

  -- Versão em rascunho ---------------------------------------------------------
  select id into v_versao from public.config_versoes where motivo = v_motivo;
  if v_versao is not null then
    raise notice 'Versão do seed já existe: nada alterado (parâmetros e faixas ficam como estão)';
    return;
  end if;

  insert into public.config_versoes (status, criada_por, motivo)
  values ('rascunho', v_criada_por, v_motivo)
  returning id into v_versao;

  -- O trigger config_parametros_validar confere minimo/maximo/escopo de cada linha.
  insert into public.config_parametros (versao_id, chave, valor)
  select v_versao, chave, valor from pg_temp.seed_config where valor is not null;
  get diagnostics v_n = row_count;

  insert into public.config_faixas_taxa (versao_id, de_centavos, ate_centavos, taxa_bps)
  select v_versao, de_centavos, ate_centavos, taxa_bps
    from pg_temp.seed_faixa
   where taxa_bps is not null and de_centavos is not null
   order by ordem;

  raise notice 'seed_config_taxa: versão em rascunho criada com % parâmetro(s). Falta aprovar (outra pessoa) e publicar (backend).', v_n;
end
$seed$;
