# Status do MVP — tela por tela

Atualizado em 29/10/2026, depois da rodada final de integração em `develop`.

Legenda do app:
- **API**: no modo `api` (`--dart-define=TRATO_MODO=api`) chama a API de verdade.
- **Demo**: só dados de exemplo, mesmo no modo `api` (a rota ou o serviço real ainda não existe).
- **Sem protótipo**: a tela segue o padrão visual das vizinhas, mas ninguém conferiu contra o PDF de design.

O app sempre abre em `demo`. Sem `TRATO_API_URL`, o modo `api` cai em `demo`. Detalhes: `docs/app-ligacao.md`.

## Cliente

| Tela | Estado | Observação |
|---|---|---|
| Splash, onboarding, escolha de perfil | Demo | Não precisam de API. |
| Login, criar conta, recuperar senha | Demo (serviço de teste) | `ServicoAuth` pronto; o `main.dart` troca para o Supabase quando há `SUPABASE_URL` e `SUPABASE_ANON_KEY`. O token do login ainda **não** é passado ao cliente HTTP (`SessaoTrato`), então a API real não recebe o usuário. Ver `docs/login-configuracao.md`. |
| Google, Apple, SMS | Depende do João | Chaves e provedor (P11). |
| Início, buscar, perfil do profissional | Demo | Categorias e profissionais de exemplo. |
| Busca com serviço (`busca/`) | Demo, ligada | É a aba Buscar do cliente (`RotasTrato.abaBuscar`), abre o perfil público. Filtros e mapa da tela antiga (`BuscarTela`) saíram da aba; a busca real depende do backend. |
| Novo pedido (tela 11) | API | `POST /v1/pedidos`. A API ainda não tem campos de serviços, descrição nem faixa de preço. |
| Seus pedidos | API | Título genérico ("Pedido #XXXX"): a API não devolve título nem nome do profissional. |
| Orçamentos recebidos e detalhe | Demo | Falta `GET /v1/pedidos/{id}/orcamentos`. O aceite já tem rota. |
| Pagamento e aguardando confirmação | Demo | Falta a rota de cobrança no provedor de teste. O app nunca mostra "pago" antes do backend (D13). |
| Pedido em execução, código de início | API | Fotos do check-in não vêm da API. |
| Aditivo e nota de materiais (lado do cliente) | Demo, **não ligadas** | `ver_nota_tela` e `responder_aditivo_tela` existem; falta ponto de entrada no pedido em execução. Sem protótipo. |
| Conclusão, confirmar serviço | API | Valores de `GET .../saldo`. |
| Avaliação | API (valores) | Não há rota para enviar; mostra "função ainda não disponível". |
| Relatar problema (disputa) | API | `POST .../disputa`. |
| Garantia e retrabalho | Retrabalho: API. Garantia: Demo | Falta `GET .../garantia`. |
| Chat do pedido | Demo | Faltam `GET/POST /v1/pedidos/{id}/mensagens`. |
| Mensagens (aba, lista de conversas) | Demo, sem protótipo | Abre o chat do pedido. Falta rota da lista. |
| Notificações | Demo, sem protótipo | Falta `GET /v1/notificacoes`. Marcar como lida é local. |
| Perfil do cliente | Demo | Falta `GET /v1/me`. |
| Central de privacidade (LGPD) e excluir conta | Demo, sem protótipo | Texto de prazos a definir com o jurídico. Exclusão real depende do backend. |
| Ajuda | Demo, sem protótipo | Perguntas frequentes provisórias. |
| Termos e demais itens do Perfil | Sem tela | Abrem "Em breve". |
| SOS | Desligado | `kSosHabilitado = false` (D13). |

## Profissional

| Tela | Estado | Observação |
|---|---|---|
| Cadastro do profissional | Demo, sem protótipo | A foto vem da câmera (só a referência; sem upload). Falta rota. |
| Verificação (documento e selfie) | Demo, sem protótipo | Sem rota; upload para o bucket `verificacao` por ligar (câmera já captura). Texto de retenção a definir com o jurídico. |
| Início, pedidos abertos, detalhe, recusar | Demo | Faltam as rotas de pedidos abertos. |
| Filtros | Sem tela | "Em breve". |
| Calculadora de orçamento | Demo | Taxa e líquido têm de vir do backend (`POST /v1/orcamentos/resumo` não existe). A taxa de 7,5% do fake é só demonstração. |
| Check-in e check-out | Demo (envio pronto) | `fazer_check_in` e `fazer_check_out` existem na API. Câmera e GPS do aparelho já capturam (`app/lib/dispositivo/`); o envio da foto e da posição ao backend falta. |
| Enviar nota de materiais e criar aditivo | Demo, ligadas | Ações do "pedido de hoje" (botão de check-in da Início). Cliente: links na tela do pedido em execução. Sem rota de nota/aditivo na API. |
| Responder disputa e atender retrabalho | Demo, ligadas pela notificação | Abertas pelo toque na notificação (tipos `disputa` e `retrabalho`). Falta a entrada pela lista de pedidos do profissional e a rota na API. |
| Carteira | API, como extrato | `GET /v1/extrato`. Sem saldo próprio e sem saque (D15). |
| Perfil público e avaliações recebidas | Demo, sem protótipo | Na aba Perfil da casca do profissional. |
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

1. ~~Token do Supabase Auth no `SessaoTrato`~~ feito (`LigacaoSessao`). ~~Pontos de entrada~~ feitos, menos disputa/retrabalho pela lista de pedidos do profissional.
3. Criar as rotas que faltam no backend (orçamentos, cobrança, mensagens, notificações, perfil, pedidos abertos, verificação).
4. Envio de fotos e posição ao backend (buckets por URL assinada): implementar `EnvioMidia` quando a rota existir. Câmera e GPS já capturam; textos de permissão em `AndroidManifest.xml` e `Info.plist`. Não testado em aparelho real.
5. Busca de textos proibidos (D13) no `verificar`.
