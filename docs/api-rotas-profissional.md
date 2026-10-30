# Rotas da API — profissional, verificação e upload

Seção da sessão `rotas-profissional-upload`. (As rotas de pedido, orçamento e cobrança ficam em
seção própria, da sessão `rotas-pedido-pagamento`.) Todas pedem `Authorization: Bearer <token>`.

## Cadastro e perfil do profissional

| Rota | Quem | O que faz |
|---|---|---|
| `POST /v1/profissional/cadastro` | cliente ou profissional | Cria o perfil (`em_analise`): categorias **ativas**, regiões (cidade ativa + bairro), disponibilidade semanal, bio, portfólio. 409 se já existe. |
| `GET /v1/profissional/perfil` | dono | Meu perfil + `nivel_verificacao_exigido` para as minhas categorias. |
| `PATCH /v1/profissional/perfil` | dono | Edita só os campos enviados. `status` e nível de verificação não se editam (422). |
| `GET /v1/profissionais/{id}` | qualquer logado | Perfil público + avaliações recebidas. Só profissional **aprovado** (senão 404). Nome abreviado ("João C."); sem documento, telefone, e-mail, endereço; a avaliação não mostra quem avaliou. |

Texto livre (bio, bairro, portfólio) passa pelo mascaramento de contato. Limites em `TRATO_PRO_*`.

## Verificação

`POST /v1/profissional/verificacao` (já existia em `rotas_app.py`; ficou mais rígida) e
`GET /v1/profissional/verificacao`.

- Corpo: `consentimento_lgpd` (obrigatório `true`), `nivel_solicitado`, `documentos` =
  `[{tipo, upload_id}]`. Com o serviço de upload ligado, **só** `upload_id` de um envio concluído
  em `/v1/uploads` (destino `verificacao`, mesmo dono, mesmo tipo) vale; o caminho cru do app é
  recusado. Sem o serviço (modo antigo/Postgres atual), vale `storage_path` do próprio dono.
- **Nível proporcional ao risco**: `TRATO_PRO_VERIFICACAO_NIVEL_POR_CATEGORIA` (slug ou id →
  `verificado`/`verificado_plus`); vale o mais exigente entre as categorias do profissional.
  Pedir nível menor → 422. Documentos obrigatórios por nível: `..._DOCUMENTOS_OBRIGATORIOS`
  (padrão: frente + selfie; `verificado_plus` acrescenta antecedentes).
- **LGPD**: grava `consentimento_lgpd_em`, `sha256` e `excluir_em` (hoje + `TRATO_PRO_VERIFICACAO_RETENCAO_DIAS`,
  padrão 365, prazo a confirmar — N10). A resposta traz `finalidade` e `retencao_dias` para o app mostrar.
- **Status** (`status_app`): `em_analise` (= `enviada`/`em_analise`), `aprovado` (= `aprovada`),
  `pendente` com `motivo` (= `recusada` + `motivo_recusa`). Bate com a fila da equipe em
  `api/admin/rotas_verificacoes.py` (`enviada, em_analise, aprovada, recusada`); nada duplicado.
- Documento **nunca volta ao dono** (nem caminho, nem link). A equipe de cadastro o vê por URL
  assinada curta e auditada (`docs/api-admin.md`).

## Upload seguro

1. `POST /v1/uploads` — `{destino, nome_arquivo, content_type, tamanho_bytes, pedido_id?, tipo_documento?}`
   → `{upload_id, url_envio, metodo, expira_em_segundos}`. Valida destino, tipo e tamanho (regras
   `TRATO_SEG_UPLOADS`), nome seguro e **autorização**: destinos de pedido exigem ser parte do pedido
   (senão 404; cliente em destino do profissional → 403); `checkin`, `checkout`, `nota_material`,
   `durante`, `depois` só do profissional; `pedido` só do cliente. Caminho = `<pedido_id>/<uuid>.ext`
   (pedido), `<usuario_id>/<uuid>.ext` (avatar) ou `<usuario_id>/pendente/<uuid>.ext` (verificação).
2. O app envia o arquivo à `url_envio` (bucket privado; sem policy de escrita para o app).
3. `POST /v1/uploads/{id}/concluir` — o backend **revalida**: arquivo existe (409 se não), prazo
   (`TRATO_UP_SOLICITACAO_VALIDADE_SEGUNDOS`, 410), tamanho não maior que o informado, tipo REAL pelo
   conteúdo (arquivo `.jpg` executável → 422 e o arquivo é apagado), remove EXIF/GPS/texto embutido de
   JPEG/PNG/WebP, calcula SHA-256, grava o arquivo limpo e registra. Idempotente. Outro usuário → 404.

| Destino | Bucket | Registro |
|---|---|---|
| `pedido, antes, durante, depois, checkin, checkout, nota_material, disputa, retrabalho` | `pedido-midias` | `midias` (devolve `midia_id`) |
| `chat` | `chat-anexos` | `midias` |
| `avatar` | `avatar` | (`usuarios.foto_path`: ligação pendente) |
| `verificacao` | `verificacao` | `verificacao_documentos` (sem devolver nada ao dono) |

Armazenamento: interface `ArmazenamentoArquivos` (`trato/uploads/armazenamento.py`). Testes usam
`ArmazenamentoFake`. O adaptador `ArmazenamentoSupabase` só liga se `SUPABASE_URL` e a chave de serviço
existirem; sem nenhum, as rotas respondem 503.

## Check-in / check-out

`POST /v1/pedidos/{id}/acoes/fazer_check_in|fazer_check_out` (já existiam). Com o upload ligado,
o servidor passa a:

- exigir que `foto.arquivo_id` seja o `midia_id` de uma mídia **registrada**, deste pedido, enviada por
  quem faz a ação, com a finalidade certa (`checkin`/`checkout`) — senão 422;
- **ignorar o horário da foto vindo do app**: usa a hora em que o servidor recebeu o arquivo;
- calcular a **distância** (haversine) entre `localizacao` e o local do pedido; acima de
  `TRATO_UP_CHECKIN_DISTANCIA_MAX_M` (padrão 500 m) → 422. O app nunca manda distância.

## Pendências (ver `harness/PENDENCIAS.md`)

- Adaptadores **Postgres** para perfil/catálogo, solicitações de upload e `midias` (hoje em memória;
  sem eles ligados, `/v1/profissional/cadastro` e `/v1/uploads` respondem 503). Migration preparada e
  **não aplicada**: `supabase/migrations/20261030130000_profissional_disponibilidade_portfolio_uploads.sql`
  (rollback em `supabase/rollback/`). PRECISO DO SEU OK para aplicar.
- Local do pedido para a distância do check-in: em produção deve vir do endereço exato do pedido
  (`ServicoUploads.local_do_pedido`); sem ele a distância não é checada.
- Foto de portfólio e `usuarios.foto_path` do avatar (bucket de portfólio não existe).
- Atribuição automática de `perfis_profissional.nivel_verificacao`/`status` ao aprovar na fila admin.
