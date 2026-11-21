# Matriz de Cobertura QA5 — App e Admin

Base: `develop` (`6269a7b`)
Legenda:
- `coberto (<arquivo>)`: coberto por testes automatizados
- `parcial (<arquivo>)`: coberto parcialmente
- `não coberto (<motivo>)`: sem cobertura

## App (`app/lib/telas/*_tela.dart`)

| Tela | Texto hostil / vazio | Valor limite | Toque duplo | Voltar no meio | Responsividade (320x568 / tablet 1.3x) | Erro de rede / timeout | Payload null / desconhecido / 500 itens | Sessão expirada |
|---|---|---|---|---|---|---|---|---|
| `aditivo/criar_aditivo_tela.dart` | não coberto | não coberto | não coberto | não coberto | não coberto | não coberto | não coberto | não coberto |
| `aditivo/responder_aditivo_tela.dart` | não coberto | não coberto | não coberto | não coberto | não coberto | não coberto | não coberto | não coberto |
| `agenda/agenda_tela.dart` | não coberto | — | — | — | não coberto | não coberto | não coberto | — |
| `ajuda/ajuda_tela.dart` | — | — | — | — | coberto (`qa3_cliente_test.dart`) | coberto (`qa3_cliente_test.dart`) | coberto (`qa3_cliente_test.dart`) | — |
| `auth/confirmar_celular_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `auth/confirmar_email_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `auth/criar_conta_tela.dart` | coberto (`qa5_cliente_fluxos_test.dart`) | — | — | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | — | — |
| `auth/login_tela.dart` | coberto (`qa5_cliente_fluxos_test.dart`) | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | coberto (`qa5_cliente_fluxos_test.dart`) | coberto (`qa5_cliente_fluxos_test.dart`) | — | coberto (`qa5_cliente_fluxos_test.dart`) |
| `auth/nova_senha_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `auth/recuperar_senha_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `busca/busca_profissionais_tela.dart` | não coberto | — | — | — | não coberto | não coberto | não coberto | — |
| `carteira/avaliar_cliente_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `carteira/carteira_tela.dart` | coberto (`qa5_cliente_fluxos_test.dart`) | coberto (`qa5_cliente_fluxos_test.dart`) | — | — | coberto (`qa5_cliente_fluxos_test.dart`) | coberto (`qa5_cliente_fluxos_test.dart`) | coberto (`qa5_cliente_fluxos_test.dart`) | — |
| `carteira/conta_recebimento_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `carteira/detalhe_valores_tela.dart` | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | — | coberto (`qa5_cliente_fluxos_test.dart`) | coberto (`qa5_cliente_fluxos_test.dart`) | — | — |
| `catalogo/avaliacoes_profissional_tela.dart` | — | — | — | — | não coberto | não coberto | não coberto | — |
| `catalogo/categoria_tela.dart` | — | — | — | — | não coberto | não coberto | não coberto | — |
| `catalogo/todas_categorias_tela.dart` | — | — | — | — | não coberto | não coberto | não coberto | — |
| `cliente/casca_cliente_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `cliente/inicio_tela.dart` | — | — | — | — | não coberto | não coberto | não coberto | — |
| `cliente/perfil_profissional_tela.dart` | — | — | — | — | não coberto | não coberto | não coberto | — |
| `comuns/moedas_ganhas_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `comuns/sucesso_acao_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `conclusao/avaliacao_tela.dart` | coberto (`qa4_fluxo_test.dart`) | parcial (`qa4_fluxo_test.dart`) | coberto (`qa4_fluxo_test.dart`) | — | coberto (`qa4_fluxo_test.dart`) | não coberto | — | — |
| `conclusao/conclusao_tela.dart` | coberto (`qa5_cliente_fluxos_test.dart`) | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | — | — |
| `conclusao/garantia_tela.dart` | — | — | — | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | — | — |
| `conclusao/relatar_problema_tela.dart` | coberto (`qa5_cliente_fluxos_test.dart`) | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | — | — |
| `configuracoes/configuracoes_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `conta/dados_pessoais_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `conta/enderecos_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | não coberto | — |
| `conta/favoritos_contatos_telas.dart` | — | — | — | — | não coberto | não coberto | não coberto | — |
| `conta/seguranca_conta_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `disputa_profissional/atender_retrabalho_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `disputa_profissional/responder_disputa_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `legal/texto_legal_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `lgpd/central_privacidade_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `lgpd/excluir_conta_tela.dart` | coberto (`qa4_fluxo_test.dart`, `qa5_cliente_fluxos_test.dart`) | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | — | coberto (`qa5_cliente_fluxos_test.dart`) | — | — |
| `mensagens/mensagens_tela.dart` | coberto (`qa3_cliente_test.dart`) | — | — | — | coberto (`qa3_cliente_test.dart`) | coberto (`qa3_cliente_test.dart`) | coberto (`qa3_cliente_test.dart`) | — |
| `nota_material/enviar_nota_tela.dart` | não coberto | não coberto | não coberto | — | não coberto | não coberto | — | — |
| `nota_material/ver_nota_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `notificacoes/notificacoes_tela.dart` | coberto (`qa3_cliente_test.dart`) | — | — | — | coberto (`qa3_cliente_test.dart`) | coberto (`qa3_cliente_test.dart`) | coberto (`qa3_cliente_test.dart`) | — |
| `notificacoes/preferencias_notificacoes_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `onboarding/escolha_perfil_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `onboarding/onboarding_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `orcamentos/detalhe_orcamento_tela.dart` | coberto (`qa4_fluxo_test.dart`) | — | não coberto | — | coberto (`qa4_fluxo_test.dart`) | não coberto | — | — |
| `orcamentos/orcamentos_recebidos_tela.dart` | — | — | — | — | não coberto | não coberto | não coberto | — |
| `pagamento/aguardando_pagamento_tela.dart` | — | — | — | — | não coberto | não coberto | — | — |
| `pagamento/pagamento_tela.dart` | coberto (`qa4_fluxo_test.dart`) | coberto (`qa4_fluxo_test.dart`) | coberto (`qa4_fluxo_test.dart`) | — | coberto (`qa4_fluxo_test.dart`) | parcial (`qa4_fluxo_test.dart`) | parcial (`qa4_fluxo_test.dart`) | — |
| `pedidos/chat_pedido_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `pedidos/pedido_aberto_tela.dart` | — | — | — | — | não coberto | não coberto | — | — |
| `pedidos/pedido_execucao_tela.dart` | não coberto | — | — | — | não coberto | não coberto | — | — |
| `pedidos/seus_pedidos_tela.dart` | — | — | — | — | não coberto | não coberto | não coberto | — |
| `pedido_novo/novo_pedido_tela.dart` | não coberto | — | não coberto | não coberto | não coberto | não coberto | — | — |
| `perfil_cliente/perfil_cliente_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `perfil_publico/avaliacoes_recebidas_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `perfil_publico/perfil_publico_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `profissional/calculadora_orcamento_tela.dart` | não coberto | não coberto | não coberto | — | não coberto | não coberto | — | — |
| `profissional/check_in_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `profissional/check_out_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `profissional/detalhe_orcamento_enviado_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `profissional_cadastro/cadastro_profissional_tela.dart` | não coberto | — | não coberto | — | não coberto | não coberto | — | — |
| `profissional_inicio/casca_profissional_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `profissional_inicio/detalhe_pedido_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `profissional_inicio/filtros_pedidos_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `profissional_inicio/inicio_profissional_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `profissional_inicio/pedidos_profissional_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `servicos/detalhe_servico_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `servicos/servicos_recentes_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `verificacao/verificacao_tela.dart` | — | — | — | — | não coberto | — | — | — |
| `splash_tela.dart` | — | — | — | — | não coberto | — | — | — |

## Admin (`admin/lib/telas/*.dart`)

| Tela | Texto hostil / vazio | Valor limite | Toque duplo | Responsividade | Erro de rede / timeout | Payload null / 500 itens |
|---|---|---|---|---|---|---|
| `auditoria_tela.dart` | — | — | — | não coberto | não coberto | não coberto |
| `busca_tela.dart` | não coberto | — | — | não coberto | não coberto | não coberto |
| `config_tela.dart` | não coberto | não coberto | não coberto | não coberto | não coberto | — |
| `cupons_tela.dart` | não coberto | não coberto | não coberto | não coberto | não coberto | não coberto |
| `dashboard_tela.dart` | — | — | — | não coberto | não coberto | — |
| `disputas_tela.dart` | não coberto | — | não coberto | não coberto | não coberto | não coberto |
| `equipe_tela.dart` | não coberto | — | não coberto | não coberto | não coberto | — |
| `financeiro_abas.dart` | — | — | — | não coberto | não coberto | — |
| `login_tela.dart` | não coberto | — | não coberto | não coberto | não coberto | — |
| `moedas_tela.dart` | não coberto | não coberto | não coberto | não coberto | não coberto | — |
| `notificacoes_tela.dart` | — | — | — | não coberto | não coberto | — |
| `nova_senha_tela.dart` | não coberto | — | não coberto | não coberto | não coberto | — |
| `pagamentos_tela.dart` | — | — | — | não coberto | não coberto | — |
| `relatorios_tela.dart` | — | — | — | não coberto | não coberto | — |
| `risco_tela.dart` | — | — | — | não coberto | não coberto | — |
| `shell.dart` | — | — | — | não coberto | — | — |
| `verificacao_tela.dart` | — | — | não coberto | não coberto | não coberto | — |
