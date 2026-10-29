-- Desfaz seed_config_taxa (supabase/seeds/seed_config_taxa.sql).
-- ATENÇÃO: só com OK do João. Só apaga a versão se ela ainda for rascunho ou aguardando aprovação.
-- Versão aprovada/vigente é imutável (trigger) e nunca se apaga: o rollback ABORTA sem mexer em nada;
-- a correção é publicar uma nova versão. As definições só saem se nenhuma versão usa a chave.
do $rb$
declare
  v_motivo constant text := 'Seed inicial de configuração (rascunho) — valores de supabase/seeds/parametros.sql';
  v_versao uuid;
  v_status text;
begin
  select id, status into v_versao, v_status from public.config_versoes where motivo = v_motivo;
  if v_versao is not null then
    if v_status not in ('rascunho', 'aguardando_aprovacao') then
      raise exception 'A versão do seed está "%": versão aprovada não se apaga. Publique uma nova versão.', v_status;
    end if;
    delete from public.config_faixas_taxa where versao_id = v_versao;
    delete from public.config_parametros where versao_id = v_versao;
    delete from public.config_versoes where id = v_versao;
  end if;

  delete from public.config_definicoes d
   where d.chave in ('taxa_bps', 'taxa_minima_centavos', 'taxa_progressiva_ativa', 'prazo_liberacao_dias',
                     'prazo_confirmacao_cliente_horas', 'janela_chargeback_dias', 'prazo_congelar_disputa_horas',
                     'prazo_resposta_disputa_horas', 'prazo_decisao_disputa_dias_uteis',
                     'prazo_retrabalho_atendimento_dias', 'garantia_retrabalho_dias_padrao',
                     'valor_minimo_servico_centavos', 'limite_orcamentos_por_pedido')
     and not exists (select 1 from public.config_parametros p where p.chave = d.chave);
end
$rb$;
