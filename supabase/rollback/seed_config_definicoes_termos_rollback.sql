-- Desfaz supabase/seeds/seed_config_definicoes_termos.sql. RASCUNHO. Só com OK do João.
-- Apaga só definições com a mesma chave E descrição do seed e que NENHUMA versão usa
-- (rascunho incluído). As usadas ficam, com aviso: versão publicada é imutável. Idempotente.
-- Usar somente se a pré-checagem, antes do seed, mostrou todas as chaves ausentes.
-- Rodar ANTES do rollback de 20261125141500 (que volta a recusar a unidade 'minutos').

begin;

do $rb$
declare
  r record;
begin
  for r in
    with seed (chave, descricao) as (values
      ('arrependimento_dias', 'Prazo legal de arrependimento (CDC art. 49)'),
      ('ausencia_espera_minutos', 'Tempo mínimo de espera após check-in antes de ausência'),
      ('ausencia_justificativa_horas', 'Prazo para o cliente justificar ausência após aviso'),
      ('ausencia_retencao_max_bps', 'Teto de retenção por custos comprovados (3000 = 30%)'),
      ('sac_resposta_dias_uteis', 'SAC: prazo geral de resposta (25.4)'),
      ('sac_dados_pessoais_dias', 'SAC: resposta a pedido sobre dados pessoais (14.9)'),
      ('incidente_seguranca_cautela_horas', 'Medidas de cautela após relato de segurança (9.6)'),
      ('disputa_contestacao_prazo_dias_uteis', 'Prazo para contestar a decisão da disputa (8.7)'),
      ('disputa_contestacao_resposta_dias_uteis', 'Prazo de resposta da contestação (8.7)'),
      ('avaliacao_revisao_resposta_dias_uteis', 'Prazo de resposta ao pedido de revisão de avaliação (12.7)'),
      ('lgpd_pedido_resposta_dias', 'Prazo de resposta a pedido sobre dados pessoais (14.9)')
    )
    select d.chave,
           exists (select 1 from public.config_parametros p where p.chave = d.chave) as usada
      from public.config_definicoes d join seed s on s.chave = d.chave and s.descricao = d.descricao
     order by d.chave
  loop
    if r.usada then
      raise notice 'Definição % já usada numa versão de configuração: mantida', r.chave;
    else
      delete from public.config_definicoes where chave = r.chave;
    end if;
  end loop;
end
$rb$;

commit;
