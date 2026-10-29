-- F3.8b — Concessões e policies RLS de todas as tabelas (seção 10 do modelo).
-- Fonte: docs/modelo-de-dados.md, seção 10 (aprovado pelo João em 28/10/2026). Diferenças marcadas lá.
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Só DDL (grants e policies). Não mexe em dados.
-- Depende da F3.8a (funções do schema privado). Reversão: supabase/rollback/F3.8b_rollback.sql
--
-- Princípios:
--  * Negar por padrão. anon não recebe NENHUM privilégio em nenhuma tabela.
--  * O app só LÊ (N11): authenticated recebe só SELECT, e só nas colunas que a tela pode ver.
--    Colunas sensíveis (CPF de outros, hash de código, IP de aceite, custo do Stripe, texto original
--    da mensagem, localização EXIF das fotos etc.) ficam fora da concessão: só o backend
--    (service_role) lê. Toda escrita é do backend.
--  * Nenhuma policy usa `using (true)`. Policies só para o papel authenticated.
--  * Policy restritiva em todas as tabelas: conta bloqueada ou anonimizada não lê nada.
--  * Policies de equipe usam papéis (privado.eh_equipe). Quem lê o quê: docs/seguranca-banco.md.

-- ---------------------------------------------------------------------------
-- 1. Fecha o que a plataforma abriu por padrão nas tabelas da F3.2 (as da F3.3 a F3.7 já nasceram
--    fechadas). Observado no projeto em 29/10/2026: anon, authenticated e service_role têm
--    TRUNCATE, REFERENCES, TRIGGER e MAINTAIN nelas. A RLS não protege contra TRUNCATE.
--    O backend (service_role) recebe só o que precisa; nunca TRUNCATE.
-- ---------------------------------------------------------------------------
revoke all on table public.usuarios, public.usuarios_privados, public.equipe, public.cidades,
  public.categorias, public.categoria_perguntas, public.perfis_profissional,
  public.profissional_categorias, public.profissional_regioes, public.verificacoes,
  public.verificacao_documentos, public.config_definicoes, public.config_versoes,
  public.config_parametros, public.config_faixas_taxa
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.usuarios, public.usuarios_privados, public.equipe,
  public.cidades, public.categorias, public.categoria_perguntas, public.perfis_profissional,
  public.profissional_categorias, public.profissional_regioes, public.verificacoes,
  public.verificacao_documentos, public.config_definicoes, public.config_versoes,
  public.config_parametros, public.config_faixas_taxa
  to service_role;
-- Só estas aceitam DELETE (rascunho de configuração, vínculos do profissional, retenção de documento).
grant delete on table public.config_versoes, public.config_parametros, public.config_faixas_taxa,
  public.profissional_categorias, public.profissional_regioes, public.verificacao_documentos
  to service_role;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke execute on function public.definir_atualizado_em(), public.config_versoes_proteger(),
  public.config_parametros_validar(), public.config_faixas_proteger()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Concessões de leitura por coluna (authenticated). A RLS filtra as linhas.
-- ---------------------------------------------------------------------------
grant select (id, nome, foto_path, criado_em) on public.usuarios to authenticated;
grant select (usuario_id, cpf, telefone, telefone_confirmado_em, email_confirmado_em, data_nascimento)
  on public.usuarios_privados to authenticated;
grant select on public.equipe, public.cidades, public.categorias, public.categoria_perguntas,
  public.profissional_categorias, public.profissional_regioes, public.verificacao_documentos,
  public.config_definicoes, public.config_versoes, public.config_parametros, public.config_faixas_taxa
  to authenticated;
grant select (usuario_id, status, nivel_verificacao, bio, servicos_concluidos, nota_publica, criado_em)
  on public.perfis_profissional to authenticated;
grant select (id, profissional_id, nivel_solicitado, status, motivo_recusa, consentimento_lgpd_em,
              enviada_em, decidida_em)
  on public.verificacoes to authenticated;

