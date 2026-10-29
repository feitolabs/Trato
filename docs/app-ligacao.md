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
- `repositorios_api.dart`: implementação que fala com a API.
- `repositorios_fake.dart`: implementação de demonstração (os dados de exemplo das telas).
- `repositorios_trato.dart`: escolhe API ou fake por área, conforme o modo.
- `carregador.dart`: widget que dá a toda tela ligada os estados **carregando**, **erro** (com "Tentar de novo") e **vazio**.

## O que está ligado, tela por tela

Legenda: **API** = chama a API real no modo `api`. **Fake** = ainda usa dados de exemplo mesmo no modo `api`.

| Tela | Modo `api` | Observação |
|------|-----------|------------|
| Novo pedido | **API** | `POST /v1/pedidos`. O backend só abre o pedido; serviços, descrição e faixa de preço ainda não têm campo na API. |
| Seus pedidos | **API** | `GET /v1/pedidos`. O título é "Pedido #XXXX" porque a API ainda não devolve título nem nome do profissional. |
| Orçamentos recebidos / detalhe | Fake | Falta `GET /v1/pedidos/{id}/orcamentos`. O **aceite** já está implementado (`.../acoes/aceitar_orcamento`, só manda o id) mas só vale quando a lista vier da API. |
| Pagamento | Fake | Falta criar a cobrança no provedor em modo teste (`POST /v1/pedidos/{id}/cobranca`) e a rota de valores. |
| Aguardando confirmação do pagamento | Fake (consulta pronta) | A tela consulta o status a cada 3 s e só avança quando o **backend** diz pago. A consulta pela API (estado do pedido) está implementada e testada. O app nunca mostra "pago" por conta própria (D14/D15). |
| Pedido em execução (linha do tempo, código de início) | **API** | `GET /v1/pedidos/{id}` e `/eventos`. Fotos do check-in ainda não vêm da API. |
| Conclusão (código de conclusão) | **API** | Valores vêm de `GET .../saldo`. |
| Confirmar serviço | **API** | `acoes/confirmar_conclusao`. |
| Avaliação | **API** (valores) / sem rota para enviar | `POST .../avaliacao` não existe: o envio mostra "função ainda não disponível". |
| Relatar problema | **API** | `POST .../disputa`. O valor congelado vem do saldo do backend. Lista de motivos e de soluções é texto de tela. |
| Garantia / Pedir retrabalho | Retrabalho: **API**. Garantia: **sem rota** | `POST .../retrabalho` existe. `GET .../garantia` não existe. |
| Chat | Fake | Faltam `GET/POST /v1/pedidos/{id}/mensagens`. |
| Notificações | Fake | Tela nova e simples (Perfil, Notificações). Falta `GET /v1/notificacoes`. |
| Perfil | Fake | Falta `GET /v1/me`. |
| Profissional: início / pedidos abertos / detalhe / recusar | Fake | Faltam as rotas de pedidos abertos do profissional. |
| Profissional: calculadora (taxa e líquido) | Fake | Falta `POST /v1/orcamentos/resumo`. A tela **não calcula**; no fake a taxa de 7,5% é só de demonstração. |
| Profissional: check-in | Fake (envio pronto) | `acoes/fazer_check_in` e `fazer_check_out` estão implementados e testados. Falta câmera, GPS e envio da foto no aparelho. |
| Profissional: Carteira | **API**, como **extrato** (D15) | `GET /v1/extrato`. Sem saldo próprio, sem botão de saque. |

## O que ainda é fake e por quê

- **Pagamento real**: depende do parceiro de pagamento em modo teste (chaves de teste e webhook assinado) e da rota de cobrança. Nada de efeito real sem o OK do João.
- **SMS, Google e Apple**: login e confirmação de celular são da sessão `auth-login` (D14).
- **Verificação do profissional** (documento, selfie): sem rota ainda.
- **Câmera e GPS**: sem os pacotes e permissões ligados no aparelho.
- **Taxa e líquido**: só o backend calcula. Enquanto não houver `POST /v1/orcamentos/resumo`, a calculadora usa o fake de demonstração.

## Como ligar uma área nova

1. Quando a rota existir no backend, confira a classe `...Api` da área (o comentário "Sem rota no backend" diz a rota esperada) e ajuste ao formato real.
2. Em `repositorios_trato.dart`, troque o fake pelo `...Api` no construtor `RepositoriosTrato.api`.
3. Escreva o teste com `MockClient` em `app/test/dados/`.

## Testes

- `app/test/dados/dados_api_test.dart`: cliente HTTP e repositórios API com cliente simulado (cabeçalho, erros, rotas, corpos enviados).
- `app/test/dados/fluxo_ligado_test.dart`: telas ligadas com repositórios fake (lista, vazio, erro com nova tentativa, pagamento aguardando, código de início, Carteira sem saque).
