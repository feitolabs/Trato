# Progresso

Diário do projeto. Uma entrada por sessão, mais recente no fim.

## 28/10/2026 — Fase 0 e início da Fase 1

**Feito**
- Gitflow montado: `main` (commit inicial com documentos), `develop`, features por fase.
- Fase 0: `CLAUDE.md`, `harness/RESUMO.md`, `DECISOES.md`, `PENDENCIAS.md`, `TAREFAS.md`, `verificar.py` (+ `.ps1`/`.sh`).
- Fase 1 (parte que não precisa de OK): pastas, `.env.example`, `.gitattributes`, backend FastAPI com `/saude` e teste, esqueleto do app Flutter (`pubspec.yaml`, `lib/main.dart`, teste).

**Falhou / bloqueado**
- Flutter SDK não instalado: não deu para gerar `android/` e `ios/` nem rodar `flutter analyze`/`test`.

**Pendente**
- João aprovar `TAREFAS.md` (F0.6).
- Responder `PENDENCIAS.md` P1–P4 antes da Fase 4 (dinheiro).
- 🔒 Conectar Supabase (leitura) e GitHub (push).

**Próxima tarefa:** F1.5 (instalar Flutter e gerar plataformas) ou F2.1 (tokens de design).

## 28/10/2026 — F1.5 plataformas Flutter

**Feito**
- João aprovou o `TAREFAS.md` e instalou o Flutter (3.47.8, `C:\flutter`).
- `flutter create` gerou `android/` e `ios/` (org `br.com.feitolabs`). Nome no Android ajustado para "Trato".
- `verificar.py` acha o Flutter fora do PATH. Verificação completa: TUDO OK (backend 3 testes, `flutter analyze` sem problemas, `flutter test` 1 teste).

**Pendente**
- Android SDK (emulador) e Mac para iOS — ver PENDENCIAS.

**Próxima tarefa:** F2.1 (tokens de design do protótipo).

## 28/10/2026 — F2.1 e F2.2 tema do protótipo

**Feito**
- Cores medidas nos pixels do PDF de telas (o PDF é imagem + OCR) → `docs/design-tokens.md`.
- Tema Flutter em `app/lib/tema/` (cores, tipografia, espaços, ThemeData). Fontes Archivo e Figtree (OFL) embutidas em `app/assets/fontes/`.
- Splash provisória com o tema; golden tests em 3 tamanhos (320, 390, 768 de largura).
- `verificar` agora falha se houver cor solta fora de `lib/tema/`. Verificação: TUDO OK (8 testes no app, 3 no backend).

**Riscos**
- Goldens gerados no Windows: podem dar diferença de pixel em macOS/Linux. Gerar no CI quando existir.
- Fontes a confirmar (P12).

**Próxima tarefa:** F2.3 (componentes: botão, campo, cartão, chip, linha do tempo, barra de abas).

## 28/10/2026 — Android rodando

**Feito**
- João instalou o Android Studio. SDK em `%LOCALAPPDATA%\Android\Sdk`, emulador `Medium_Phone_API_37.0`.
- `flutter build apk --debug` ok (primeiro build ~10 min: Gradle 9.3.1, NDK 28.2 e Platform 36 baixados automaticamente).
- APK instalado e aberto no emulador: splash igual ao protótipo e ao golden.

**Pendente**
- Command-line Tools + licenças (João). iOS precisa de Mac.

**Próxima tarefa:** F2.3 (componentes).

## 28/10/2026 — F2.3 componentes

**Feito**
- `app/lib/componentes/`: BotaoPrimario, BotaoSecundario (com estado selecionado), BotaoLink, CampoTrato (rótulo, dica, ajuda, erro, "R$"/"h" fixos), CartaoTrato (claro, escuro, tocável), ChipStatus (info, alerta, sucesso, perigo, destaque), LinhaDoTempo, BarraAbasTrato (abas do cliente e do profissional).
- Galeria em `lib/galeria/` (`--dart-define=GALERIA=true`), conferida no emulador Android e em golden (celular e celular pequeno).
- 13 testes novos de componente; testes carregam fontes reais e ícones Material.

**Pendente**
- P13: ícones estilo Lucide.

**Próxima tarefa:** F2.4 (responsividade: breakpoints e largura máxima no tablet).

## 28/10/2026 — F2.4 responsividade