grant select on public.pedidos, public.pedidos_endereco, public.pedido_respostas, public.pedido_historico,
  public.orcamentos, public.orcamento_itens, public.etapas, public.aditivos, public.notas_material,
  public.nota_material_itens, public.presencas, public.eventos_webhook, public.contas_ledger,
  public.lancamentos, public.partidas, public.repasses, public.disputa_evidencias, public.garantias, public.retrabalhos, public.avaliacoes,
  public.avaliacao_criterios, public.conversas, public.notificacoes, public.notificacao_preferencias,
  public.auditoria
  to authenticated;
-- Sem lat/lng (EXIF pode entregar a casa do cliente antes da contratação).
grant select (id, pedido_id, enviada_por, finalidade, bucket, storage_path, mime, tamanho_bytes,
              sha256, capturada_em, criado_em)
  on public.midias to authenticated;
-- Sem IP/dispositivo do aceite nem custo do Stripe (dado interno do Trato).
grant select (id, pedido_id, orcamento_id, cliente_id, profissional_id, status, escopo_texto, fora_do_escopo,
              itens, prazo_execucao_dias, garantia_dias, valor_total_centavos, taxa_bps_aplicada,
              taxa_trato_centavos, liquido_profissional_centavos, adiantamento_centavos,
              config_versao_id, regras_aplicadas, hash_documento, aceito_em, criado_em)
  on public.contratos to authenticated;
-- Sem os hashes dos códigos de 4 dígitos: com só 10 mil combinações, o hash seria quebrado na hora.
grant select (id, contrato_id, etapa_id, data, janela_inicio, janela_fim, status, remarcado_de,
              codigo_expira_em, endereco_liberado_em, criado_em, atualizado_em)
  on public.agendamentos to authenticated;
-- Sem pagador, meio, parcelas, ids do Stripe, custos nem chave de idempotência.
grant select (id, contrato_id, tipo, etapa_id, aditivo_id, valor_centavos, status, confirmado_em, criado_em)
  on public.pagamentos to authenticated;
-- Sem a avaliação interna do mediador (procedente, má-fé) nem quem decidiu/aprovou.
grant select (id, contrato_id, pedido_id, aberta_por, motivo, descricao, status, valor_congelado_centavos,
              resposta_ate, decisao_ate, decisao, valor_reembolso_centavos, justificativa,
              aberta_em, decidida_em)
  on public.disputas to authenticated;
-- Sem o texto original (N9): o app lê só o corpo_exibido.
grant select (id, conversa_id, autor_id, corpo_exibido, mascarada, midia_id, enviada_em, lida_em)
  on public.mensagens to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Policies (todas SELECT, todas para authenticated)
-- ---------------------------------------------------------------------------

-- Identidade
create policy usuarios_select on public.usuarios for select to authenticated
  using (id = (select auth.uid())
         or privado.eh_equipe_qualquer()
         or privado.profissional_aprovado(id)
         or privado.eh_contraparte(id));

-- CPF e telefone: só o dono. A equipe vê pelo backend, com motivo e registro na auditoria (diferença do modelo).
create policy usuarios_privados_select on public.usuarios_privados for select to authenticated
  using (usuario_id = (select auth.uid()));

create policy equipe_select on public.equipe for select to authenticated
  using (usuario_id = (select auth.uid()) or privado.eh_equipe('administrador'));

create policy cidades_select on public.cidades for select to authenticated
  using (ativa or privado.eh_equipe_qualquer());
create policy categorias_select on public.categorias for select to authenticated
  using (ativa or privado.eh_equipe_qualquer());
create policy categoria_perguntas_select on public.categoria_perguntas for select to authenticated
  using (ativa or privado.eh_equipe_qualquer());

create policy perfis_profissional_select on public.perfis_profissional for select to authenticated
  using (usuario_id = (select auth.uid())
         or status = 'aprovado'
         or privado.eh_equipe('cadastro', 'atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador'));
