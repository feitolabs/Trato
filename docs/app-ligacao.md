# Ligação do app à API

O app Flutter fala com a API FastAPI (`backend/src/trato/api/`) por uma camada própria, `app/lib/dados/`. As telas **não conhecem a rede**: recebem os dados prontos de quem as liga (`app/lib/telas/fluxo/rotas.dart`).

Regra de ouro (CLAUDE.md): nenhuma regra de dinheiro roda no app. O app **pede e mostra**; o backend decide. Valores em centavos inteiros.

## Modos

| Modo | Como ligar | O que faz |
|------|------------|-----------|
| `demo` (padrão) | nada, ou `--dart-define=TRATO_MODO=demo` | Dados de exemplo das telas. Sem rede. Tudo funciona sem backend. |
| `api` | `--dart-define=TRATO_MODO=api --dart-define=TRATO_API_URL=https://...` | Usa a API onde a rota já existe; o resto continua em demonstração (tabela abaixo). |

`TRATO_MODO=api` sem `TRATO_API_URL` cai em `demo`: melhor abrir o app do que quebrar.

```bash
flutter run --dart-define=TRATO_MODO=api --dart-define=TRATO_API_URL=http://10.0.2.2:8000
```

(`10.0.2.2` é o computador, visto de dentro do emulador Android.)

## Variáveis

| Variável | Onde | Para quê |
|----------|------|----------|
| `TRATO_MODO` | `--dart-define` | `demo` ou `api`. |
| `TRATO_API_URL` | `--dart-define` | Endereço base da API. |

Só os **nomes** estão no `.env.example`. Nunca coloque token, senha ou chave no código. O token da sessão fica em `SessaoTrato` (`app/lib/dados/sessao.dart`), em memória; quem faz o login chama `sessaoTrato.entrar(token)`, e o cliente HTTP manda `Authorization: Bearer ...`.

## Camadas

- `config.dart`: lê o modo e a URL.
- `cliente_api.dart`: HTTP (`package:http`), URL base, Authorization, tempo limite de 15 s e erros em português simples (sem internet, sessão expirada, erro do servidor; para 4xx mostra o motivo que o backend explicou).
- `modelos_api.dart`: respostas da API escritas à mão a partir de `api/modelos.py`.
- `repositorios.dart`: **interfaces** por área (pedidos, orçamentos, pagamento, chat, notificações, perfil, profissional).
- `repositorios_api.dart`: implementação que fala com a API. `servicos_api.dart`: aditivo, nota de materiais e verificação.
- `repositorios_fake.dart`: implementação de demonstração (os dados de exemplo das telas).
- `repositorios_trato.dart`: escolhe API ou fake por área, conforme o modo.
- `carregador.dart`: widget que dá a toda tela ligada os estados **carregando**, **erro** (com "Tentar de novo") e **vazio**.

## O que está ligado, tela por tela

Legenda: **API** = chama a API real no modo `api`. **Demo** = dados de exemplo, mesmo no modo `api`.
O estado completo (com observações) está em `docs/STATUS-MVP.md`; o que o backend não entrega, em `docs/app-divergencias.md`.

