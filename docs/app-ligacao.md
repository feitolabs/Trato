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
| Orçamentos recebidos / detalhe | Fake (rota pronta no backend) | `GET /v1/pedidos/{id}/orcamentos` já existe (ver "Rotas novas"). O **aceite** já está implementado (`.../acoes/aceitar_orcamento`, só manda o id) mas só vale quando a lista vier da API. |
| Pagamento | Fake (valores prontos no backend) | `GET /v1/pedidos/{id}/pagamento` existe. `POST .../cobranca` existe, mas só com o serviço de pagamento ligado (ver abaixo). |
| Aguardando confirmação do pagamento | Fake (consulta pronta) | A tela consulta o status a cada 3 s e só avança quando o **backend** diz pago. A consulta pela API (estado do pedido) está implementada e testada. O app nunca mostra "pago" por conta própria (D14/D15). |
| Pedido em execução (linha do tempo, código de início) | **API** | `GET /v1/pedidos/{id}` e `/eventos`. Fotos do check-in ainda não vêm da API. |
| Conclusão (código de conclusão) | **API** | Valores vêm de `GET .../saldo`. |
| Confirmar serviço | **API** | `acoes/confirmar_conclusao`. |
| Avaliação | **API** (valores) / envio: rota pronta no backend | `POST .../avaliacao` existe; ligar o envio no app. |
| Relatar problema | **API** | `POST .../disputa`. O valor congelado vem do saldo do backend. Lista de motivos e de soluções é texto de tela. |
| Garantia / Pedir retrabalho | Retrabalho: **API**. Garantia: **sem rota** | `POST .../retrabalho` existe. `GET .../garantia` não existe. |
| Chat | Fake (rotas prontas no backend) | `GET/POST /v1/pedidos/{id}/mensagens` existem. |
| Notificações | Fake | Tela nova e simples (Perfil, Notificações). `GET /v1/notificacoes` existe no backend (ligar no app). |
| Perfil | Fake (rota pronta no backend) | `GET /v1/me` existe. |
| Profissional: início / pedidos abertos / detalhe / recusar | Fake | `GET /v1/profissional/pedidos-abertos` existe no backend (ligar no app). Recusar é local: não há rota. |
| Profissional: calculadora (taxa e líquido) | Fake | `POST /v1/orcamentos/resumo` existe no backend (ligar no app). A tela **não calcula**; no fake a taxa de 7,5% é só de demonstração. |
| Profissional: check-in | Fake (envio pronto) | `acoes/fazer_check_in` e `fazer_check_out` estão implementados e testados. Falta câmera, GPS e envio da foto no aparelho. |
| Profissional: Carteira | **API**, como **extrato** (D15) | `GET /v1/extrato`. Sem saldo próprio, sem botão de saque. |

## O que ainda é fake e por quê

- **Pagamento real**: depende do parceiro de pagamento em modo teste (chaves de teste e webhook assinado) e da rota de cobrança. Nada de efeito real sem o OK do João.
- **SMS, Google e Apple**: login e confirmação de celular são da sessão `auth-login` (D14).
- **Verificação do profissional** (documento, selfie): rota pronta no backend (`POST /v1/profissional/verificacao`, só referências dos arquivos); falta o envio do arquivo por URL assinada e a tela ligada.
- **Câmera e GPS**: sem os pacotes e permissões ligados no aparelho.
- **Taxa e líquido**: só o backend calcula. A rota `POST /v1/orcamentos/resumo` já existe; até o app ser ligado a ela, a calculadora usa o fake de demonstração.

## Rotas novas (pendências da fase 4, backend pronto)

O backend ganhou as rotas abaixo (`api/rotas_app.py`, testes em `tests/api/test_api_app.py` e, contra o Postgres local, `tests/integracao/test_rotas_app_postgres.py`). Passam de **Fake** para **API** quando o app trocar a classe da área em `repositorios_trato.dart` (a sessão do app cuida disso). Todas exigem login; papel errado dá 403 e pedido de outra pessoa dá 404.

