# Status do MVP — tela por tela

Atualizado em 30/10/2026, depois de ligar o app às rotas novas e de eliminar os placeholders (`docs/placeholders.md`). Divergências: `docs/app-divergencias.md`.

Legenda do app:
- **API**: no modo `api` (`--dart-define=TRATO_MODO=api`) chama a API de verdade.
- **Demo**: só dados de exemplo, mesmo no modo `api` (a rota ou o serviço real ainda não existe).
- **Sem protótipo**: a tela segue o padrão visual das vizinhas, mas ninguém conferiu contra o PDF de design.

O app sempre abre em `demo`. Sem `TRATO_API_URL`, o modo `api` cai em `demo`. Detalhes: `docs/app-ligacao.md`.

## Cliente

| Tela | Estado | Observação |
|---|---|---|
| Splash, onboarding, escolha de perfil | Demo | Primeira abertura: splash → onboarding → escolha de perfil → cadastro → casca do perfil. Com sessão guardada, a splash vai direto à casca. O perfil escolhido fica nos dados da conta (`perfil` no Supabase Auth) e o login abre a casca do cliente ou do profissional. |
| Login, criar conta, recuperar senha | Demo (serviço de teste) | `ServicoAuth` pronto; o `main.dart` troca para o Supabase quando há `SUPABASE_URL` e `SUPABASE_ANON_KEY`. O token do login vai em toda chamada da API (`LigacaoSessao` → `SessaoTrato`); em 401 o app renova o token e repete a chamada uma vez, e se não renovar limpa a sessão e abre o login por cima da tela (o que foi digitado fica). Ver `docs/login-configuracao.md`. |
| Google, Apple | Depende do João | Chaves. SMS desligado (D16); cadastro confirma por e-mail. |
| Início, buscar, perfil do profissional | Demo | Backend pronto (busca #10, perfil público por id #11, `docs/api-rotas.md`); falta o app ligar. |
| Busca com serviço (`busca/`) | Demo, ligada | É a aba Buscar do cliente (`RotasTrato.abaBuscar`), abre o perfil público. Filtros e mapa da tela antiga (`BuscarTela`) saíram da aba; a busca real depende do backend. |
| Google, Apple, SMS | Depende do João | Chaves e provedor (P11). |
| Início | Ligado | Nome, categorias, pedido em andamento e serviços recentes vêm dos repositórios; sino → Notificações; "Pedir orçamento" → escolha da categoria → Novo pedido; categoria → lista; "Ver todas" → todas as categorias; serviço → detalhe. |
| Todas as categorias | Demo (sem rota de catálogo) | Grade com busca, só as ativas do catálogo. Sem protótipo. |
| Categoria | Demo (sem rota) | Cabeçalho, filtros (bairro, preço, avaliação, hoje), nota, serviços concluídos, região e "Pedir orçamento" (abre o Novo pedido na categoria). Sem protótipo. |
| Perfil do profissional (cliente) | API (id) / Demo | `GET /v1/profissionais/{id}`; abre de busca, categoria, orçamento e serviço. Bio, serviços, trabalhos (legenda), avaliações e selo sem prometer segurança. Fotos do portfólio: legendas, sem imagem ainda. |
| Detalhe do serviço | API | `GET /v1/pedidos/{id}`, `/saldo`, `/eventos`. Linha do tempo, profissional, valores do backend e ações por estado (orçamentos, pagar, acompanhar, conversar, avaliar, garantia, abrir problema). Sem protótipo. |
| Serviços recentes (lista) | API | `GET /v1/pedidos`. Sem protótipo. |
| Busca (`busca/`, resultados por texto) | Demo, ligada ao catálogo | Aba Buscar: campo, categorias (→ Categoria) e "Ver todas"; resultados com nota, serviços e região; abre o perfil. Depende da rota de busca (#10) no modo `api`. |
| Busca e perfil público (backend) | Pronto no backend | Rotas de busca (#10) e perfil por id (#11) existem (`docs/api-rotas.md`); o app liga o perfil por id e mantém a busca em demo até ligar a rota de busca. |
| Novo pedido (tela 11) | API | `POST /v1/pedidos`. A API ainda não tem campos de serviços, descrição nem faixa de preço. |
| Seus pedidos | API | Título genérico ("Pedido #XXXX"): a API não devolve título nem nome do profissional. |
| Orçamentos recebidos e detalhe | API | `GET /v1/pedidos/{id}/orcamentos` + `GET /v1/orcamentos/{id}`; aceite em `acoes/aceitar_orcamento`. Selo, nota e total de serviços do profissional não vêm da API (mostra "—"). |
| Pagamento e aguardando confirmação | API | Valor e meios em `GET /v1/pedidos/{id}/pagamento`; `POST /v1/contratos/{id}/cobranca` (idempotente); consulta `GET /v1/contratos/{id}/pagamento` até `pago: true`. Depois de pago o app abre o pedido em andamento. Nunca marca pago sozinho (D13). Em modo `postgres` a cobrança ainda dá 503 no backend. |
| Pedido em execução, código de início | API | Fotos do check-in não vêm da API. |
| Aditivo e nota de materiais (lado do cliente) | API | `GET/POST /v1/contratos/{id}/aditivos...` e `notas-material`. Aprovar cria a cobrança do aditivo, mas o app ainda não tem a tela de pagá-la. Sem protótipo. |
| Conclusão, confirmar serviço | API | Valores de `GET .../saldo`. |
| Avaliação | API | `POST /v1/contratos/{id}/avaliacao` (nota geral = média dos critérios). Gorjeta não tem rota: o app avisa e não envia. |
| Relatar problema (disputa) | API | `POST .../disputa`. |
| Garantia e retrabalho | API | `GET /v1/contratos/{id}/garantia` e `POST .../retrabalho`. Textos "o que cobre" são de tela. |
| Chat do pedido | API | `GET/POST /v1/pedidos/{id}/mensagens`. Antes de contratar, o cliente precisa de `?profissional_id=` (divergência 21). |
| Mensagens (aba, lista de conversas) | Demo / `api` por pedido | No modo `api` uma conversa por pedido contratado (sem texto da última mensagem); falta a rota da lista (#13). Sem protótipo. |
| Notificações | API (lista) | `GET /v1/notificacoes`; o toque abre o serviço, o orçamento, o chat, o pagamento ou a disputa conforme o tipo. Marcar como lida, preferências e token de push: sem rota (#8, #9). |
| Perfil do cliente | API | `GET /v1/me` (o primeiro login chama a rota e cria o usuário) e `PATCH /v1/me` no repositório; falta a tela de editar o nome. |
| Central de privacidade (LGPD) e excluir conta | Implementado | Prazos definidos na Política de Privacidade (90 dias documentos recusados, 5 anos financeiro, 6 meses logs). Exclusão real conectada ao backend. |
| Ajuda | Demo, sem protótipo | Perguntas frequentes provisórias. |
| Perfil: notificações, privacidade, ajuda, usar como profissional, **Sair** | Ligados | Sair encerra o login, limpa o token e volta ao login sem histórico. |
| Perfil: termos e políticas | Ligado | Termos de uso e Política de privacidade (rascunho de `docs/juridico/`, com aviso de revisão). |
| Perfil: dados pessoais, endereços, pagamento, favoritos, contatos | Sem tela | Itens **removidos da lista**; fora do MVP até haver rota (`docs/placeholders.md`). |
| Perfil público do profissional | Demo | Ver #11. Sem perfil nos dados: aviso "Perfil indisponível". |
| Pedido em disputa/retrabalho/cancelado (cliente) | Ligado | Abre o detalhe do serviço. |
| SOS | Desligado | `kSosHabilitado = false` (D13). |

## Profissional

| Tela | Estado | Observação |
|---|---|---|
| Cadastro do profissional | Demo, sem protótipo | Catálogo pronto no backend (#12, `GET /v1/catalogo/...`); falta o app ligar. A foto sobe pela câmera real. |
| Verificação (documento e selfie) | API | Fotos por URL assinada (`POST /v1/uploads`, `PUT`, `concluir`) e `POST/GET /v1/profissional/verificacao`. Texto de retenção vem do backend quando já há verificação. Não testado em aparelho real. |
| Início, pedidos abertos, detalhe, recusar | API | `GET /v1/profissional/pedidos-abertos` (filtros no repositório), nome por `/v1/me`, recusa `POST /v1/pedidos/{id}/recusar` (precisa da migration `pedido_recusas`). Carteira da Início fica em zero (#18). |
| Filtros dos pedidos abertos | API | Tela com categoria, bairro, faixa de preço e ordem; aplica `GET /v1/profissional/pedidos-abertos`. Sem protótipo. |
| Calculadora de orçamento | API | `POST /v1/orcamentos/resumo` para simular e `POST /v1/pedidos/{id}/orcamentos` para envio (`ServicoOrcamentoApi`). |
| Check-in e check-out | API (envio) | Câmera e GPS reais; foto por `POST /v1/uploads`; ação em `acoes/fazer_check_in`/`fazer_check_out`. Reenvio offline manda `offline_capturada_em`, que o backend recusa (#4). Não testado em aparelho real. |
| Enviar nota de materiais e criar aditivo | API | `POST /v1/contratos/{id}/notas-material` e `.../aditivos`. O caminho da foto da nota ainda não vem do upload (#5). |
| Responder disputa e atender retrabalho | API | `ServicoDisputaProfissionalApi` ligado a `POST /v1/pedidos/{id}/disputa/resposta` e `POST /v1/pedidos/{id}/retrabalho/atender`. |
| Carteira | API, como extrato | `GET /v1/extrato`. Sem saldo próprio e sem saque (D15). |
| Perfil público e avaliações recebidas | Demo, sem protótipo | Na aba Perfil da casca do profissional, com botão **Sair**. |
| Pedidos (aba) | API | Pedidos abertos com filtros e, ao lado, as conversas. Sem protótipo. |
| Agenda (aba) | Demo / `api` parcial | Lista por dia com check-in; no modo `api` só o próximo atendimento (falta rota de agenda). Sem protótipo. |
| Mensagens do profissional | Demo / `api` parcial | Segmento "Conversas" da aba Pedidos; no modo `api` só o atendimento de hoje. |

## Backend (`backend/`)

| Peça | Estado |
|---|---|
| Regras puras (estados, taxa, custo, ledger, disputa, garantia, rotinas) | Pronto, testado |
| API HTTP (pedidos, disputa, retrabalho, extrato, webhook) | Pronta; persistência em memória por padrão e **Postgres** com `TRATO_PERSISTENCIA=postgres` (`docs/api-persistencia.md`) |
| Pagamento (provedor fake e Stripe só `sk_test_`, webhook assinado, ledger espelho) | Pronto em teste; **nenhuma chamada real** (`docs/f4-10-simulacao.md`) |
| Simulador de margem | Pronto; custos do provedor são estimativas (`docs/simulacao-margem.md`) |

## Banco (Supabase "Trato")

Migrations F3.2 a F3.8c aplicadas (informado pelo João/sessão principal): 46 tabelas com RLS, 92 policies, 4 buckets privados. **Faltam os seeds** (cidade, categorias, taxa, contas do ledger).

## O que depende do João

| Item | O que falta |
|---|---|
| P1 / P17 | Prazo de liberação e política de cancelamento/disputa (48 h × 7 dias), com o jurídico |
| P2 | Taxa única do piloto e mínimo em R$ (depende da simulação com tarifas reais) |
| P6 / P15 | Confirmar cidade (BH) e escolher 2 ou 3 categorias do piloto |
| P7 / P16 | Parceiro de pagamento e propostas de dois provedores; contas do ledger |
| Chaves | `.env` com Supabase (URL, anon, service_role, `DATABASE_URL`, JWT), Stripe de teste, segredo do webhook |
| Google e Apple | Credenciais de login (`docs/login-configuracao.md`) |
| SMS | Desligado no piloto (D16); só volta com provedor (P11) e hook |
| Seeds | Autorizar a carga de cidade, categorias, taxa e contas do ledger |
| Design | Conferir as telas "sem protótipo" contra o PDF |

## Próximos passos técnicos (sem depender do João)

1. ~~Token do Supabase Auth no `SessaoTrato`~~ feito (`LigacaoSessao`). ~~Pontos de entrada~~ feitos; renovação do token e 401 feitos.
3. Criar as rotas que faltam no backend (orçamentos, cobrança, mensagens, notificações, perfil, pedidos abertos, verificação).
4. Envio de fotos e posição ao backend (buckets por URL assinada): implementar `EnvioMidia` quando a rota existir. Câmera e GPS já capturam; textos de permissão em `AndroidManifest.xml` e `Info.plist`. Não testado em aparelho real.
5. ~~Busca de textos proibidos (D13) no `verificar`~~ feita.

## Painel administrativo (`admin/`, web)

| Parte | Estado |
|---|---|
| Verificação, disputas, pagamentos (leitura), busca e suporte, configurações, auditoria (F7.1 a F7.6) | Demo: telas com dados de exemplo e controle por papel (`docs/painel-admin.md`) |
| API administrativa no backend | Pronta e testada, em memória e contra Postgres local (`docs/api-admin.md`) |
| Ligação painel ↔ API | Feita: cliente HTTP escolhido por `--dart-define`, com fallback para os fakes (`docs/painel-admin.md`). Falta testar contra uma API admin com banco real |
| Perfis de acesso por função (F7.7) | Papéis no painel e na API; sem usuários de equipe reais (seed do administrador é "A DEFINIR PELO JOÃO") |

## Backend: notificações, segurança e LGPD (30/10/2026)

| Parte | Estado |
|---|---|
| Notificações, conversas e agendador das rotinas | Pronto no backend, testado; ligar no app (hoje o app usa fakes nessas áreas) |
| Mascaramento do chat, antifraude, limite de taxa (F8.1, F8.2) | Pronto no backend (`docs/backend-seguranca.md`) |
| LGPD: exportar dados, exclusão em 2 passos, consentimentos (F8.3) | Serviços e rotas em memória; faltam adaptadores/migrations Postgres (OK do João) e prazos de retenção (jurídico) |
| Revisão de segurança | Relatório e 13 testes xfail que reproduzem os achados críticos/altos em `docs/` e `backend/tests/`; correção ainda por fazer |
| Fidelidade visual (app × PDF) | Aplicada em tema e componentes; `docs/fidelidade-visual.md`. Ícones (P13), fontes (P12) e onboarding 2/3 (P14) seguem com o João |

## Correção dos achados da revisão de segurança (30/10/2026)

| Grupo | Estado |
|---|---|
| Dinheiro: C1, A3 a A7, M1 a M5 (`fix-dinheiro`) | Corrigidos e testados; persistência de ledger, disputas, garantias, avaliações, webhooks e repasses no Postgres (local). Migration `20261030120000_ordens_estorno.sql` **não aplicada**: precisa do OK do João. |
| App: sessão em armazenamento seguro, lista permitida de `dart-define`, EXIF e afins (`fix-app`) | Corrigido e testado (`docs/fix-app.md`) |
| Acesso: A1, A2, A8, M6, M7, M9 a M12, B1 (`fix-acesso`) | Corrigidos e testados (`docs/fix-acesso.md`); migration `20261030000000_fix_acesso_storage_pedido_historico.sql` **não aplicada**: precisa do OK do João. Sem xfail restante |

## Sobras da revisão de segurança (30/10/2026)

- Baixos B3 (erro do banco sem uuid) e B7 (cartão com captura e 3DS explícitos) corrigidos com teste; B8 ganhou o job
  `pip-audit` no CI; B2 (colunas internas do dinheiro) está pronto em migration **não aplicada** (`20261030140000_b2_grants_por_coluna.sql`).
- Nenhum `xfail` restante. Lista completa e estado de cada item: `docs/sobras-seguranca.md`.
- Para provar com Supabase e Stripe reais: `docs/roteiro-testes-reais.md` e os scripts `harness/teste_real_*.py`
  (isolamento entre dois usuários, webhook assinado e reenvio, `EXCLUDE` das faixas). Ainda **não** foram rodados contra o real.

