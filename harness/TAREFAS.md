# Tarefas

Cada tarefa cabe numa sessão e tem critério de pronto. Branch: `feature/<id>-<nome>`.
Status: `[ ]` a fazer · `[~]` em andamento · `[x]` pronta · `[!]` bloqueada (ver PENDENCIAS) · 🔒 precisa de OK do João.

## Fase 0 — Harness

- [x] **F0.1** Ler os 4 documentos. *Pronto quando:* resumo escrito em `RESUMO.md`.
- [x] **F0.2** `DECISOES.md` e `PENDENCIAS.md`. *Pronto quando:* decisões das observações registradas e dúvidas listadas.
- [x] **F0.3** `CLAUDE.md` curto. *Pronto quando:* regras + ações perigosas + gitflow.
- [x] **F0.4** Este arquivo. *Pronto quando:* fases 1–9 quebradas em tarefas.
- [x] **F0.5** `harness/verificar.ps1` e `verificar.sh`. *Pronto quando:* rodam testes, lint e busca de segredos.
- [x] **F0.6** 🔒 João aprova esta lista. (aprovado em 28/10/2026: "pode prosseguir")

## Fase 1 — Ambiente e segurança de base

- [x] **F1.1** Pastas `backend/`, `app/`, `harness/`, `docs/`. *Pronto quando:* existem com README.
- [x] **F1.2** `.env.example` (só nomes) e `.gitignore` ignorando `.env`. *Pronto quando:* `git check-ignore .env` confirma.
- [x] **F1.3** Checagem de segredos no `verificar`. *Pronto quando:* falha se achar chave no código.
- [x] **F1.4** Backend "olá mundo" (FastAPI `/saude`) lendo `.env`, com teste. *Pronto quando:* `pytest` passa.
- [~] **F1.5** App Flutter "olá mundo". Android ok (APK debug roda no emulador API 37). *Falta:* iOS (precisa de Mac). *Pronto quando:* `flutter analyze` e `flutter test` passam e roda no emulador Android e no simulador iOS.
- [ ] **F1.6** João coloca as chaves reais no `.env` (Supabase, Stripe teste). *Pronto quando:* backend sobe e lê as variáveis.
- [ ] **F1.7** 🔒 Conectar ao Supabase "Trato" só lendo (listar tabelas). *Pronto quando:* lista retornada e registrada.
- [ ] **F1.8** 🔒 Ligar `origin` ao GitHub "Trato" e dar push de `main` e `develop`. *Pronto quando:* branches no GitHub.

## Fase 2 — Design

- [x] **F2.1** Extrair do PDF de telas: cores, fontes, raios, espaçamentos, ícones. *Pronto quando:* `docs/design-tokens.md` com valores e print de origem.
- [x] **F2.2** Tema Flutter em `app/lib/tema/` (cores, tipografia, espaçamentos). *Pronto quando:* nenhuma cor literal fora do tema (checado no `verificar`).
- [x] **F2.3** Componentes: botão (primário/secundário/texto), campo, cartão, chip de status, linha do tempo, barra de abas. *Pronto quando:* galeria de componentes com teste de widget.
- [x] **F2.4** Responsividade: breakpoints celular pequeno, grande e tablet. *Pronto quando:* golden tests em 3 tamanhos.
- [~] **F2.5** Tela de exemplo (Splash + Onboarding 1/3) igual ao protótipo. *Pronto quando:* comparação lado a lado aprovada pelo João.

## Fase 3 — Banco de dados (cada migration 🔒)

- [~] **F3.1** `docs/modelo-de-dados.md` com as entidades da seção 11.2. *Pronto quando:* João aprova. *(documento escrito; falta o João aprovar)*
- [ ] **F3.2** 🔒 Migration: usuários, perfis, categorias, configuração (taxa progressiva, prazos, limites).
- [ ] **F3.3** 🔒 Migration: pedidos, orçamentos e itens, contratos (versão das regras congelada no aceite).
- [ ] **F3.4** 🔒 Migration: etapas, aditivos, notas de material, agendamentos e check-in/out.
- [ ] **F3.5** 🔒 Migration: pagamentos, ledger imutável, repasses e saques.
- [ ] **F3.6** 🔒 Migration: disputas e evidências, garantia e retrabalho, avaliações.
- [ ] **F3.7** 🔒 Migration: chat, notificações, auditoria imutável.
- [ ] **F3.8** 🔒 RLS em todas as tabelas (endereço completo só após contratação). *Pronto quando:* testes de acesso provam que um usuário não vê dados de outro.
- [ ] **F3.9** Rodar advisors do Supabase e corrigir. *Pronto quando:* sem alerta de segurança.

## Fase 4 — Backend Python

