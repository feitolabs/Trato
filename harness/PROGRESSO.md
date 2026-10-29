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

## 29/10/2026 — Telas ligadas ao fluxo

- `app/lib/telas/fluxo/rotas.dart` liga: login/cadastro → casca do cliente; aba Pedidos → pedido em execução → chat → conclusão → avaliação ou relato; finalizado → garantia. Cadastro de profissional → `AreaProfissionalProvisoria` (calculadora e check-in, com serviços de teste).
- Testes: 267 no app (7 percursos novos em `test/fluxo_test.dart`). No emulador: splash → onboarding → login → cadastro (formulário preenchido e validado). Não conferido no emulador: confirmar celular → casca, e as telas de pedido (só nos testes).
- Ainda sem tela: orçamentos recebidos, novo pedido, disputa em andamento, perfil do cliente, lista de mensagens, home do profissional. Dados continuam de exemplo.

## 29/10/2026 — Integração em lote (sessões do banco, API, telas e docs)

- Em develop (sem push), uma por vez, cada uma verificada antes de entrar: F2.4 duplicada com telas F5.5/F5.6 (`telas/orcamentos/`, `telas/pedido_novo/`), F5.7 e F5.13 (`telas/pagamento/`, `telas/perfil_cliente/`), F6.2 (`telas/profissional_inicio/`), camada HTTP do backend (`trato/api/`), F6.6 (`telas/carteira/`), banco F3.3 a F3.8 (**só arquivos SQL**) e docs (`docs/advogado-e-contador.md`, `docs/COMO-RODAR.md`, workflow `.github/workflows/verificar.yml`, não executado).
- Ligação no fluxo (`rotas.dart`): pedido com orçamentos → lista → detalhe → aceite → pagamento; aba Perfil do cliente; cadastro de profissional agora cai na casca do profissional (check-in e orçamento com serviços de teste).
- Testes em develop: 362 no backend, 404 no app, verificação OK.
- **Migrations F3.3 a F3.8c NÃO foram aplicadas no Supabase.** Plano e riscos em `docs/seguranca-banco.md`; aplicar é decisão do João. Testadas num Postgres local (574 verificações).
- Para o app/backend: nas tabelas com colunas escondidas não usar `select *`; app só lê, escrita pelo backend com `service_role`; buckets `verificacao`, `pedido-midias`, `chat-anexos`, `avatar` com upload por URL assinada.
- Descoberta: tabelas novas do `public` nascem com TRUNCATE/REFERENCES/TRIGGER para anon/authenticated e sem SELECT/INSERT para service_role; as migrations dão os grants explicitamente.
- Não ligado ainda (sem ponto de entrada óbvio): Novo pedido (tela 11), Carteira na aba do profissional (a casca tem a aba como "em breve"), `AreaProfissionalProvisoria` ficou sem uso. Sair do perfil sem ação definida.
- `docs/COMO-RODAR.md` cobre F9.5 só em parte (falta `ENTREGA.md`).


## 29/10/2026 — Simulador de margem V2 (`trato/margem/`)

- Novo pacote `backend/src/trato/margem/`: `regras.py` (taxa única % com mínimo, ou tabela progressiva por faixas, modo marginal ou faixa inteira), `simulador.py` (margem = taxa − provedor − chargeback esperado − suporte − garantia − tributos − incentivo; usa o custo do Stripe de `pagamentos/custo.py`) e `relatorio.py` (gera as tabelas de `docs/simulacao-margem.md`). Tudo em centavos/bps inteiros, sem `float`, half-up uma vez por percentual.
- Testes em `backend/tests/margem/` (55): Pix, cartão à vista, 3x e 6x, os dois tipos de regra, arredondamento e soma exata.
- `docs/simulacao-margem.md`: tickets R$ 80 a R$ 3.000 × Pix/cartão/3x/6x para 5% fixa, 7,5% fixa e progressiva 7,5/5/3,5. **Custos do provedor são ESTIMATIVAS até haver proposta (P7); faixas e mínimo de R$ 5,00 são hipóteses (P2).** Resultado: Pix nunca negativo; cartão 6x negativo em tudo; 5% fixa perde no cartão até R$ 500; a progressiva fica negativa no 3x a partir de R$ 1.000.
- Sem banco, sem `app/`, sem push.