create policy profissional_categorias_select on public.profissional_categorias for select to authenticated
  using (profissional_id = (select auth.uid())
         or privado.profissional_aprovado(profissional_id)
         or privado.eh_equipe('cadastro'));
create policy profissional_regioes_select on public.profissional_regioes for select to authenticated
  using (profissional_id = (select auth.uid())
         or privado.profissional_aprovado(profissional_id)
         or privado.eh_equipe('cadastro'));

create policy verificacoes_select on public.verificacoes for select to authenticated
  using (profissional_id = (select auth.uid()) or privado.eh_equipe('cadastro'));
-- Documentos e selfie: SÓ a equipe de cadastro. Nem o dono lê de volta.
create policy verificacao_documentos_select on public.verificacao_documentos for select to authenticated
  using (privado.eh_equipe('cadastro'));

-- Configuração
create policy config_definicoes_select on public.config_definicoes for select to authenticated
  using (privado.eh_equipe('financeiro', 'juridico', 'administrador'));
create policy config_versoes_select on public.config_versoes for select to authenticated
  using (privado.eh_equipe('financeiro', 'juridico', 'administrador'));
create policy config_parametros_select on public.config_parametros for select to authenticated
  using (privado.eh_equipe('financeiro', 'juridico', 'administrador'));
create policy config_faixas_taxa_select on public.config_faixas_taxa for select to authenticated
  using (privado.eh_equipe('financeiro', 'juridico', 'administrador'));

-- Pedido e contrato
create policy pedidos_select on public.pedidos for select to authenticated
  using (cliente_id = (select auth.uid()) or privado.pode_ver_pedido(id));
create policy pedidos_endereco_select on public.pedidos_endereco for select to authenticated
  using (privado.pode_ver_endereco(pedido_id));
create policy pedido_respostas_select on public.pedido_respostas for select to authenticated
  using (privado.pode_ver_pedido(pedido_id));
create policy pedido_historico_select on public.pedido_historico for select to authenticated
  using (privado.pode_ver_pedido(pedido_id));
create policy midias_select on public.midias for select to authenticated
  using (privado.pode_ver_midia(id));

create policy orcamentos_select on public.orcamentos for select to authenticated
  using (profissional_id = (select auth.uid()) or privado.pode_ver_orcamento(id));
create policy orcamento_itens_select on public.orcamento_itens for select to authenticated
  using (privado.pode_ver_orcamento(orcamento_id));