**Feito**
- `lib/tema/responsivo.dart`: faixas pequeno/celular/tablet, margem por faixa, largura máxima 560 no tablet, escala de fonte limitada a 0,9–1,3.
- Barra de abas própria (rótulo nunca quebra), botões e rótulos de campo em uma linha.
- 17 testes novos (5 tamanhos × 2 escalas de fonte, sem estouro) + goldens de tablet e fonte grande.
- Conferido no emulador Android com fonte do sistema em 2,0.

**Paralelo:** propostas as sessões F4.1 (estados do pedido) e F3.1 (modelo de dados, só documento), em worktrees próprias, sem merge.

**Próxima tarefa:** F2.5 (splash + onboarding iguais ao protótipo, aprovação lado a lado).

## 28/10/2026 — F2.5 splash, onboarding e escolha de perfil

**Feito**
- Splash completa (logo Feito Labs desenhado em código, pontos, "Toque para começar"), onboarding de 3 páginas (PageView, Pular, Próximo, Já tenho conta) e escolha de perfil, tudo com o tema e responsivo.
- Fluxo: splash → onboarding → escolha de perfil → "em breve" (login e cadastro ficam na F5.2 e F5.3).
- 13 testes novos (fluxo e goldens em 3 tamanhos); verificação OK. Conferido no emulador Android.

**Pendente**
- João aprovar lado a lado com o PDF (critério da F2.5). Textos das páginas 2 e 3 são meus (P14). Ícones ainda Material (P13).

**Paralelo (em worktrees, sem merge):** F4.1 estados do pedido (commit e1be9cf, 82 testes), F3.1 modelo de dados (documento), F4.6 ledger, F4.3 e F4.5 (custo Stripe, webhook e idempotência) em andamento.

## 28/10/2026 — Integração das sessões paralelas

**Feito (merge em develop, sem push)**
- F4.1 `backend/src/trato/pedidos/estados.py`: máquina de estados do pedido.
- F4.6 `backend/src/trato/financeiro/ledger.py`: ledger de partidas dobradas em centavos, imutável, idempotente.
- F4.3 `backend/src/trato/pagamentos/custo.py`: custo do meio de pagamento e margem do Trato (taxas por parâmetro).
- F4.5 `pagamentos/webhook.py` e `idempotencia.py`: assinatura no formato Stripe e registro de eventos.
- F3.1 `docs/modelo-de-dados.md`: proposta de modelo (nada aplicado no Supabase).
- Develop: 163 testes no backend, 51 no app, verificação OK.

**Pendente**
- João aprovar o modelo de dados (F3.1) antes de qualquer migration (F3.2 em diante 🔒) e responder P2/P6 (seed de taxa e cidade).
- F4.2 e F4.4 continuam bloqueadas por P1–P4 e P7.

**Próxima tarefa:** F3.9/F3.2 dependem do OK do João; do lado do app, F5.2 (login) e F5.3 (cadastro).

## 28/10/2026 — Modelo aprovado e leitura do Supabase

- João aprovou `docs/modelo-de-dados.md` (F3.1). Valem as propostas provisórias do documento (N1 sem coluna de papel, N8 região por cidade/bairro, N10 `excluir_em` sem prazo, N11 escrita só pelo backend) até ele decidir diferente.
- Leitura (sem escrita) no Supabase: projeto "Trato" `ornaoshsvuszquntkqsk`, região sa-east-1, Postgres 17.11, status ativo, **0 tabelas e 0 migrations**.
- Plano da F3.2 apresentado ao João; **nada foi criado nem aplicado**.
- Aviso: a sessão da F3.1 abriu por conta própria F4.7 (disputa), F4.8 (garantia) e uma F2.4 duplicada (responsividade, já integrada em develop). Nenhuma foi integrada.

## 28/10/2026 — F3.2 escrita (não aplicada)

- `supabase/migrations/20261028000100_f32_identidade_catalogo_config.sql`: 15 tabelas, RLS ligado em todas e sem policy, triggers de `atualizado_em`, validação de parâmetros e imutabilidade de configuração aprovada. **Só estrutura: nenhum dado, nenhuma taxa, nenhuma cidade.**
- `supabase/rollback/F3.2_rollback.sql` desfaz tudo.
- Testado num Postgres 16 local e descartável (`supabase/testes/testar_f32.py`): constraints, triggers, rollback e reaplicação OK. **Não testado:** o EXCLUDE de faixas sobrepostas (o Postgres embutido não tem btree_gist; o Supabase tem).
- Nada foi enviado ao Supabase. Falta o OK do João para aplicar.
- Seed de `config_definicoes` fora desta migration: precisa dos limites mínimo e máximo de cada parâmetro, que o João define.
- Em paralelo: F5.2/F5.3 (telas de login e cadastro) na sessão f2-4-responsivo, F4.9 (rotinas) na f4-1, F4.7 e F4.8 em andamento.

