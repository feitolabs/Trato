# Divergências entre o app, `docs/api-rotas.md` e o backend

Conferido em 30/10/2026 contra `backend/src/trato/api/`. O backend **não foi editado**: cada item
abaixo é um pedido para a sessão do backend (ou uma limitação conhecida do app). Os testes de
contrato do app estão em `app/test/dados/contrato_api_test.dart`.

## Doc × código

| # | O que a doc diz | O que o código/uso mostra | Efeito no app |
|---|---|---|---|
| 1 | `docs/api-rotas.md` não lista as rotas de mensagens, notificações, upload, verificação, cadastro e perfil público | Existem em `rotas_app.py`, `rotas_upload.py` e `rotas_profissional_cadastro.py` | O app usa as rotas do código. Atualizar a doc. |
| 2 | `docs/app-camera-gps.md` propunha `POST /v1/arquivos/url-envio` | A rota real é `POST /v1/uploads` → `PUT url_envio` → `POST /v1/uploads/{id}/concluir` | **Corrigido no app** (`ServicoUploadApi`). Atualizar `app-camera-gps.md`. |
| 3 | Pagamento: `GET /v1/pedidos/{id}/pagamento` (valor e meios) e `GET /v1/contratos/{id}/pagamento` (estado) | Duas rotas para a mesma coisa, com formatos diferentes | O app usa a de pedido para o valor e os meios antes da cobrança e a de contrato para consultar `pago`. |

## O app manda, o backend recusa (ou vai recusar)

| # | Problema | Efeito | Pedido ao backend |
|---|---|---|---|
| 4 | `offline_capturada_em` dentro de `prova` (check-in/out reenviado) não existe no backend e `CheckInIn`/`CheckOutIn` usam `extra="forbid"` | Reenvio offline → 422 → o app trata como recusa e **tira da fila** | Aceitar o campo, ou o app deixa de mandar (decidir) |
| 5 | `nota-material` pede `foto_storage_path` (caminho no bucket), mas `POST /v1/uploads/{id}/concluir` de destino `nota_material` devolve só `midia_id`, sem caminho | O app não tem como saber o caminho da foto. Hoje manda o id que recebeu; o backend só valida formato (sem `..`, sem URL), então aceita um valor que não aponta para a foto | Aceitar `midia_id` em vez de caminho, ou devolver `caminho` no `concluir` |
| 6 | Verificação: `POST /v1/profissional/verificacao` espera `upload_id` quando o serviço de upload está ligado; sem ele, `storage_path` | O app manda `upload_id` (caminho feliz). Sem o serviço de upload, falha | Documentar que o upload é obrigatório |
| 7 | Foto de portfólio não tem `destino` em `DESTINOS` (`uploads/servico.py`) | `FinalidadeArquivo.portfolio` devolve "função indisponível" | Criar o destino `portfolio` |

## Faltam rotas (o app não consegue ligar)

| # | Falta | Efeito no app |
|---|---|---|
| 8 | Marcar notificação como lida | Fica sem efeito no servidor |
| 9 | Preferências de notificação e **registro do token de push** | Não implementado no app (sem rota, qualquer código seria inventado) |
| 10 | Busca de profissionais por serviço | A aba Buscar continua com dados de exemplo |
| 11 | Perfil público: `GET /v1/profissionais/{id}` existe, mas o app abre o perfil pelo **nome** (que vem da busca de exemplo) e o modelo da tela exige "no Trato desde" e cidade em texto, que a API não devolve | Perfil público continua demonstração |
| 12 | Catálogo de categorias e cidades (`categoria_id`, `cidade_id` do cadastro) | O cadastro do profissional continua demonstração: sem ids reais não dá para enviar `POST /v1/profissional/cadastro` |
| 13 | Lista de conversas (aba Mensagens) | Demonstração. O chat do pedido é real |
| 14 | Pedido: título, descrição, faixa de preço e serviços em `POST /v1/pedidos` | O app só abre o pedido; os campos do formulário não são enviados |
| 15 | Orçamento: selo de verificação, nota e total de serviços do profissional; limite de orçamentos e tempo restante da janela | Mostra "—" e esconde o que não vem |
| 16 | Pedido aberto: distância, quantos já orçaram, endereço aproximado | A tela esconde esses campos (`null`) |
| 17 | `taxa` em % na resposta de `POST /v1/orcamentos/resumo` | A calculadora mostra "Taxa Trato" sem o percentual (o app não calcula) |
| 18 | Carteira do profissional na Início (a rota é só extrato, D15) | Os valores da Início ficam em R$ 0 |
| 19 | Gorjeta na avaliação | O app recusa com aviso em vez de ignorar |
| 20 | Detalhe de pedido aberto (`GET /v1/profissional/pedidos-abertos/{id}`) | O detalhe sai da própria lista |
| 21 | Conversa do cliente antes de contratar exige `?profissional_id=` | O app não manda; antes do aceite o chat do cliente responde 422 "Diga com qual profissional…" |
| 22 | Mensagens rápidas e "cliente ausente" do check-in | Seguem "indisponível" |

## Limites do backend que aparecem no app

- `POST /v1/contratos/{id}/cobranca` responde `503` em modo `postgres` (cobrança só em memória): o app
  mostra o erro do servidor.
- Aprovar aditivo cria uma cobrança `aguardando_confirmacao`, mas o app **ainda não tem a tela de
  pagar o aditivo**: a aprovação funciona, o pagamento do aditivo não.
- Migrations `pedido_recusas` e `profissional_disponibilidade_portfolio_uploads` não aplicadas: recusar
  pedido responde erro em modo `postgres`.