- [x] **F4.1** Máquina de estados do pedido (10 estados, quem/quando/prova). *Pronto quando:* teste para cada transição válida e inválida.
- [!] **F4.2** Cálculo da taxa progressiva (base 7,5%, mínima configurável). *Bloqueado:* P2. *Pronto quando:* testes com tabela de exemplos.
- [x] **F4.3** Cálculo do custo Stripe (Pix e cartão) e margem do Trato. *Pronto quando:* testes por meio de pagamento.
- [!] **F4.4** Fluxo de pagamento: 30% adiantado, restante no fim, por etapas, aditivo. *Bloqueado:* P1, P4, P7.
- [x] **F4.5** Idempotência e webhooks Stripe assinados. *Pronto quando:* reenvio do mesmo evento não duplica lançamento.
- [x] **F4.6** Ledger de partidas dobradas e saldos derivados. *Pronto quando:* soma de débitos = créditos em todos os testes.
- [ ] **F4.7** Disputa (congela, 48 h, decisão em 5 dias úteis, resultados). *Pronto quando:* testes dos 4 resultados.
- [ ] **F4.8** Garantia e retrabalho (prazo por categoria, 7 dias para atender). *Pronto quando:* testes.
- [ ] **F4.9** Rotinas: liberação por prazo, expiração de pedido, lembretes. *Pronto quando:* testes com relógio simulado.
- [ ] **F4.10** Simulação ponta a ponta pela API (Stripe modo teste). *Pronto quando:* um serviço vai de Aberto a Concluído.

## Fase 5 — App do Cliente (MVP primeiro)

- [ ] **F5.1** Splash, onboarding (3), escolha de perfil.
- [ ] **F5.2** Login (e-mail/CPF/telefone, Google, Apple, biometria), recuperar senha.
- [ ] **F5.3** Cadastro em 2 passos + confirmação por SMS.
- [ ] **F5.4** Início, categorias, buscar, perfil do profissional.
- [ ] **F5.5** Novo pedido com perguntas guiadas, fotos, prazo, faixa de preço.
- [ ] **F5.6** Orçamentos recebidos, detalhe, aceite com contrato digital.
- [ ] **F5.7** Pagamento (Pix/cartão, 30% adiantado) e recibo.
- [ ] **F5.8** Seus pedidos, pedido em execução (linha do tempo, código de início).
- [ ] **F5.9** Aditivo (aprovar/recusar) e nota de materiais.
- [ ] **F5.10** Conclusão (código), avaliação, garantia, retrabalho.
- [ ] **F5.11** Relatar problema (disputa).
- [ ] **F5.12** Chat, notificações.
- [ ] **F5.13** Perfil, ajuda, LGPD (exportar e excluir conta), SOS e compartilhar atendimento.

*Pronto quando (cada uma):* tela confere com o protótipo, teste de widget passa, funciona em Android e iOS.

## Fase 6 — App do Profissional

- [ ] **F6.1** Cadastro e verificação (documento + selfie), status da análise.
- [ ] **F6.2** Início, pedidos abertos com filtros, detalhe, recusar com motivo.
- [ ] **F6.3** Calculadora de orçamento (taxa e líquido vindos do backend), etapas, sinal, validade, garantia.
- [ ] **F6.4** Agenda, navegação, check-in (foto, local, código), check-out.
- [ ] **F6.5** Enviar nota dos materiais e criar aditivo.
- [ ] **F6.6** Carteira: retido, a liberar, liberado, extrato, saque Pix (mesmo CPF/CNPJ).
- [ ] **F6.7** Responder disputa, atender retrabalho, perfil público, avaliações.

*Pronto quando:* profissional de teste é aprovado, orça, executa, recebe e saca.

## Fase 7 — Painel administrativo (web) — depende de P9

- [ ] **F7.1** Fila de verificação. - [ ] **F7.2** Fila de disputas e decisão.
- [ ] **F7.3** Pagamentos, conciliação, repasses e saques. - [ ] **F7.4** Usuários, pedidos, suporte, categorias.
- [ ] **F7.5** Configurações com validação, aprovação dupla, histórico e reversão.
- [ ] **F7.6** Auditoria imutável. - [ ] **F7.7** Perfis de acesso por função.

*Pronto quando:* disputa de teste decidida pelo painel move o dinheiro certo.

## Fase 8 — Segurança, LGPD, conformidade

- [ ] **F8.1** Mascarar telefone, endereço só após contratar. - [ ] **F8.2** Antifraude básico.
- [ ] **F8.3** LGPD: consentimentos, exportar, excluir, retenção. - [ ] **F8.4** Regras das lojas.
- [ ] **F8.5** Advisors + varredura de segredos no repo. - [ ] **F8.6** Lista para advogado e contador.

## Fase 9 — Entrega

- [ ] **F9.1** Testes ponta a ponta. - [ ] **F9.2** Testes de tela em vários tamanhos.
- [ ] **F9.3** 🔒 Build de teste Android e iOS. - [ ] **F9.4** 🔒 Piloto.
- [ ] **F9.5** `docs/COMO-RODAR.md` e `docs/ENTREGA.md`. - [ ] **F9.6** 🔒 Release `v1.0.0` (merge em `main`, tag, push).