## 28/10/2026 — F4.7, F4.8 e F4.9 integradas

- `backend/src/trato/disputas/` (F4.7), `garantias/` (F4.8) e `rotinas/` (F4.9), todas em Python puro, prazos por configuração, sem banco.
- Develop: 305 testes no backend, 51 no app, verificação OK. Sem push.
- Falta para fechar a Fase 4: F4.2 (taxa progressiva, P2), F4.4 (fluxo de pagamento, P1/P4/P7) e F4.10 (simulação ponta a ponta).

## 28/10/2026 — F5.2 e F5.3 (telas) integradas

- `app/lib/telas/auth/`: login, criar conta (passo 1), confirmar celular (passo 2) e recuperar senha, com validação no app e goldens em 3 tamanhos. Onboarding e escolha de perfil agora levam a elas.
- Develop: 305 testes no backend, 108 no app, verificação OK. Sem push.
- Provisório (abre EmBreveTela): Google, Apple, biometria, envio de SMS e de código. Falta ligar ao Supabase Auth e escolher o provedor de SMS (P11).

## 29/10/2026 — F3.2 aplicada no Supabase

- Com o OK do João, `apply_migration` no projeto "Trato" (`ornaoshsvuszquntkqsk`): versão `20261029025430`, 15 tabelas, RLS ligado em todas, 10 gatilhos, extensão `btree_gist` e o EXCLUDE de faixas criados. 0 linhas em qualquer tabela (sem taxa, cidade nem definições).
- Arquivo local renomeado para a versão do Supabase. Rollback em `supabase/rollback/F3.2_rollback.sql` (não executado).
- Advisors de segurança: 15 INFO "RLS ligado sem policy" (esperado até a F3.8) e 2 WARN da função `public.rls_auto_enable()` (SECURITY DEFINER executável por anon/authenticated), que **já existia no projeto** (usada pelo gatilho de evento `ensure_rls` da plataforma). Não mexi: revogar o EXECUTE é mudança de permissão e precisa de OK do João.
- Não testado no banco real: o comportamento do EXCLUDE (precisaria inserir linhas de teste). A existência da constraint foi confirmada.
- Em paralelo, telas (só app/): F5.4 (início/buscar/perfil), F5.8-F5.9 (pedidos/chat), F5.10-F5.11 (conclusão/avaliação/disputa/garantia) e F6.3-F6.4 (calculadora/check-in).

## 29/10/2026 — Revogado o acesso público a rls_auto_enable

- Com o OK do João: `revoke execute on function public.rls_auto_enable() from public, anon, authenticated` (versão `20261029025741`). Antes, ACL padrão: anon e authenticated executavam.
- Teste sem rastro: uma tabela criada dentro de um bloco que dá erro e desfaz tudo nasceu com RLS ligado, então o gatilho `ensure_rls` continua funcionando. Continuam 15 tabelas.
- Advisors de segurança: os 2 WARN sumiram. Restam 15 INFO "RLS sem policy" (esperado até a F3.8).
- Rollback em `supabase/rollback/rls_auto_enable_rollback.sql` (não executado).

## 29/10/2026 — Telas do cliente e do profissional integradas

- Em develop (sem push): F5.4 (`telas/cliente/`), F5.8-F5.9 (`telas/pedidos/`), F5.10-F5.11 (`telas/conclusao/`), F6.3-F6.4 (`telas/profissional/`). Verificação: 305 testes no backend, 260 no app.
- Marcadas como em andamento (`[~]`): as telas existem com dados de exemplo, mas **não estão ligadas ao fluxo** nem ao backend. Falta ligar a casca do cliente ao login, as telas entre si e tudo à API.
- Pendências vindas das sessões: P1 (48 h x 7 dias na conclusão), P2/P5 (taxa mostrada na calculadora vem de interface, hoje com implementação fake), P13 (ícones).
