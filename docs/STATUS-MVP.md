# Status do MVP — tela por tela

Atualizado em 30/10/2026, depois de ligar o app às rotas novas. Divergências: `docs/app-divergencias.md`.

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
| Google, Apple, SMS | Depende do João | Chaves e provedor (P11). |
| Início, buscar, perfil do profissional | Demo | Sem rota de busca (#10) e o perfil público abre por nome (#11). |
| Busca com serviço (`busca/`) | Demo, ligada | É a aba Buscar do cliente (`RotasTrato.abaBuscar`), abre o perfil público. Filtros e mapa da tela antiga (`BuscarTela`) saíram da aba; a busca real depende do backend. |
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
| Mensagens (aba, lista de conversas) | Demo, sem protótipo | Falta rota da lista (`docs/app-divergencias.md` #13). |
| Notificações | API (lista) | `GET /v1/notificacoes`. Marcar como lida, preferências e token de push: sem rota (#8, #9). |
| Perfil do cliente | API | `GET /v1/me` (o primeiro login chama a rota e cria o usuário) e `PATCH /v1/me` no repositório; falta a tela de editar o nome. |
| Central de privacidade (LGPD) e excluir conta | Demo, sem protótipo | Texto de prazos a definir com o jurídico. Exclusão real depende do backend. |
| Ajuda | Demo, sem protótipo | Perguntas frequentes provisórias. |
| Perfil: notificações, privacidade, ajuda, usar como profissional, **Sair** | Ligados | Sair encerra o login, limpa o token e volta ao login sem histórico. |
| Perfil: dados pessoais, endereços, pagamento, favoritos, contatos, termos | Sem tela | Itens **removidos da lista** (não abrem mais "Em breve"); voltam quando a tela existir. |
| Perfil público do profissional | Demo | Ver #11. Sem perfil nos dados: aviso "Perfil indisponível". |
| Pedido em disputa/estado sem tela (cliente) | Aviso | Mostra aviso de que está em análise (antes "Em breve"). |
| SOS | Desligado | `kSosHabilitado = false` (D13). |

## Profissional

| Tela | Estado | Observação |
|---|---|---|
| Cadastro do profissional | Demo, sem protótipo | Falta o catálogo de categorias e cidades (#12). A foto sobe pela câmera real. |
| Verificação (documento e selfie) | API | Fotos por URL assinada (`POST /v1/uploads`, `PUT`, `concluir`) e `POST/GET /v1/profissional/verificacao`. Texto de retenção vem do backend quando já há verificação. Não testado em aparelho real. |
| Início, pedidos abertos, detalhe, recusar | API | `GET /v1/profissional/pedidos-abertos` (filtros no repositório), nome por `/v1/me`, recusa `POST /v1/pedidos/{id}/recusar` (precisa da migration `pedido_recusas`). Carteira da Início fica em zero (#18). |
| Filtros | Sem tela | Repositório pronto (`FiltroPedidosAbertos`); falta a tela. |
| Calculadora de orçamento | API | `POST /v1/orcamentos/resumo`: taxa e líquido do backend, nada calculado no app. Sem o percentual (#17). |
| Check-in e check-out | API (envio) | Câmera e GPS reais; foto por `POST /v1/uploads`; ação em `acoes/fazer_check_in`/`fazer_check_out`. Reenvio offline manda `offline_capturada_em`, que o backend recusa (#4). Não testado em aparelho real. |
| Enviar nota de materiais e criar aditivo | API | `POST /v1/contratos/{id}/notas-material` e `.../aditivos`. O caminho da foto da nota ainda não vem do upload (#5). |
| Responder disputa e atender retrabalho | Demo | Falta a rota do lado do profissional. |
| Carteira | API, como extrato | `GET /v1/extrato`. Sem saldo próprio e sem saque (D15). |
| Perfil público e avaliações recebidas | Demo, sem protótipo | Na aba Perfil da casca do profissional, com botão **Sair**. |
| Agenda, mensagens do profissional | Sem tela | "Em breve". |

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
| SMS | Escolha do provedor (P11) e hook no Supabase Auth |
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

