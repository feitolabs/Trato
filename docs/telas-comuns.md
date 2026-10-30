# Telas comuns (F5.12, F5.13, F5.4)

Telas usadas por cliente e profissional. Cada uma recebe um **serviço por interface** (com fake
ao lado) e avisa as ações por **callback**. Nenhuma regra de dinheiro. Estados: carregando, vazio,
erro (com "Tentar de novo"). Testes: `app/test/telas_comuns_test.dart`; goldens em 3 tamanhos
(320, 390, 768): `app/test/golden/telas_comuns_golden_test.dart`.

Peças compartilhadas: `app/lib/telas/comuns/estados.dart` (`CarregadorTela`, `EstadoCarregando`,
`EstadoVazio`, `EstadoErro`, `MolduraTelaComum`).

## Telas e callbacks a ligar em `rotas.dart`

| Tela | Arquivo | Serviço (interface) | Callbacks | Protótipo |
|---|---|---|---|---|
| Notificações | `notificacoes/notificacoes_tela.dart` | `ServicoNotificacoes` | `aoAbrirDestino(Notificacao)` — usar `tipo` e `destinoId` para abrir pedido, orçamento ou conversa | Sem protótipo |
| Mensagens (lista, aba do cliente) | `mensagens/mensagens_tela.dart` | `ServicoMensagens` | `aoAbrirConversa(ConversaResumo)` — abrir `ChatPedidoTela` do `pedidoId` | Sem protótipo da lista (o chat é a tela 17) |
| Central de privacidade (LGPD) | `lgpd/central_privacidade_tela.dart` | `ServicoPrivacidade` | `aoAbrirTermos`, `aoContaExcluida` (fazer logout e voltar ao início) | Sem protótipo |
| Excluir conta (2 passos) | `lgpd/excluir_conta_tela.dart` (aberta pela central) | `ServicoPrivacidade` | `aoContaExcluida` | Sem protótipo |
| Ajuda | `ajuda/ajuda_tela.dart` | `ServicoAjuda` | `aoFalarComSuporte`, `aoRelatarProblema` (ligar à `RelatarProblemaTela` ou ao canal de suporte) | Sem protótipo |
| Busca de profissional/serviço | `busca/busca_profissionais_tela.dart` | `ServicoBusca` | `aoAbrirProfissional(Profissional)` — abrir `PerfilProfissionalTela` | Parte da tela 9 (`BuscarTela`, já existente, com filtros e mapa); esta versão com serviço e estados é nova |

## Itens do menu do Perfil (tela 22)

`PerfilClienteTela` já avisa `aoTocarItem(AcaoPerfil)`. Destinos para ligar:

| `AcaoPerfil` | Destino |
|---|---|
| `notificacoes` | `NotificacoesTela` |
| `meusDados` | `CentralPrivacidadeTela` |
| `centralAjuda` | `AjudaTela` |

`termos` segue com o texto legal (ainda "Em breve"). Os demais itens não fazem parte desta tarefa.

## Já existia (não recriado)

- Início do cliente com categorias: `cliente/inicio_tela.dart`.
- Perfil público do profissional visto pelo cliente: `cliente/perfil_profissional_tela.dart`
  (só abre quando `Profissional.detalhe` existe; "Favoritar" ainda é "Em breve").

## Regras de texto

Sem "garantia total", "escrow" nem "24/7"; suporte descrito como equipe que responde por
mensagem. A exclusão de conta explica o que é retido por obrigação legal, sem citar prazos
(o backend decide). Nenhum texto afirma "pago" antes do provedor (D15).

## Pendências

- Os serviços reais (API) ainda não existem; só os fakes (`servico_fake.dart` em cada pasta).
- O texto das perguntas frequentes e dos consentimentos é provisório.