| Rota | Quem | Devolve |
|------|------|---------|
| `GET /v1/pedidos/{id}/orcamentos` | cliente dono / equipe (todos); profissional (só o seu, em pedido aberto) | Lista do mais barato ao mais caro: `id`, `profissional_id`, `profissional_nome`, `versao`, `valor_centavos`, `prazo_execucao_dias`, `garantia_dias`, `observacoes`, `enviado_em`, `aceito`. |
| `GET /v1/pedidos/{id}/pagamento` | cliente dono / equipe | `valor_centavos` (contrato), `pago_centavos` (ledger), `pagamento_confirmado`, `meios_disponiveis` (`pix`, `cartao`), `cobranca_pendente_id`. Não mostra taxa. |
| `POST /v1/pedidos/{id}/cobranca` | cliente | Já existia (`rotas_pagamento.py`). **Não está ligada na API de produção**: só existe quando o serviço de pagamento é instalado (`instalar_pagamento`), o que exige o provedor em modo teste, que o João ainda não liberou, e cobranças gravadas no banco (hoje em memória). |
| `GET/POST /v1/pedidos/{id}/mensagens` | cliente, profissional (POST); equipe só lê | Mensagens com `minha`, `texto`, `mascarada`. Antes do contrato, e-mail e telefone saem ocultos. O cliente escolhe a conversa com `?profissional_id=` (sem ele vale o contratado). |
| `GET /v1/notificacoes?nao_lidas=` | cliente, profissional | `id`, `tipo`, `titulo`, `corpo`, `dados`, `criada_em`, `lida`. |
| `GET /v1/me` | qualquer login | `id`, `nome`, `papel`, `status`, `nivel_verificacao`, `nota_publica`, `servicos_concluidos`. Sem documento, telefone ou e-mail. |
| `GET /v1/profissional/pedidos-abertos` | profissional | Pedidos abertos na categoria e cidade dele (sem endereço exato). |
| `POST /v1/orcamentos/resumo` `{valor_centavos}` | profissional | `valor_centavos`, `taxa_centavos`, `liquido_centavos`. A taxa vem da configuração vigente; sem ela, 503. |
| `POST/GET /v1/profissional/verificacao` | cliente em cadastro / profissional | Envio de **referências** (`tipo` + `storage_path` no bucket privado), `consentimento_lgpd` obrigatório, frente do documento e selfie obrigatórias. Devolve só os tipos e o status. Uma verificação em análise por vez (409). |
| `POST /v1/pedidos/{id}/avaliacao` | cliente ou profissional do pedido | Nota 1 a 5, comentário e etiquetas; só depois de concluído e uma vez por lado (409). |

Limites desta entrega (no modo Postgres):

- **Avaliações ficam em memória**: a tabela `avaliacoes` é da F3.6, que ainda não foi aplicada (como ledger, disputas e garantias). Reiniciar a API perde as avaliações.
- **Pagamento (cobrança)** continua sem provedor ligado na API real (acima).
- **Notificações**: a rota só lê; quem cria a notificação (eventos do pedido) ainda não foi ligado.
- **Recusar pedido** (profissional) e **marcar notificação/mensagem como lida** não têm rota.
- **Garantia** (`GET .../garantia`) segue sem rota.

## Como ligar uma área nova

1. Quando a rota existir no backend, confira a classe `...Api` da área (o comentário "Sem rota no backend" diz a rota esperada) e ajuste ao formato real.
2. Em `repositorios_trato.dart`, troque o fake pelo `...Api` no construtor `RepositoriosTrato.api`.
3. Escreva o teste com `MockClient` em `app/test/dados/`.

## Testes

- `app/test/dados/dados_api_test.dart`: cliente HTTP e repositórios API com cliente simulado (cabeçalho, erros, rotas, corpos enviados).
- `app/test/dados/fluxo_ligado_test.dart`: telas ligadas com repositórios fake (lista, vazio, erro com nova tentativa, pagamento aguardando, código de início, Carteira sem saque).