## 29/10/2026 — Telas do profissional faltantes (F6.1, F6.5, F6.7, F5.9 cliente)

- Branch `feature/telas-profissional-faltantes`. 10 telas novas em `telas/{profissional_cadastro,verificacao,nota_material,aditivo,disputa_profissional,perfil_publico}/` + peças comuns em `telas/profissional_apoio/`. Serviços por interface com fakes; callbacks a ligar em `rotas.dart` listados em `docs/telas-profissional.md`.
- Protótipo não conferido página a página: todas marcadas "sem protótipo".
- Testes: `test/telas_profissional_test.dart` (27) e goldens 14×3. Não mexi em main.dart, rotas.dart, componentes.dart nem tema.
## 29/10/2026 — Rodada V2 integrada

- Em develop (sem push nesta sessão), uma por vez, cada uma verificada: `v2-margem` (simulador e `docs/simulacao-margem.md`), `v2-impacto-docs` (`docs/v2-impacto.md`, PENDENCIAS, TAREFAS, advogado-e-contador), `feature/v2-backend-d13` (pedido só pago após webhook assinado; garantia financiada desligada; janela de congelamento separada dos prazos legais) e `v2-textos-telas` (textos sem promessas proibidas; SOS atrás de `kSosHabilitado`). `claude/v2-backend-pago-43520a` não tinha commits próprios: os do backend estavam em `feature/v2-backend-d13`.
- Testes em develop: 442 no backend, 406 no app, verificação OK.
- Decisões D13, D14 e D15 registradas em `DECISOES.md`. D15: custódia caminho A (ledger espelho, sem saldo próprio nem saque).
- Estado do banco (informado pelo João): F3.3, F3.4 e F3.7 **aplicadas** no Supabase em 29/10/2026 (versões 20261029170308, 20261029170728, 20261029170820). F3.5 está sendo refeita para o caminho A (a atual não será aplicada); F3.6 e F3.8 aguardam. F1.8: `origin` ligado e push de `main` e `develop` feito em https://github.com/feitolabs/Trato.
- Não integradas por orientação: `banco-de-dados-seguro` (refazendo F3.5/F3.6/F3.8) e `auth-login` (ainda trabalhando).
- Pendências: busca de textos proibidos no `verificar` (V2.1); custos reais de provedor para fechar V2.3 (P7/P16); ajustar a tela Carteira ao extrato (F6.6).

## 29/10/2026 — Banco refeito para o caminho A integrado e aplicado

- Em develop (sem push): `claude/fase-3-banco-completo-23eeae` (commit 34e6219: F3.5 refeita para o caminho A/D15, sem saque, chave Pix nem saldo; F3.6, F3.8b, rollbacks, testes e docs ajustados). Verificação: 442 testes no backend, 406 no app, TUDO OK.
- Informado pelo João/sessão principal: aplicadas no Supabase em 29/10/2026 F3.3, F3.4, F3.5 (caminho A), F3.6, F3.7, F3.8a, F3.8b e F3.8c. Advisor de segurança sem alertas; 46 tabelas com RLS, 92 policies, 0 privilégios do anon, 4 buckets privados. Não apliquei nada: só os arquivos entraram em develop.
- Faltam só os seeds (cidade, categorias, taxa, contas do ledger), que dependem de P2, P6, P7 e do OK do João.
- Não integradas por orientação (sessões em andamento): ligar-backend-banco, ligar-app-api, telas-profissional, telas-comuns, pagamento-e2e e auth-login.

