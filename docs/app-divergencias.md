# Divergências entre o app, `docs/api-rotas.md` e o backend

Conferido em 30/10/2026 contra `backend/src/trato/api/`. A sessão `backend-divergencias` fechou o
que dava para fechar no backend (código, testes em memória e em Postgres local, exemplos em
`docs/api-rotas.md`, que é o contrato do app). Os testes de contrato do app estão em
`app/test/dados/contrato_api_test.dart`.

Legenda do **Estado**: **Resolvido** = backend e doc prontos, o app já pode ligar; **Já existia** =
a rota estava no código, só faltava na doc (agora está); **Parcial** = parte feita, o resto na seção
"Resolução"; **Aberto** = depende de decisão ou de outra tarefa (motivo e próximo passo abaixo).

## Doc × código

| # | O que a doc dizia | O que o código/uso mostra | Estado |
|---|---|---|---|
| 1 | `docs/api-rotas.md` não listava mensagens, notificações, upload, verificação, cadastro e perfil público | Existem em `rotas_app.py`, `rotas_upload.py` e `rotas_profissional_cadastro.py` | **Resolvido.** Todas as rotas têm tabela e exemplo em `docs/api-rotas.md` |
| 2 | `docs/app-camera-gps.md` propunha `POST /v1/arquivos/url-envio` | A rota real é `POST /v1/uploads` → `PUT url_envio` → `POST /v1/uploads/{id}/concluir` | **Resolvido.** App corrigido (`ServicoUploadApi`); `app-camera-gps.md` já marca a proposta como antiga; fluxo na seção "Upload" de `api-rotas.md` |
| 3 | Pagamento: duas rotas (`/pedidos/{id}/pagamento` e `/contratos/{id}/pagamento`) | Formatos diferentes | **Resolvido.** São duas coisas: valor e meios **antes** de cobrar × estado do pagamento **depois**. Seção "Duas rotas de pagamento" |

## O app manda, o backend recusa

| # | Problema | Estado e decisão |
|---|---|---|
| 4 | `offline_capturada_em` dentro de `prova` (reenvio offline) era 422 | **Resolvido.** Aceito só em `fazer_check_in`/`fazer_check_out`, ISO com fuso. A hora oficial continua a do servidor; o campo é evidência, vai para a auditoria (`evidencia_offline`) e nunca decide nada. Janela em `TRATO_UP_OFFLINE_JANELA_MAX_HORAS` (72 h) e `TRATO_UP_OFFLINE_TOLERANCIA_FUTURO_S` (300 s); fora dela, `422` |
| 5 | `nota-material` pedia caminho, mas o `concluir` devolve só `midia_id` | **Resolvido.** Aceita `midia_id` (ou o caminho, um dos dois). O backend confere que a mídia é do pedido, de quem envia e de finalidade `nota_material`, e guarda o caminho real |
| 6 | Verificação com `upload_id` falha sem o serviço de upload | **Resolvido (documentado).** O upload é obrigatório na verificação; sem o serviço ligado o upload responde `503` e o app não verifica. O app já manda `upload_id` |
| 7 | Sem destino `portfolio` em `DESTINOS` | **Resolvido.** Destino `portfolio`: só profissional, só imagem, limite em `TRATO_SEG_UPLOADS` (8 MB), EXIF/GPS removidos, pasta `<dono>/portfolio/` do bucket `avatar`. Migration NOVA (não aplicada) para a CHECK de `upload_solicitacoes`, ver "Resolução" |

## Faltavam rotas

| # | Falta | Estado |
|---|---|---|
| 8 | Marcar notificação como lida | **Já existia** (`POST /v1/notificacoes/{id}/lida`); agora na doc |
| 9 | Preferências e token de push | **Resolvido.** Preferências (`GET/PUT /v1/notificacoes/preferencias`) e `POST /v1/dispositivos` já existiam; **novo** `DELETE /v1/dispositivos` (só o dono; idempotente), em memória e em Postgres (`dispositivos_push`, já aplicada) |
| 10 | Busca de profissionais por serviço | **Resolvido.** `GET /v1/profissionais?servico=&categoria_id=&cidade_id=&bairro=&pagina=&limite=`: só aprovados, sem dado pessoal, paginada |
| 11 | Perfil público abre por nome; falta "no Trato desde" e cidade em texto | **Resolvido no backend.** A busca devolve o `id`; `GET /v1/profissionais/{id}` agora traz `no_trato_desde` e `cidades` (texto). Falta o app abrir pelo `id` |
| 12 | Catálogo de categorias e cidades | **Resolvido.** `GET /v1/catalogo/categorias` e `/v1/catalogo/cidades` (só ativas; exige login). Em Postgres o cadastro agora grava no banco (antes respondia `503`) |
| 13 | Lista de conversas | **Já existia** (`GET /v1/conversas`: última mensagem e não lidas); agora na doc |

## Outros itens do app (14 a 22)