create policy contratos_select on public.contratos for select to authenticated
  using (cliente_id = (select auth.uid())
         or profissional_id = (select auth.uid())
         or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador', 'financeiro', 'seguranca'));

-- Execução
create policy etapas_select on public.etapas for select to authenticated
  using (case when contrato_id is null
              then privado.pode_ver_orcamento(orcamento_id)
              else privado.eh_parte_do_contrato(contrato_id)
                   or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador', 'financeiro')
         end);
create policy aditivos_select on public.aditivos for select to authenticated
  using (privado.eh_parte_do_contrato(contrato_id)
         or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador', 'financeiro'));
create policy notas_material_select on public.notas_material for select to authenticated
  using (privado.eh_parte_do_contrato(contrato_id)
         or privado.eh_equipe('atendente_n2', 'lider_suporte', 'mediador', 'financeiro'));
create policy nota_material_itens_select on public.nota_material_itens for select to authenticated
  using (exists (select 1 from public.notas_material n
                  where n.id = nota_id
                    and (privado.eh_parte_do_contrato(n.contrato_id)
                         or privado.eh_equipe('atendente_n2', 'lider_suporte', 'mediador', 'financeiro'))));
create policy agendamentos_select on public.agendamentos for select to authenticated
  using (privado.eh_parte_do_contrato(contrato_id)
         or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador', 'financeiro', 'seguranca'));
create policy presencas_select on public.presencas for select to authenticated
  using (privado.eh_parte_do_agendamento(agendamento_id)
         or privado.eh_equipe('atendente_n2', 'lider_suporte', 'mediador', 'financeiro', 'seguranca'));

-- Dinheiro
create policy pagamentos_select on public.pagamentos for select to authenticated
  using (privado.eh_parte_do_contrato(contrato_id)
         or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador', 'financeiro'));
create policy eventos_webhook_select on public.eventos_webhook for select to authenticated
  using (privado.eh_equipe('financeiro'));
create policy contas_ledger_select on public.contas_ledger for select to authenticated
  using (usuario_id = (select auth.uid()) or privado.eh_equipe('financeiro'));
create policy lancamentos_select on public.lancamentos for select to authenticated
  using (privado.lancamento_envolve_minha_conta(id) or privado.eh_equipe('financeiro'));
create policy partidas_select on public.partidas for select to authenticated
  using (privado.conta_e_minha(conta_id) or privado.eh_equipe('financeiro'));
create policy repasses_select on public.repasses for select to authenticated
  using (profissional_id = (select auth.uid()) or privado.eh_equipe('financeiro', 'mediador'));

-- Disputa, garantia, avaliação
create policy disputas_select on public.disputas for select to authenticated
  using (privado.eh_parte_do_contrato(contrato_id)
         or privado.eh_equipe('atendente_n2', 'lider_suporte', 'mediador', 'financeiro'));
create policy disputa_evidencias_select on public.disputa_evidencias for select to authenticated
  using ((visivel_as_partes and privado.eh_parte_da_disputa(disputa_id))
         or autor_id = (select auth.uid())
         or privado.eh_equipe('atendente_n2', 'lider_suporte', 'mediador')
         or (visivel_as_partes and privado.eh_equipe('financeiro')));
create policy garantias_select on public.garantias for select to authenticated
  using (privado.eh_parte_do_contrato(contrato_id) or privado.eh_equipe('mediador'));
create policy retrabalhos_select on public.retrabalhos for select to authenticated
  using (privado.eh_parte_da_garantia(garantia_id) or privado.eh_equipe('mediador'));
create policy avaliacoes_select on public.avaliacoes for select to authenticated
  using (privado.pode_ver_avaliacao(id));
create policy avaliacao_criterios_select on public.avaliacao_criterios for select to authenticated
  using (privado.pode_ver_avaliacao(avaliacao_id));

-- Chat, notificações, auditoria
create policy conversas_select on public.conversas for select to authenticated
  using (cliente_id = (select auth.uid()) or profissional_id = (select auth.uid())
         or privado.mediador_com_disputa_no_pedido(pedido_id));
create policy mensagens_select on public.mensagens for select to authenticated
  using (privado.eh_participante_da_conversa(conversa_id) or privado.mediador_da_conversa(conversa_id));
create policy notificacoes_select on public.notificacoes for select to authenticated
  using (usuario_id = (select auth.uid()));
create policy notificacao_preferencias_select on public.notificacao_preferencias for select to authenticated
  using (usuario_id = (select auth.uid()));
create policy auditoria_select on public.auditoria for select to authenticated
  using (privado.eh_equipe('administrador', 'dpo', 'seguranca', 'juridico'));

-- ---------------------------------------------------------------------------
-- 4. Policy restritiva em TODAS as tabelas: conta bloqueada/anonimizada não lê nada.
--    (Restritiva = soma-se às outras com AND.)
-- ---------------------------------------------------------------------------
do $$
declare
  tabela text;
begin
  for tabela in select tablename from pg_tables where schemaname = 'public' loop
    execute format(
      'create policy conta_ativa_obrigatoria on public.%I as restrictive for select to authenticated '
      'using ((select privado.conta_ativa()))', tabela);
  end loop;
end;
$$;
