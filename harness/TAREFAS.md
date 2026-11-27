# Tarefas

Cada tarefa cabe numa sessão e tem critério de pronto. Branch: `feature/<id>-<nome>`.
Status: `[ ]` a fazer · `[~]` em andamento · `[x]` pronta · `[!]` bloqueada (ver PENDENCIAS) · 🔒 precisa de OK do João.
*Atualizado em 20/11/2026 com base em `harness/PROGRESSO.md`, `git log` e conferência no disco.*

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
- [~] **F1.5** App Flutter "olá mundo". Android ok (APKs debug e release até `v0.1.30` rodando no emulador). *Falta:* iOS (precisa de Mac). *Pronto quando:* `flutter analyze` e `flutter test` passam e roda no emulador Android e no simulador iOS.
- [x] **F1.6** João coloca as chaves reais no `.env` (Supabase, Stripe teste). *Pronto quando:* backend sobe e lê as variáveis. *(`.env` local configurado; backend validado contra Supabase real, Stripe Sandbox 11/11 e publicado no Fly.io `trato.fly.dev`.)*
- [x] **F1.7** 🔒 Conectar ao Supabase "Trato" só lendo (listar tabelas). *Pronto quando:* lista retornada e registrada. Leitura feita em 28/10/2026: projeto "Trato" (sa-east-1, Postgres 17) ativo, 0 tabelas, 0 migrations.
- [x] **F1.8** 🔒 Ligar `origin` ao GitHub "Trato" e dar push de `main` e `develop`. *Pronto quando:* branches no GitHub. *(push de `main` e `develop` feito em https://github.com/feitolabs/Trato; `origin` ligado.)*

## Fase 2 — Design

- [x] **F2.1** Extrair do PDF de telas: cores, fontes, raios, espaçamentos, ícones. *Pronto quando:* `docs/design-tokens.md` com valores e print de origem.
- [x] **F2.2** Tema Flutter em `app/lib/tema/` (cores, tipografia, espaçamentos). *Pronto quando:* nenhuma cor literal fora do tema (checado no `verificar`).
- [x] **F2.3** Componentes: botão (primário/secundário/texto), campo, cartão, chip de status, linha do tempo, barra de abas. *Pronto quando:* galeria de componentes com teste de widget.
- [x] **F2.4** Responsividade: breakpoints celular pequeno, grande e tablet. *Pronto quando:* golden tests em 3 tamanhos.
- [~] **F2.5** Tela de exemplo (Splash + Onboarding 1/3) igual ao protótipo. *Pronto quando:* comparação lado a lado aprovada pelo João. *(fidelidade visual conferida em 30/10 e entrada leve com "Pular" em `e0886b1`; falta confirmação explícita lado a lado do João — ver Dúvidas.)*

## Fase 3 — Banco de dados (cada migration 🔒)

- [x] **F3.1** `docs/modelo-de-dados.md` com as entidades da seção 11.2. *Pronto quando:* João aprova. (aprovado pelo João em 28/10/2026; as propostas provisórias N1, N8, N10, N11 valem até ele decidir diferente)
- [x] **F3.2** 🔒 Migration: usuários, perfis, categorias, configuração. Aplicada no Supabase Trato em 29/10/2026 (versão 20261029025430) com o OK do João. 15 tabelas, RLS em todas, 0 linhas de dados.
- [x] **F3.3** 🔒 Migration: pedidos, orçamentos e itens, contratos (versão das regras congelada no aceite). *(APLICADA no Supabase em 29/10/2026, versão 20261029170308.)*
- [x] **F3.4** 🔒 Migration: etapas, aditivos, notas de material, agendamentos e check-in/out. *(APLICADA no Supabase em 29/10/2026, versão 20261029170728.)*
- [x] **F3.5** 🔒 Migration: pagamentos, ledger imutável, repasses e saques. *(APLICADA em 29/10/2026 com OK do João, refeita para o caminho A/D15: ledger espelho, sem saldo próprio, saque nem chave Pix. Seeds das contas do ledger aplicados em 31/10/2026.)*
- [x] **F3.6** 🔒 Migration: disputas e evidências, garantia e retrabalho, avaliações. *(APLICADA no Supabase em 29/10/2026 com OK do João.)*
- [x] **F3.7** 🔒 Migration: chat, notificações, auditoria imutável. *(APLICADA no Supabase em 29/10/2026, versão 20261029170820.)*
- [x] **F3.8** 🔒 RLS em todas as tabelas (endereço completo só após contratação). *Pronto quando:* testes de acesso provam que um usuário não vê dados de outro. *(APLICADA em 29/10/2026 com OK do João: F3.8a, F3.8b e F3.8c. 46 tabelas com RLS, 92 policies, 0 privilégios do anon, 4 buckets privados.)*
- [x] **F3.9** Rodar advisors do Supabase e corrigir. *Pronto quando:* sem alerta de segurança. *(advisor de segurança sem alertas após a F3.8, 29/10/2026.)*

## Fase 4 — Backend Python

- [x] **F4.1** Máquina de estados do pedido (10 estados, quem/quando/prova). *Pronto quando:* teste para cada transição válida e inválida. *(ampliada para incluir `aguardando_confirmacao` e `reservado` na exclusividade 48h.)*
- [x] **F4.2** Cálculo da taxa progressiva (base 7,5%, mínima configurável). *Pronto quando:* testes com tabela de exemplos. *(encerrada/substituída pela decisão do João em 18/11/2026: app 100% gratuito, commit `5906fa7`, taxa removida do código; resta apenas aplicar migration destrutiva de limpeza `20261118150000_remove_faixas_taxa.sql` quando o João autorizar.)*
- [x] **F4.3** Cálculo do custo Stripe (Pix e cartão) e margem do Trato. *Pronto quando:* testes por meio de pagamento.
- [x] **F4.4** Fluxo de pagamento: 30% adiantado, restante no fim, por etapas, aditivo. *(ajustado por D15/D16: Stripe caminho A, pagamento integral após aceite sem os 30% adiantados nem etapas pagas na V2, mais aditivo, cupom e Tratinhos; implementado em `backend/src/trato/pagamentos/` e `persistencia/pagamentos.py`, validado no Stripe Sandbox em 04/11 e 16/11.)*
- [x] **F4.5** Idempotência e webhooks Stripe assinados. *Pronto quando:* reenvio do mesmo evento não duplica lançamento.
- [x] **F4.6** Ledger de partidas dobradas e saldos derivados. *Pronto quando:* soma de débitos = créditos em todos os testes. *(idempotência reforçada na B11 `b5aa270`.)*
- [x] **F4.7** Disputa (congela, 48 h, decisão em 5 dias úteis, resultados). *Pronto quando:* testes dos 4 resultados.
- [x] **F4.8** Garantia e retrabalho (prazo por categoria, 7 dias para atender). *Pronto quando:* testes.
- [x] **F4.9** Rotinas: liberação por prazo, expiração de pedido, lembretes. *Pronto quando:* testes com relógio simulado. *(agendador embutido pronto e testado; mantido desligado no Fly `TRATO_AGENDADOR_EMBUTIDO=false` por decisão do João.)*
- [x] **F4.10** Simulação ponta a ponta pela API (Stripe modo teste). *Pronto quando:* um serviço vai de Aberto a Concluído. *(validado no Postgres local, no emulador em 05/11 e ao vivo 7/7 contra `https://trato.fly.dev` + Supabase real + Stripe Sandbox em 16/11/2026.)*

## Fase 5 — App do Cliente (MVP primeiro)

- [~] **F5.1** Splash, onboarding (3), escolha de perfil. *(telas prontas, ligadas e com entrada leve "Pular" em `e0886b1`; falta aprovação lado a lado F2.5 e validação em iOS.)*
- [~] **F5.2** Login (e-mail/CPF/telefone, Google, Apple, biometria), recuperar senha. *(e-mail/senha via Supabase Auth real e `SessaoTrato` funcionando em produção; falta ligar Google/Apple no Supabase com client IDs, biometria e iOS.)*
- [~] **F5.3** Cadastro em 2 passos + confirmação por SMS. *(cadastro real com confirmação por e-mail e CPF opcional em `e0886b1`/`e6bf09c`, SMS descartado no piloto por D16; falta Google/Apple e iOS.)*
- [~] **F5.4** Início, categorias, buscar, perfil do profissional. *(ligados à API real com categorias A–Z, busca unificada `?q=`, filtros `nota_minima`/`atende_hoje` e ranking composto `c4df85b`; falta exibir fotos reais do portfólio na vitrine do cliente e validação em iOS.)*
- [~] **F5.5** Novo pedido com perguntas guiadas, fotos, prazo, faixa de preço. *(ligado à `POST /v1/pedidos` com perguntas da categoria, CEP `/v1/cep`, fotos, urgente `3857bdb` e `F23` `8a58de9`; falta tirar faixas de preço/prazos fixos do app e validação em iOS.)*
- [x] **F5.6** Orçamentos recebidos, detalhe, aceite com contrato digital. *(ligados à API real com contraproposta/prazo e contrato completo em `v0.1.26` `f08b0f8`; texto próprio de cancelamento segue pendente do João e iOS é rastreado em F1.5/F9.3.)*
- [~] **F5.7** Pagamento (Pix/cartão, 30% adiantado) e recibo. *(ajustado a D16 sem 30% adiantados; Pix/cartão via Stripe real + cupom + Tratinhos + `F21`/`F22` validados no E2E em 16/11; falta tela/documento de recibo dedicado e validação em iOS — ver Dúvidas.)*
- [x] **F5.8** Seus pedidos, pedido em execução (linha do tempo, código de início). *(ligados à API real com estado real, "a caminho" `4cad35b`, código e plano B `37fdbe5`, validados no emulador Android em 05/11 e 16/11; iOS em F1.5/F9.3.)*
- [x] **F5.9** Aditivo (aprovar/recusar) e nota de materiais. *(ligados à API real com aprovação de aditivo levando ao pagamento e todas as notas de materiais com URL assinada de foto testada no Storage real em 16/11; iOS em F1.5/F9.3.)*
- [x] **F5.10** Conclusão (código), avaliação, garantia, retrabalho. *(ligados à API real com conclusão com/sem código, avaliação +50 Tratinhos, garantia, contrato e retrabalho validados no emulador em 05/11 e 16/11; iOS em F1.5/F9.3.)*
- [x] **F5.11** Relatar problema (disputa). *(ligado à API real com upload de fotos `enviarFotosLocais` e motivos atualizados em `0eea47b`; iOS em F1.5/F9.3.)*
- [~] **F5.12** Chat, notificações. *(chat com polling, "recebido", foto e botão "Aceitar e pagar" e notificações marcáveis como lidas ligados à API real; falta push real via Firebase/APNs e validação em iOS.)*
- [~] **F5.13** Perfil, ajuda, LGPD (exportar e excluir conta), SOS e compartilhar atendimento. *(Perfil, `ConfiguracoesTela` `3ee7e5b`, dados pessoais/endereços/favoritos/contatos, ajuda e LGPD real ligados à API; SOS e compartilhar fora do MVP por D13; falta chamado de suporte in-app, tela de preferências de notificação e iOS.)*

*Pronto quando (cada uma):* tela confere com o protótipo, teste de widget passa, funciona em Android e iOS. *(Validação iOS de todas as telas do app bloqueada por ausência de Mac — ver F1.5 e F9.3.)*

## Fase 6 — App do Profissional

- [x] **F6.1** Cadastro e verificação (documento + selfie), status da análise. *(cadastro, edição `07/11`, upload real de documento/selfie/portfólio em `UploadsPostgres` e status da verificação ligados à API real e validados no Android/Supabase; raio de atendimento ocultado até decisão em `PENDENCIAS.md`.)*
- [x] **F6.2** Início, pedidos abertos com filtros, detalhe, recusar com motivo. *(ligados à API real com `FiltrosPedidosAbertosTela`, perguntas/fotos no detalhe, recusa com motivo `0beda5e` e exclusividade 48h `5839a4e`.)*
- [x] **F6.3** Calculadora de orçamento (taxa e líquido vindos do backend), etapas, sinal, validade, garantia. *(ligada à API real com valor fechado `8880e6d`, horas `ad058d7`, prazo negociável, erros tratados `6269a7b` e modelo sem taxa `5906fa7`; etapas pagas e sinal adiados por V2/D16.)*
- [~] **F6.4** Agenda, navegação, check-in (foto, local, código), check-out. *(ligados à API real com "Estou a caminho" `4cad35b`, câmera/GPS reais, plano B sem código `37fdbe5`, fila offline em disco `0eea47b` e correções `6269a7b`/`cdc7e28`; falta validar câmera/GPS/offline em aparelho físico e iOS.)*
- [x] **F6.5** Enviar nota dos materiais e criar aditivo. *(ligados à API real e aos pontos de entrada no pedido em execução, com tetos na tela e no backend `cdc7e28`/`27a5351`.)*
- [x] **F6.6** Carteira: retido, a liberar, liberado, extrato, saque Pix (mesmo CPF/CNPJ). *(ajustada ao caminho A/D15 sem saque próprio: retido, a liberar, liberado, valores do pedido, conta de recebimento `6e127a4`, repasse automático `8880e6d` e extrato PDF compartilhável `4cad35b`/`0b23fa1` ligados à API.)*
- [x] **F6.7** Responder disputa, atender retrabalho, perfil público, avaliações. *(ligados à API real com resposta de disputa com proposta/fotos `0eea47b`, retrabalho completo `cdc7e28`, perfil público no app e web sem login `1569e10`, avaliações e bônus por avaliar cliente `4e97c7f`.)*

*Pronto quando:* profissional de teste é aprovado, orça, executa, recebe e saca. *(Saque próprio removido por D15; repasse segue o caminho A.)*

## Fase V2 — Ajustes da Auditoria e Escopo V2 (D13)

Derivada de `docs/v2-impacto.md`. Não depende de aplicar migrations.

- [x] **V2.1** Textos de tela. Trocar "5%", "dinheiro protegido", "garantia", "escrow" e afins por textos da V2 (ex.: "pagamento processado por parceiro", "suporte e análise de problemas"). Tirar o SOS da F5.13. *Pronto quando:* busca no `verificar` não acha os textos proibidos de D13 em `app/lib/`, e testes de widget passam. (P5, P14) *(textos trocados, SOS atrás de `kSosHabilitado = false` e busca de textos proibidos (D13) no `verificar`.)*
- [x] **V2.2** Backend "pago só após o provedor". O pedido e o app só viram "pago" com o webhook assinado do provedor; aceite não é pagamento. Liberação e repasse viram eventos do provedor. *Pronto quando:* testes mostram que nenhuma rota marca "pago" sem evento confirmado; reenvio não duplica. (usa F4.4, F4.5; ver P7) *(pedido só vira pago após webhook assinado, estado `aguardando_confirmacao`; garantia financiada desligada por padrão.)*
- [~] **V2.3** Simulador de margem. Margem de contribuição por serviço = receita − custo de pagamento − chargeback esperado − suporte − garantia/retrabalho − tributos − incentivo, por ticket e método (Pix, cartão à vista, parcelado). *Pronto quando:* tabela de cenários com dados reais de 2 provedores. *Bloqueada por:* P16. *(pacote `trato/margem/` removido em 18/11 no commit `5906fa7` após decisão de app 100% gratuito; sem proposta formal de 2 provedores — ver Dúvidas.)*
- [x] **V2.4** 🔒 Decisão do caminho de custódia: **A (ledger espelho, recomendado)** ou **B (manter até o parceiro confirmar)**. *Pronto quando:* João registra a escolha em `DECISOES.md`; F3.5, F4.4, F4.6 e F6.6 ajustadas ao caminho. *Depende de:* P7, P16 e advogado de pagamentos. *(João escolheu o caminho A em 29/10/2026, D15. F3.5, F4.4, F4.6 e F6.6 ajustadas ao ledger espelho.)*
- [x] **V2.5** Conciliação com o parceiro (ledger espelho × relatório do provedor) e alerta de diferença. *Só no caminho A.* *Pronto quando:* teste com extrato de exemplo acusa a diferença. *(conciliação do dia em `financeiro/conciliacao.py` e na aba "Conciliação do dia"; testes com extrato simulado acusam a diferença. Falta rodar contra o Stripe de verdade e agendar a conferência diária.)*
- [x] **V2.6** Painel admin web responsivo (substitui o app Ops): busca por pedido e usuário, revisão de verificação, fila de casos, conciliação, reembolso por alçada, auditoria. *Pronto quando:* caso de teste decidido no painel. *Depende de:* P9. Cobre parte da Fase 7. *(painel em `admin/` no Design System v2 ligado à API admin real, pronto para Vercel `4e1cc37`, 175+ testes e correções A4 `6163cbb`; deploy da rodada recente aguarda OK do João.)*
- [~] **V2.7** Desligar por configuração o que a V2 adiou: etapas pagas, adiantamento de material, `verificado_plus`, saque próprio, score e ranking. *Pronto quando:* chaves de configuração documentadas e teste de que o fluxo não oferece essas opções. *(etapas pagas, adiantamento de material e saque próprio desligados/removidos; ranking foi religado por decisão do João em 19/11 `c4df85b`; falta limpar referência residual a `verificado_plus` em `repositorios_api.dart` e documentar/testar as chaves vigentes.)*
- [~] **V2.8** Carga do piloto: 1 cidade e 2–3 categorias de baixo risco. 🔒 grava no banco. *Bloqueada por:* P15. *(seeds de Belo Horizonte/MG e categorias aplicados no Supabase real em 31/10/2026 com OK do João; falta ativar a cidade quando o João abrir o piloto.)*

## Fase 7 — Painel administrativo (web) — depende de P9

*Painel web em `admin/` (Flutter Web, Design System v2, `docs/painel-admin.md`, `docs/painel-integracao.md`, pronto para Vercel `4e1cc37`) integrado à API administrativa em Postgres (`backend/src/trato/api/admin/`).*

- [x] **F7.1** Fila de verificação. *(implementada em `verificacao_tela.dart` + `rotas_verificacoes.py` com modal de documento por 10 min, assumir análise, paginação e correções A4 `6163cbb`.)*
- [x] **F7.2** Fila de disputas e decisão. *(implementada em `disputas_tela.dart` + `rotas_disputas.py` com assumir disputa, evidências, reembolso por alçada, aprovação dupla e migration `20261116120000` aplicada.)*
- [~] **F7.3** Pagamentos, conciliação, repasses e saques. *(abas Extrato, Alertas, Contestações, Conciliação do dia, Avisos do provedor, Fechamento mensal e PDF implementadas; saque próprio removido por D15; falta conciliação diária agendada contra Stripe real e assinar eventos de contestação no Stripe.)*
- [~] **F7.4** Usuários, pedidos, suporte, categorias. *(busca, diagnóstico RN-01, bloquear/desbloquear usuário e CRUD de categorias/perguntas prontos; falta tabela e rotas de chamados de suporte — aba exibe estado vazio.)*
- [x] **F7.5** Configurações com validação, aprovação dupla, histórico e reversão. *(implementada em `config_tela.dart` + `rotas_config.py`, incluindo `moedas_tela.dart` e `ranking/config`.)*
- [x] **F7.6** Auditoria imutável. *(implementada em `auditoria_tela.dart` + `rotas_auditoria.py` com cadeia de hash verificável, `X-Auditoria-Id`, filtros, CSV e correção A4 `6163cbb`.)*
- [~] **F7.7** Perfis de acesso por função. *(matriz de papéis, alçadas em `papeis_alcada` e `equipe_tela.dart` prontos; falta convite por e-mail e 2FA obrigatório no primeiro acesso.)*

*Pronto quando:* disputa de teste decidida pelo painel move o dinheiro certo.

## Fase 8 — Segurança, LGPD, conformidade

- [x] **F8.1** Mascarar telefone, endereço só após contratar.
- [x] **F8.2** Antifraude básico (backend; ver `docs/backend-seguranca.md`).
- [~] **F8.3** LGPD: consentimentos, exportar, excluir, retenção. *(serviços, rotas, adaptador Postgres `persistencia/lgpd.py` e migration `20261101180000_lgpd_exclusao_consentimentos.sql` prontos; `GET /v1/me/dados` validado no Fly em 16/11; falta ligar `TRATO_AGENDADOR_EMBUTIDO=true` para anonimização automática após carência e confirmar aplicação completa da migration no Supabase — ver Dúvidas.)*
- [~] **F8.4** Regras das lojas. *(`/privacidade` e `/termos` públicos em `rotas_legal.py`, exclusão de conta in-app e permissões Android/iOS prontos; falta revisão jurídica final e submissão/revisão Play Store e App Store.)*
- [~] **F8.5** Advisors + varredura de segredos no repo. *(varredura ativa em `harness/verificar.py` e CI; advisors rodados em 29/10 e 07/11 com 1 aviso restante de senhas vazadas no Auth; falta re-rodar advisors após migrations de 08/11–21/11 e limpar alertas da varredura em `builds/` e `app/test/auth_test.dart`.)*
- [x] **F8.6** Lista para advogado e contador.

## Fase 9 — Entrega

- [~] **F9.1** Testes ponta a ponta. *(E2E ao vivo 7/7 no Fly + Supabase + Stripe Sandbox em 16/11, `harness/teste_real_*.py`, `subir-pilha-local.py` e suítes QA3–QA5 verdes; falta caminhada visual automatizada do painel admin e rodar B12–B14 contra Postgres real.)*
- [x] **F9.2** Testes de tela em vários tamanhos. *(180 golden tests em 3 tamanhos — celular pequeno `320x568`, celular grande e tablet `1.3x` — `responsivo_test.dart` e QA3/QA5 no app e no painel mobile `400x700` + desktop.)*
- [~] **F9.3** 🔒 Build de teste Android e iOS. *(APKs e AAB de release Android assinados gerados até `v0.1.30` em `builds/` e `.github/workflows/build.yml` criado; falta build iOS por ausência de Mac/Apple Developer e execução do `build.yml` na nuvem com `STRIPE_PUBLISHABLE_KEY`.)*
- [ ] **F9.4** 🔒 Piloto. *(cidade fechada, agendador desligado no Fly, 7 bloqueios de `docs/checklist-lancamento.md` abertos e rodadas recentes ainda só locais.)*
- [x] **F9.5** `docs/COMO-RODAR.md` e `docs/ENTREGA.md` (e `docs/BUILD.md`).
- [ ] **F9.6** 🔒 Release `v1.0.0` (merge em `main`, tag, push). *(última tag existente: `v0.1.31`.)*

## Rodadas recentes (20/11/2026 — só locais na `develop`, sem push nem deploy)

- [x] **QA3 a QA5** Cobertura adversarial no app (cliente e profissional), painel admin e backend em memória (`01abc5c` + `app/test/QA_COBERTURA.md`, `qa5_cliente_fluxos_test.dart`, `qa5_profissional_test.dart`, `admin/test/qa5_admin_test.dart`, `backend/tests/api/test_qa5_backend.py`); todos os bugs reais encontrados (`QA5-1`, `QA5P-1..13`, `QA5B-1..3`, `SEG-1/2/4`) corrigidos nas rodadas abaixo.
- [x] **B12** (`0beda5e`) Backend: proteção de concorrência em `memoria.py`, status 404/403 em `recusar_pedido`/`decidir_disputa` e `desconto_cupom_centavos` separado na resposta.
- [x] **B13** (`c5f0b41`) Backend: correção de `QA5B-1..3` (`limite_por_usuario` no cupom, filtro de mês nas reservas abertas de Tratinhos e bônus no fuso `America/Sao_Paulo`).
- [x] **B14** (`27a5351`) Backend: correção de `SEG-1` (reserva de cupom por usuário na criação da cobrança e registro no webhook), `SEG-2` (tetos da nota de material no backend) e `SEG-4` (nota duplicada devolve 409).
- [x] **F21** (`6269a7b`) App: tratamento de erros no check-in, calculadora e pagamento; pagamento sem opções; linha do cupom vinda do backend.
- [x] **F22** (`d5339aa`) App: botão "Tentar de novo" do pagamento ligado em `rotas.dart`.
- [x] **F23** (`8a58de9`) App: `_faixa` nulo-seguro em `NovoPedidoTela` (`QA5-1`).
- [x] **F24** (`cdc7e28`) App Profissional: correção de `QA5P-1..9` (check-out, nota de material com tetos, retrabalho e perfil público).
- [x] **A4** (`6163cbb`) Painel Admin: correção de `QA5P-10..13` (travas em verificação/assumir, lista mobile `1.3x` em `MestreDetalhe` e guarda contra duplo clique em auditoria).

## Termos v1.2 — rodada de 26/11/2026 (só código local: sem commit, push, deploy nem migration aplicada)

- [~] **T5.3** Comprovante e cópia dos Termos após a contratação. *(Backend e app prontos no local; não testado com servidor real nem aparelho. Envio por e-mail depende de SMTP.)*
- [~] **T1.7/23.4** Novo aceite quando os Termos mudam. *(Backend pronto no local, sem bloquear rotas; tela do app em andamento. Versão vigente segue 1.1.)*
- [~] **T6.9** Contestação de material. *(Backend, painel com abertura de anexos e app prontos no local; sem teste com armazenamento real. App usa só o envio conferido da nota. Migrations 20261126231800 (PDF) e 231900 (acesso n2) só em arquivo, não aplicadas; anexo com finalidade pedido segue visível ao n2. Efeito financeiro não definido: nada move dinheiro; depende de decisão do João.)*
- [~] **T12.6** Moderação e revisão de avaliações. *(Backend e painel prontos no local; banco real não testado.)*
- [~] **T13.10** Aviso de perda de Tratinhos no encerramento voluntário. *(Backend e app prontos no local.)*
- [~] **T14.9/14.10** Pedidos LGPD e revisão de decisão automatizada. *(Backend, painel e app prontos no local; banco real não testado.)*
- [~] **T20.9** Impedimento de cadastro e retorno de conta. *(Backend, painel e app prontos no local, com a correção que libera a conta bloqueada nas 2 rotas de retorno; não testado com o login real do Supabase.)*
- [~] **T-VISUAL** Comparações visuais do app. *(Lotes fechados no local; `navegacao_sem_placeholder` 10/10 (relato do Flutter; é lento, cerca de 9 min); barra inferior ajustada em telas estreitas.)*

## Dúvidas (sem evidência conclusiva — mantidas conservadoramente)

- **F2.5 / F5.1**: Não há registro explícito no `PROGRESSO.md` da aprovação lado a lado final do Splash + Onboarding pelo João após a entrada leve (`e0886b1`). Mantidas em `[~]`.
- **V2.3**: O simulador `trato/margem/` foi removido em `5906fa7` após a decisão de app 100% gratuito (18/11/2026) e não há proposta escrita de 2 provedores (P16). Confirmar com o João se deve ser encerrada ou mantida para monetização futura. Mantida em `[~]`.
- **F5.7**: Não existe tela/documento dedicado de recibo em `app/lib/` (o pagamento aparece no detalhe do pedido e no Stripe). Confirmar se recibo separado ainda é requisito. Mantida em `[~]`.
- **F8.3**: `GET /v1/me/dados` foi validado no Fly/Postgres real em 16/11, mas não há confirmação explícita no `PROGRESSO.md` de aplicação da migration `20261101180000_lgpd_exclusao_consentimentos.sql` inteira no Supabase real (além do agendador desligado no Fly). Mantida em `[~]`.
- **F5.x / F6.x (validação iOS)**: Itens marcados `[x]` têm evidência completa de API real + testes + Android, mas nenhum rodou em iOS por falta de Mac (pendência concentrada em `F1.5` e `F9.3`).