| # | Falta | Estado |
|---|---|---|
| 14 | Título, descrição, faixa de preço e serviços em `POST /v1/pedidos` | **Já existia no backend** (`AbrirPedidoIn` aceita `titulo`, `descricao`, faixa, urgência, respostas). O app precisa enviar |
| 15 | Orçamento: selo, nota e total de serviços do profissional; limite de orçamentos e tempo restante | **Parcial.** Selo, nota e total de serviços vêm em `GET /v1/pedidos/{id}/orcamentos`. Limite e janela: **Aberto** |
| 16 | Pedido aberto: distância, quantos já orçaram, endereço aproximado | **Parcial.** `orcamentos_recebidos` e `ja_orcou` no detalhe. Distância e endereço aproximado: **Aberto** |
| 17 | `taxa` em % no resumo | **Resolvido.** `taxa_bps` e `taxa_percentual` (efetiva) em `POST /v1/orcamentos/resumo` |
| 18 | Carteira do profissional na Início | **Aberto** |
| 19 | Gorjeta na avaliação | **Aberto** |
| 20 | Detalhe de pedido aberto | **Resolvido.** `GET /v1/profissional/pedidos-abertos/{id}` |
| 21 | Conversa do cliente antes de contratar exige `?profissional_id=` | **Decidido: continua assim.** A conversa é de UM profissional; o app manda o id (vem do orçamento). Documentado |
| 22 | Mensagens rápidas e "cliente ausente" do check-in | **Aberto** |

Também fechado, da lista do app (`STATUS-MVP.md`, "Responder disputa e atender retrabalho"): o lado
do profissional. `POST /v1/pedidos/{id}/disputa/resposta` já existia; **novos**
`POST /v1/pedidos/{id}/retrabalho/atender` (`aceitar`, `iniciar`, `resolver`) e
`GET /v1/pedidos/{id}/retrabalho`.

## Resolução

O que **não** deu para fechar, o motivo e o próximo passo:

- **Migration APLICADA em 30/10/2026:** `supabase/migrations/20261030140000_upload_destino_portfolio.sql`
  (rollback em `supabase/rollback/upload_destino_portfolio_rollback.sql`; testada nos dois sentidos no
  Postgres descartável). Só importa quando as solicitações de upload forem gravadas em
  `upload_solicitacoes`: hoje o `ServicoUploads` guarda solicitações e mídias **em memória**, então
  `midia_id` e `upload_id` se perdem se o servidor reiniciar entre o `concluir` e o uso. Próximo passo:
  adaptador Postgres de uploads (`upload_solicitacoes` + `midias` + `verificacao_documentos`) e, junto,
  aplicar essa migration. Precisa do OK do João (formato `PRECISO DO SEU OK`).
- **Foto de portfólio sem vínculo com o perfil (#7):** o upload funciona, mas `portfolio[]` do perfil só
  guarda `titulo` e `descricao`. Para exibir a foto, o item precisa de `upload_id`/caminho. Próximo passo:
  decidir o formato (a foto vai no item do portfólio) e estender `PortfolioIO`; não exige migration
  (`portfolio` é jsonb).
- **#15 limite de orçamentos e tempo restante:** não existe regra nem parâmetro de "máximo de orçamentos
  por pedido". Decidir o número (vai em `config_parametros`, nunca fixo) antes de expor `limite` e
  `restam`. A janela de recebimento já existe (`receber_orcamentos` nos prazos do pedido): o tempo
  restante pode sair dela quando o João confirmar que é isso que o app mostra.
- **#16 distância e endereço aproximado:** depende de decisão de privacidade (quão aproximado, em
  metros ou só bairro) e da posição do profissional. O pedido só guarda `local_aprox_lat/lng`. Próximo
  passo: o João define a aproximação; o backend calcula a distância no servidor (nunca no app).
- **#18 carteira da Início:** pelo caminho A (D15) a carteira é extrato do que o parceiro liquida; a rota
  de extrato existe (`rotas_financeiro.py`), mas o somatório "a receber / recebido" depende da F3.5
  refeita para o caminho A. Próximo passo: refazer a F3.5 e então expor o resumo.
- **#19 gorjeta:** envolve dinheiro novo (cobrança extra, taxa, repasse) e não está na V2. O app deve
  continuar recusando com aviso até haver decisão do João.
- **#22 mensagens rápidas e "cliente ausente":** são regras de produto (texto fixo e consequência da
  ausência no prazo/dinheiro). Próximo passo: o João define os textos e o efeito; o "ausente" usaria a
  ação do sistema `registrar_ausencia`, que hoje não é chamada pelo app.
- **Ainda dependem de OK do João desde antes** (ver `api-rotas.md`): migration `pedido_recusas`, cobrança
  em Postgres (`503` no app real) e cobrança do aditivo.

## Limites do backend que aparecem no app

- `POST /v1/contratos/{id}/cobranca` responde `503` em modo `postgres` (cobrança só em memória): o app
  mostra o erro do servidor.
- Aprovar aditivo cria uma cobrança `aguardando_confirmacao`, e agora o app direciona o
  cliente diretamente para a tela de pagamento (`_pagamento(pedidoId)`).
- Migrations `pedido_recusas` e `profissional_disponibilidade_portfolio_uploads`: a segunda já está
  aplicada; recusar pedido segue dependendo da primeira em modo `postgres`.
