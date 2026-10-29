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
- [x] **F1.7** 🔒 Conectar ao Supabase "Trato" só lendo (listar tabelas). *Pronto quando:* lista retornada e registrada. Leitura feita em 28/10/2026: projeto "Trato" (sa-east-1, Postgres 17) ativo, 0 tabelas, 0 migrations.
- [x] **F1.8** 🔒 Ligar `origin` ao GitHub "Trato" e dar push de `main` e `develop`. *Pronto quando:* branches no GitHub. *(push de `main` e `develop` feito em https://github.com/feitolabs/Trato; `origin` ligado.)*

## Fase 2 — Design

- [x] **F2.1** Extrair do PDF de telas: cores, fontes, raios, espaçamentos, ícones. *Pronto quando:* `docs/design-tokens.md` com valores e print de origem.
- [x] **F2.2** Tema Flutter em `app/lib/tema/` (cores, tipografia, espaçamentos). *Pronto quando:* nenhuma cor literal fora do tema (checado no `verificar`).
- [x] **F2.3** Componentes: botão (primário/secundário/texto), campo, cartão, chip de status, linha do tempo, barra de abas. *Pronto quando:* galeria de componentes com teste de widget.
- [x] **F2.4** Responsividade: breakpoints celular pequeno, grande e tablet. *Pronto quando:* golden tests em 3 tamanhos.
- [~] **F2.5** Tela de exemplo (Splash + Onboarding 1/3) igual ao protótipo. *Pronto quando:* comparação lado a lado aprovada pelo João.

## Fase 3 — Banco de dados (cada migration 🔒)

- [x] **F3.1** `docs/modelo-de-dados.md` com as entidades da seção 11.2. *Pronto quando:* João aprova. (aprovado pelo João em 28/10/2026; as propostas provisórias N1, N8, N10, N11 valem até ele decidir diferente)
- [x] **F3.2** 🔒 Migration: usuários, perfis, categorias, configuração. Aplicada no Supabase Trato em 29/10/2026 (versão 20261029025430) com o OK do João. 15 tabelas, RLS em todas, 0 linhas de dados.
- [x] **F3.3** 🔒 Migration: pedidos, orçamentos e itens, contratos (versão das regras congelada no aceite).  *(APLICADA no Supabase em 29/10/2026, versão 20261029170308.)*
- [x] **F3.4** 🔒 Migration: etapas, aditivos, notas de material, agendamentos e check-in/out.  *(APLICADA no Supabase em 29/10/2026, versão 20261029170728.)*
- [x] **F3.5** 🔒 Migration: pagamentos, ledger imutável, repasses e saques. *(APLICADA em 29/10/2026 com OK do João, refeita para o caminho A/D15: ledger espelho, sem saldo próprio, saque nem chave Pix. Seeds das contas do ledger dependem de P7 e do OK do João.)*
- [x] **F3.6** 🔒 Migration: disputas e evidências, garantia e retrabalho, avaliações. *(APLICADA no Supabase em 29/10/2026 com OK do João.)*
- [x] **F3.7** 🔒 Migration: chat, notificações, auditoria imutável.  *(APLICADA no Supabase em 29/10/2026, versão 20261029170820.)*
- [x] **F3.8** 🔒 RLS em todas as tabelas (endereço completo só após contratação). *Pronto quando:* testes de acesso provam que um usuário não vê dados de outro. *(APLICADA em 29/10/2026 com OK do João: F3.8a, F3.8b e F3.8c. 46 tabelas com RLS, 92 policies, 0 privilégios do anon, 4 buckets privados.)*
- [x] **F3.9** Rodar advisors do Supabase e corrigir. *Pronto quando:* sem alerta de segurança. *(advisor de segurança sem alertas após a F3.8, 29/10/2026.)*

## Fase 4 — Backend Python

- [x] **F4.1** Máquina de estados do pedido (10 estados, quem/quando/prova). *Pronto quando:* teste para cada transição válida e inválida.
- [!] **F4.2** Cálculo da taxa progressiva (base 7,5%, mínima configurável). *Bloqueado:* P2. *Pronto quando:* testes com tabela de exemplos.
- [x] **F4.3** Cálculo do custo Stripe (Pix e cartão) e margem do Trato. *Pronto quando:* testes por meio de pagamento.
- [!] **F4.4** Fluxo de pagamento: 30% adiantado, restante no fim, por etapas, aditivo. *Bloqueado:* P1, P4, P7.
- [x] **F4.5** Idempotência e webhooks Stripe assinados. *Pronto quando:* reenvio do mesmo evento não duplica lançamento.
- [x] **F4.6** Ledger de partidas dobradas e saldos derivados. *Pronto quando:* soma de débitos = créditos em todos os testes.
- [x] **F4.7** Disputa (congela, 48 h, decisão em 5 dias úteis, resultados). *Pronto quando:* testes dos 4 resultados.
- [x] **F4.8** Garantia e retrabalho (prazo por categoria, 7 dias para atender). *Pronto quando:* testes.
- [x] **F4.9** Rotinas: liberação por prazo, expiração de pedido, lembretes. *Pronto quando:* testes com relógio simulado.
- [~] **F4.10** Simulação ponta a ponta pela API (Stripe modo teste). *Pronto quando:* um serviço vai de Aberto a Concluído. *(fluxo ponta a ponta com ProvedorFake e Stripe teste simulado: ver docs/f4-10-simulacao.md; camada HTTP FastAPI com rotas de pedidos, disputa, retrabalho, ledger e webhook, repositórios em memória; falta banco real e Stripe modo teste)* *(pagamento e2e com provedor fake e Stripe `sk_test_`, tudo em teste; persistência Postgres opcional; nenhuma chamada real. Ver `docs/f4-10-simulacao.md`.)*

## Fase 5 — App do Cliente (MVP primeiro)

- [~] **F5.1** Splash, onboarding (3), escolha de perfil. *(telas prontas e ligadas; falta conferir com o João, ver F2.5)*
- [~] **F5.2** Login (e-mail/CPF/telefone, Google, Apple, biometria), recuperar senha. *(`ServicoAuth` com fake e Supabase; `main.dart` troca para o Supabase quando há chaves. Falta passar o token à API, Google/Apple/biometria e SMS. Ver `docs/login-configuracao.md`.)*
- [~] **F5.3** Cadastro em 2 passos + confirmação por SMS. *(cadastro e confirmação por `ServicoAuth`; falta Supabase real com chaves, Google/Apple e provedor de SMS, P11.)*
- [~] **F5.4** Início, categorias, buscar, perfil do profissional.
- [~] **F5.5** Novo pedido com perguntas guiadas, fotos, prazo, faixa de preço. *(tela pronta com dados de exemplo; falta o ponto de entrada no app e a API)*
- [~] **F5.6** Orçamentos recebidos, detalhe, aceite com contrato digital. *(orçamentos recebidos e detalhe ligados ao pagamento no fluxo; contrato digital e API pendentes)*
- [~] **F5.7** Pagamento (Pix/cartão, 30% adiantado) e recibo. *(tela de pagamento ligada ao aceite; falta recibo, Stripe e API)*
- [~] **F5.8** Seus pedidos, pedido em execução (linha do tempo, código de início).
- [~] **F5.9** Aditivo (aprovar/recusar) e nota de materiais. *(telas de nota e aditivo prontas nos dois lados, com fakes; falta ligar os botões nos pedidos em execução.)*
- [~] **F5.10** Conclusão (código), avaliação, garantia, retrabalho.
- [~] **F5.11** Relatar problema (disputa).
- [~] **F5.12** Chat, notificações. *(notificações e lista de mensagens ligadas, com fakes e sem protótipo; falta API.)*
- [~] **F5.13** Perfil, ajuda, LGPD (exportar e excluir conta), SOS e compartilhar atendimento. *(Perfil, privacidade/LGPD, excluir conta e ajuda ligados, com fakes e sem protótipo; falta compartilhar atendimento e exclusão real. SOS desligado, D13.)*

*Pronto quando (cada uma):* tela confere com o protótipo, teste de widget passa, funciona em Android e iOS.

## Fase 6 — App do Profissional

- [~] **F6.1** Cadastro e verificação (documento + selfie), status da análise. *(cadastro e verificação ligados ao cadastro de profissional, com fakes e sem câmera; falta API e status da análise.)*
- [~] **F6.2** Início, pedidos abertos com filtros, detalhe, recusar com motivo. *(início, detalhe e recusa com dados de exemplo; falta filtros e API)*
- [~] **F6.3** Calculadora de orçamento (taxa e líquido vindos do backend), etapas, sinal, validade, garantia.
- [~] **F6.4** Agenda, navegação, check-in (foto, local, código), check-out.
- [~] **F6.5** Enviar nota dos materiais e criar aditivo. *(telas prontas com fakes; falta o ponto de entrada no pedido em execução do profissional.)*
- [~] **F6.6** Carteira: retido, a liberar, liberado, extrato, saque Pix (mesmo CPF/CNPJ). *(extrato ligado à aba Carteira da casca (D15), sem saque; no modo `api` usa `GET /v1/extrato`.)*
- [~] **F6.7** Responder disputa, atender retrabalho, perfil público, avaliações. *(telas de responder disputa, atender retrabalho, perfil público e avaliações prontas; perfil e avaliações ligados à aba Perfil, as duas primeiras sem ponto de entrada.)*

*Pronto quando:* profissional de teste é aprovado, orça, executa, recebe e saca.

## Fase V2 — Ajustes da Auditoria e Escopo V2 (D13)

Derivada de `docs/v2-impacto.md`. Não depende de aplicar migrations.

- [x] **V2.1** Textos de tela. Trocar "5%", "dinheiro protegido", "garantia", "escrow" e afins por textos da V2 (ex.: "pagamento processado por parceiro", "suporte e análise de problemas"). Tirar o SOS da F5.13. *Pronto quando:* busca no `verificar` não acha os textos proibidos de D13 em `app/lib/`, e testes de widget passam. (P5, P14) *(textos trocados, SOS atrás de `kSosHabilitado = false` e busca de textos proibidos (D13) no `verificar`.)*
- [x] **V2.2** Backend "pago só após o provedor". O pedido e o app só viram "pago" com o webhook assinado do provedor; aceite não é pagamento. Liberação e repasse viram eventos do provedor. *Pronto quando:* testes mostram que nenhuma rota marca "pago" sem evento confirmado; reenvio não duplica. (usa F4.4, F4.5; ver P7) *(pedido só vira pago após webhook assinado, estado `aguardando_confirmacao`; garantia financiada desligada por padrão.)*
- [~] **V2.3** Simulador de margem. Margem de contribuição por serviço = receita − custo de pagamento − chargeback esperado − suporte − garantia/retrabalho − tributos − incentivo, por ticket e método (Pix, cartão à vista, parcelado). *Pronto quando:* tabela de cenários com dados reais de 2 provedores. *Bloqueada por:* P16. Destrava P2 e F4.2. *(simulador em `trato/margem/` e `docs/simulacao-margem.md`; custos do provedor são estimativas até haver proposta, P7/P16.)*
- [x] **V2.4** 🔒 Decisão do caminho de custódia: **A (ledger espelho, recomendado)** ou **B (manter até o parceiro confirmar)**. *Pronto quando:* João registra a escolha em `DECISOES.md`; F3.5, F4.4, F4.6 e F6.6 ajustadas ao caminho. *Depende de:* P7, P16 e advogado de pagamentos. *(João escolheu o caminho A em 29/10/2026, D15. F3.5 e F6.6 em ajuste; F4.4 e F4.6 seguem o ledger espelho.)*
- [ ] **V2.5** Conciliação com o parceiro (ledger espelho × relatório do provedor) e alerta de diferença. *Só no caminho A.* *Pronto quando:* teste com extrato de exemplo acusa a diferença.
- [ ] **V2.6** Painel admin web responsivo (substitui o app Ops): busca por pedido e usuário, revisão de verificação, fila de casos, conciliação, reembolso por alçada, auditoria. *Pronto quando:* caso de teste decidido no painel. *Depende de:* P9. Cobre parte da Fase 7.
- [ ] **V2.7** Desligar por configuração o que a V2 adiou: etapas pagas, adiantamento de material, `verificado_plus`, saque próprio, score e ranking. *Pronto quando:* chaves de configuração documentadas e teste de que o fluxo não oferece essas opções. (F5.x/F6.x não devem exibir.)
- [ ] **V2.8** Carga do piloto: 1 cidade e 2–3 categorias de baixo risco. 🔒 grava no banco. *Bloqueada por:* P15.

## Fase 7 — Painel administrativo (web) — depende de P9

- [ ] **F7.1** Fila de verificação. - [ ] **F7.2** Fila de disputas e decisão.
- [ ] **F7.3** Pagamentos, conciliação, repasses e saques. - [ ] **F7.4** Usuários, pedidos, suporte, categorias.
- [ ] **F7.5** Configurações com validação, aprovação dupla, histórico e reversão.
- [ ] **F7.6** Auditoria imutável. - [ ] **F7.7** Perfis de acesso por função.

*Pronto quando:* disputa de teste decidida pelo painel move o dinheiro certo.

## Fase 8 — Segurança, LGPD, conformidade

- [ ] **F8.1** Mascarar telefone, endereço só após contratar. - [ ] **F8.2** Antifraude básico.
- [ ] **F8.3** LGPD: consentimentos, exportar, excluir, retenção. - [ ] **F8.4** Regras das lojas.
- [ ] **F8.5** Advisors + varredura de segredos no repo. - [x] **F8.6** Lista para advogado e contador.

## Fase 9 — Entrega

- [ ] **F9.1** Testes ponta a ponta. - [ ] **F9.2** Testes de tela em vários tamanhos.
- [ ] **F9.3** 🔒 Build de teste Android e iOS. - [ ] **F9.4** 🔒 Piloto.
- [ ] **F9.5** `docs/COMO-RODAR.md` e `docs/ENTREGA.md`. - [ ] **F9.6** 🔒 Release `v1.0.0` (merge em `main`, tag, push).