| Tela | Modo `api` | Rotas |
|------|-----------|-------|
| Novo pedido | **API** | `POST /v1/pedidos` (só abre; serviços, descrição e faixa ainda não têm campo) |
| Seus pedidos | **API** | `GET /v1/pedidos` |
| Orçamentos / detalhe | **API** | `GET /v1/pedidos/{id}/orcamentos`, `GET /v1/orcamentos/{id}`, aceite em `acoes/aceitar_orcamento` |
| Pagamento | **API** | `GET /v1/pedidos/{id}/pagamento`, `POST /v1/contratos/{id}/cobranca` |
| Aguardando confirmação | **API** | `GET /v1/contratos/{id}/pagamento` a cada 3 s até `pago: true`. O app nunca marca pago (D13) |
| Pedido em execução / conclusão / confirmar | **API** | `GET /v1/pedidos/{id}`, `/eventos`, `/saldo`, `acoes/confirmar_conclusao` |
| Avaliação | **API** | `POST /v1/contratos/{id}/avaliacao` |
| Relatar problema, retrabalho | **API** | `POST .../disputa`, `POST .../retrabalho` |
| Garantia | **API** | `GET /v1/contratos/{id}/garantia` |
| Aditivo, nota de materiais (cliente e profissional) | **API** | `/v1/contratos/{id}/aditivos...`, `/v1/contratos/{id}/notas-material` |
| Chat | **API** | `GET/POST /v1/pedidos/{id}/mensagens` |
| Notificações | **API** (lista) | `GET /v1/notificacoes` |
| Perfil do cliente | **API** | `GET/PATCH /v1/me` |
| Profissional: início, pedidos abertos, detalhe, recusar | **API** | `GET /v1/me`, `GET /v1/profissional/pedidos-abertos`, `POST /v1/pedidos/{id}/recusar` |
| Profissional: calculadora | **API** | `POST /v1/orcamentos/resumo` |
| Profissional: check-in / check-out | **API** | `POST /v1/uploads` (+ `PUT` + `concluir`), `acoes/fazer_check_in`, `acoes/fazer_check_out` |
| Profissional: verificação | **API** | `POST /v1/uploads` (destino `verificacao`), `POST/GET /v1/profissional/verificacao` |
| Profissional: Carteira | **API**, como **extrato** (D15) | `GET /v1/extrato` |
| Cadastro do profissional | Demo | falta catálogo de categorias e cidades |
| Busca e perfil público | Demo | falta rota de busca; perfil abre por nome |
| Lista de conversas, responder disputa (profissional) | Demo | faltam as rotas |
| Marcar notificação como lida, preferências, token de push | — | sem rota |

## Sessão e token

- `LigacaoSessao` leva o token do login para `SessaoTrato`; `ClienteApi` manda `Authorization: Bearer ...` em **toda** chamada (inclusive PATCH).
- 401: o cliente tenta renovar o token uma vez; se não renovar, limpa a sessão e abre o login por cima da tela.
- O primeiro login (e o app reaberto com sessão guardada) chama `GET /v1/me` (`aoEntrar` no `main.dart`), que cria o usuário no backend. Falha nessa chamada não derruba o login.
- Upload: `ServicoUploadApi` sempre tira EXIF/GPS antes de enviar; o `PUT` na URL assinada não leva o token da API.

## O que ainda é fake e por quê

- **Pagamento real**: o provedor é fake/teste no backend; nada de efeito real sem o OK do João.
- **SMS, Google e Apple**: login é da sessão `auth-login` (D14).
- **Cadastro, busca, perfil público, lista de conversas**: faltam rotas ou catálogo (`docs/app-divergencias.md`).
- **Câmera e GPS**: capturam no aparelho, mas não foram testados em aparelho real.

## Como ligar uma área nova

1. Crie a classe `...Api` conforme a rota (`repositorios_api.dart` ou `servicos_api.dart`).
2. Em `repositorios_trato.dart`, ponha-a no construtor `RepositoriosTrato.api`.
3. Escreva o teste de contrato com cliente HTTP simulado em `app/test/dados/contrato_api_test.dart`.

## Testes

- `app/test/dados/dados_api_test.dart`: cliente HTTP e repositórios API com cliente simulado (cabeçalho, erros, rotas, corpos enviados).
- `app/test/dados/contrato_api_test.dart`: **contrato** de cada repositório API (método, caminho, corpo, leitura da resposta, 401 e sem rede) com exemplos de `docs/api-rotas.md`.
- `app/test/dados/fluxo_completo_test.dart`: pedido → orçamento → aceite → pagamento aguardando → confirmado → execução → conclusão → avaliação, com um backend simulado.
- `app/test/dados/fluxo_ligado_test.dart`: telas ligadas com repositórios fake (lista, vazio, erro com nova tentativa, pagamento aguardando, código de início, Carteira sem saque).
