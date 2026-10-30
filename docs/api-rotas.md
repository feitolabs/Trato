# API: rotas do pedido, do orçamento e do pagamento (para o app seguir)

Código: `backend/src/trato/api/rotas_pedido_contrato.py` (novas) e `rotas_app.py` (orçamentos do
pedido, resumo, mensagens, verificação, avaliação). Testes: `backend/tests/api/test_rotas_pedido_contrato.py`
(memória) e `backend/tests/integracao/test_rotas_pedido_contrato_postgres.py` (Postgres local).

Regras que valem para todas:

- Header `Authorization: Bearer <token do Supabase Auth>`. Sem token: `401`.
- O papel vem do **banco**, nunca do token. Papel errado: `403`. Quem não é parte do pedido: `404`
  (a API não revela que o pedido existe).
- Valores em **centavos inteiros** (`1.5` ou texto é recusado com `422`). O app **só pede e mostra**:
  taxa, líquido, custo do provedor e "pago" são decididos pelo backend.
- Corpo com campo desconhecido: `422`.
- `{contrato_id}` é o **id do pedido** (o contrato é um por pedido e não tem outro id).
- O app **nunca** mostra "pago" antes de `pago: true` em `GET /v1/contratos/{id}/pagamento` (D13).

## Orçamento

| Método e caminho | Quem pode | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/pedidos/{id}/orcamentos` | cliente dono (vê todos), profissional (só o dele), equipe com permissão | — | lista de `{id, profissional_id, profissional_nome, versao, valor_centavos, prazo_execucao_dias, garantia_dias, observacoes, enviado_em, aceito}`; do mais barato ao mais caro; **sem rascunhos** |
| `GET /v1/orcamentos/{id}` | cliente dono do pedido e o profissional autor | — | os campos acima mais `status`, `validade_ate`, `fora_do_escopo`, `sinal_material_centavos`, `itens[] {tipo, descricao, quantidade (texto), valor_unitario_centavos, total_centavos}`. Rascunho: `404` |
| `POST /v1/orcamentos/resumo` | profissional | `{valor_centavos}` | `{valor_centavos (bruto), taxa_centavos, liquido_centavos, custo_provedor_estimado_centavos, custo_provedor_estimativa: true}`. Taxa da configuração vigente; o custo do provedor é **estimativa** (maior entre Pix e cartão) e sai da taxa do Trato, não do líquido. Sem taxa configurada: `503`. Nada é gravado |

O aceite continua em `POST /v1/pedidos/{id}/acoes/aceitar_orcamento`.

## Cobrança e pagamento

| Método e caminho | Quem pode | Corpo | Resposta |
|---|---|---|---|
| `POST /v1/contratos/{id}/cobranca` | cliente do contrato | `{meio: "pix" \| "cartao"}` | `201` `{contrato_id, cobranca_id, estado_pagamento: "aguardando_confirmacao", meio, valor_centavos, tipo_instrucao, instrucao, criada_em}`. Pix: `tipo_instrucao = "pix_copia_e_cola"` e `instrucao` é o código. Cartão: `"cartao_segredo_do_cliente"` e `instrucao` é o segredo para o SDK do app. Repetir com o mesmo meio devolve a **mesma** cobrança pendente (idempotente); trocar o meio cancela a anterior |
| `GET /v1/contratos/{id}/pagamento` | cliente e profissional do contrato | — | `{contrato_id, estado_pagamento, pago, valor_centavos, pago_centavos, cobranca_id, meio, estado_pedido}` |

`estado_pagamento`: `sem_cobranca`, `aguardando_confirmacao`, `pago`, `falhou`, `cancelada`.
`pago` só vira `true` depois do **webhook assinado** do provedor (`POST /v1/webhooks/stripe`): a
cobrança criada, o aviso do cliente ou a cobrança "paga" no provedor não bastam. O app consulta
`GET .../pagamento` (por exemplo a cada poucos segundos) até `pago: true` ou `falhou`.

Erros da cobrança: `409` pedido que não espera pagamento (estado diferente de "orçamento aceito" ou
"aguardando confirmação") ou já pago; `404` contrato inexistente ou de outra pessoa; `503` serviço de
pagamento não configurado.

**Provedor.** `TRATO_PROVEDOR_PAGAMENTO` no `.env`: `fake` (padrão, sem rede nem dinheiro) ou
`stripe` (**modo teste**: exige `STRIPE_SECRET_KEY=sk_test_...` e `STRIPE_WEBHOOK_SECRET`; chave
`sk_live_` é recusada). Seletor: `trato.pagamentos.montagem.escolher_provedor`.

## Garantia

| Método e caminho | Quem pode | Resposta |
|---|---|---|
| `GET /v1/contratos/{id}/garantia` | cliente e profissional do contrato | `{contrato_id, iniciada, ativa, dias, inicio_em, fim_em, retrabalhos[] {aberto_em, atender_ate, estado}}`. Antes da conclusão: `iniciada: false`. Os `dias` ficam congelados ao concluir |

Pedir retrabalho continua em `POST /v1/pedidos/{id}/retrabalho`.

## Aditivos

| Método e caminho | Quem pode | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/contratos/{id}/aditivos` | cliente e profissional do contrato | — | lista `{id, contrato_id, descricao, valor_centavos, estado}`; `estado`: `proposto`, `aprovado`, `recusado`, `pago` |
| `POST /v1/contratos/{id}/aditivos` | só o profissional contratado | `{descricao, valor_centavos}` | `201` o aditivo `proposto`. Nada é cobrado. Só com o serviço **em andamento** (`409` fora disso) |
| `POST /v1/contratos/{id}/aditivos/{aditivo_id}/aprovar` | **só o cliente** | opcional `{meio}` (padrão `pix`) | `{aditivo, cobranca}`. Com o serviço de pagamento ligado, `cobranca` vem `aguardando_confirmacao` (mesmo contrato da rota de cobrança); sem ele, `cobranca: null` |
| `POST /v1/contratos/{id}/aditivos/{aditivo_id}/recusar` | **só o cliente** | — | `{aditivo, cobranca: null}` |

Decidido não muda mais (`409`). O profissional que tenta aprovar ou recusar recebe `403`.
As rotas antigas `/v1/pedidos/{id}/aditivos...` seguem valendo.

## Nota de material

| Método e caminho | Quem pode | Corpo | Resposta |
|---|---|---|---|
| `POST /v1/contratos/{id}/notas-material` | só o profissional contratado, serviço em andamento | `{midia_id` **ou** `foto_storage_path, itens[] {descricao, quantidade (decimal, até 2 casas, > 0), valor_unitario_centavos}}` (1 a 50 itens) | `201` `{id, contrato_id, itens[] {descricao, quantidade, valor_unitario_centavos, total_centavos}, total_centavos, enviada_em}`. O total sai do backend (quantidade × unitário, meio para cima) |
| `GET /v1/contratos/{id}/notas-material` | cliente e profissional do contrato | — | lista no mesmo formato |

A foto vem do upload: mande o `midia_id` devolvido por `POST /v1/uploads/{id}/concluir` (seção
"Nota de material: `midia_id` ou caminho"). `foto_storage_path` é o **caminho** no bucket privado,
nunca uma URL nem `..`; fica para quando o serviço de upload não está ligado.

## Avaliação

`POST /v1/contratos/{id}/avaliacao` (mesma regra e corpo de `POST /v1/pedidos/{id}/avaliacao`):
cliente e profissional, **uma vez cada**, só com o pedido concluído. Corpo
`{nota_geral: 1..5, comentario?, etiquetas?}`. Resposta `201` `{pedido_id, direcao, nota_geral, comentario, etiquetas, criada_em}`.

## Perfil

| Método e caminho | Quem pode | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/me` | qualquer pessoa logada | — | `{id, nome, papel, papeis[], status, nivel_verificacao, nota_publica, servicos_concluidos, tem_perfil_profissional, status_verificacao}`. Cria a linha em `usuarios` se faltar (idempotente). Nunca devolve CPF, telefone nem e-mail |
| `PATCH /v1/me` | cliente e profissional | `{nome}` (2 a 120 caracteres) | o mesmo perfil já atualizado. O papel não pode ser trocado por aqui |

`papeis` é a lista do que a pessoa pode ser (`cliente`; mais `profissional` se tem perfil de
profissional). `status_verificacao`: `enviada`, `em_analise`, `aprovada`, `recusada` ou `null`.

## Profissional: pedidos abertos e recusa

| Método e caminho | Quem pode | Parâmetros / corpo | Resposta |
|---|---|---|---|
| `GET /v1/profissional/pedidos-abertos` | profissional | query: `categoria_id`, `bairro`, `preco_min_centavos`, `preco_max_centavos`, `ordenar` (`recentes` padrão, `antigos`, `urgentes`, `maior_valor`, `menor_valor`), `limite` (1 a 100, padrão 50) | lista `{id, titulo, descricao, bairro, categoria_id, faixa_preco_min_centavos, faixa_preco_max_centavos, urgente, prazo_desejado, aberto_em}`. Sem endereço exato |
| `POST /v1/pedidos/{id}/recusar` | profissional | `{motivo}` (1 a 500) | `{pedido_id, recusado: true}` |

Visibilidade (a mesma da RLS): pedido **aberto**, profissional **aprovado**, categoria em que atua e
**não suspensa**, região (cidade, e bairro quando ele fixou um). Faixa de preço: entram os pedidos
cuja faixa cruza o intervalo pedido; pedido sem faixa sempre entra. Pedido que o profissional recusou
não volta para a lista dele. Recusar não avisa o cliente nem muda o estado do pedido; repetir é seguro;
pedido que ele não podia ver responde `404`.

## Duas rotas de pagamento (qual usar quando)

| Rota | Para que serve | Resposta |
|---|---|---|
| `GET /v1/pedidos/{id}/pagamento` | **Antes de cobrar**: o que mostrar na tela de pagar (valor e meios). Cliente do pedido ou equipe com permissão | `{pedido_id, estado, valor_centavos, pago_centavos, pagamento_confirmado, meios_disponiveis: ["pix","cartao"], cobranca_pendente_id}` |
| `GET /v1/contratos/{id}/pagamento` | **Depois de cobrar**: o estado do pagamento (consultar até `pago: true`). Cliente e profissional | `{contrato_id, estado_pagamento, pago, valor_centavos, pago_centavos, cobranca_id, meio, estado_pedido}` |

O app lê **valor e meios** da primeira e **só acredita em "pago"** na segunda (`pago: true`, que vem
do webhook assinado). `pagamento_confirmado` da primeira tem o mesmo sentido, mas não é a rota de
consulta. Valores sempre em centavos inteiros.

## Mensagens

| Método e caminho | Quem pode | Corpo / parâmetros | Resposta |
|---|---|---|---|
| `GET /v1/pedidos/{id}/mensagens` | cliente do pedido, profissional (do pedido ou que pode orçar), mediador em disputa | query `profissional_id` (cliente, antes de contratar) | lista `{id, autor_id, minha, texto, mascarada, enviada_em, lida_em}` |
| `POST /v1/pedidos/{id}/mensagens` | cliente e profissional | `{texto}` (1 a 2000), query `profissional_id` (cliente) | `201` a mensagem |
| `GET /v1/conversas` | cliente e profissional | — | lista `{id, pedido_id, outra_parte_id, encerrada, nao_lidas, ultima_mensagem, ultima_em, ultima_minha}` (mais recente primeiro) |
| `POST /v1/mensagens/{id}/lida` | quem recebeu a mensagem | — | `{lida_em}` |
| `POST /v1/conversas/{id}/lida` | participante | — | `{marcadas}` |

Antes da contratação, e-mail, telefone, link e endereço no texto saem ocultos (`mascarada: true`).
Conversa do **cliente** sem `profissional_id` só funciona depois do aceite (vale o contratado); antes
disso o app precisa mandar `?profissional_id=` (sem ele: `422`). A conversa pertence a UM profissional.

## Notificações, preferências e push

| Método e caminho | Corpo | Resposta |
|---|---|---|
| `GET /v1/notificacoes?nao_lidas=&limite=` | — | lista `{id, tipo, canal, titulo, corpo, dados {link,…}, criada_em, lida, lida_em}` |
| `POST /v1/notificacoes/{id}/lida` | — | a notificação com `lida: true`. Repetir devolve a mesma `lida_em`. De outra pessoa: `404` |
| `GET /v1/notificacoes/preferencias` | — | `{categorias: {categoria: {app, push, email: bool}}}` (com o padrão aplicado) |
| `PUT /v1/notificacoes/preferencias` | `{categorias: {categoria: {canal: bool}}}` | o mesmo formato. Troca só o que veio. Canal fora de `app/push/email`: `422` (SMS/WhatsApp não são preferência, D14) |
| `POST /v1/dispositivos` | `{token (8 a 4096), plataforma: "android"\|"ios"\|"web"}` | `204`. O token é de UMA pessoa: registrar de novo move para quem registrou |
| `DELETE /v1/dispositivos` | `{token}` | `204`. Só o dono desliga; token inexistente ou alheio também responde `204` (não revela de quem é). Chamar ao sair da conta |

## Upload de arquivos (obrigatório para foto e documento)

1. `POST /v1/uploads` `{destino, nome_arquivo, content_type, tamanho_bytes, pedido_id?, tipo_documento?}`
   → `201` `{upload_id, url_envio, metodo: "PUT", expira_em_segundos, content_type}`.
2. `PUT url_envio` com o arquivo (mesmo `content_type`).
3. `POST /v1/uploads/{upload_id}/concluir` `{latitude?, longitude?}` → `{upload_id, destino, status,
   midia_id, sha256, tamanho_bytes}`. O backend relê o arquivo, confere o tipo REAL, o tamanho, tira
   EXIF/GPS de imagem e só então registra. Arquivo falso é apagado e recusado (`422`).

Destinos: `pedido`, `antes`, `durante`, `depois`, `checkin`, `checkout`, `nota_material`, `disputa`,
`retrabalho`, `chat`, `avatar`, `verificacao`, **`portfolio`**. Destinos de pedido exigem `pedido_id` e
ser parte dele (`404` se não for; `403` se o papel não pode: check-in, check-out, nota, durante e
depois só do profissional; `pedido` só do cliente). `portfolio` e `avatar` não têm pedido;
`portfolio` é só do profissional, só imagem (JPEG, PNG, WebP), limite em `TRATO_SEG_UPLOADS`
(padrão 8 MB), EXIF e GPS removidos, guardado em `<seu id>/portfolio/`.

**O upload é obrigatório na verificação.** `POST /v1/profissional/verificacao` com o serviço de
upload ligado só aceita `documentos: [{tipo, upload_id}]` de um envio **concluído**, do mesmo dono e do
mesmo tipo (destino `verificacao`); caminho cru (`storage_path`) é recusado. Sem o serviço ligado
(`503` no upload) o app não consegue verificar.

## Check-in e check-out reenviados (offline)

Dentro de `prova` de `fazer_check_in` e `fazer_check_out` o app pode mandar
`"offline_capturada_em": "2026-10-29T09:15:00-03:00"` (ISO 8601 **com fuso**) quando reenvia uma ação
guardada sem internet. Regras:

- A hora **oficial** é sempre a do servidor (a foto leva a hora em que o servidor a recebeu). O campo é
  só evidência para a mediação: nunca decide prazo, estado nem dinheiro.
- Janela em configuração: no máximo `TRATO_UP_OFFLINE_JANELA_MAX_HORAS` (padrão 72) no passado e
  `TRATO_UP_OFFLINE_TOLERANCIA_FUTURO_S` (padrão 300) no futuro. Fora da janela, no futuro ou sem fuso:
  `422` e a ação não acontece.
- Aceita a ação, o valor informado e a hora de recebimento entram na auditoria (`evidencia_offline`).
- Em qualquer outra ação, o campo continua recusado (`422`).

## Nota de material: `midia_id` ou caminho

`POST /v1/contratos/{id}/notas-material` aceita **um** dos dois (os dois juntos ou nenhum: `422`):

- `midia_id`: o que `POST /v1/uploads/{id}/concluir` devolveu (destino `nota_material`). O backend
  confere que a mídia é **deste pedido, enviada por quem envia a nota e com finalidade
  `nota_material`**; senão `422`. É o caminho feliz do app.
- `foto_storage_path`: caminho no bucket (sem `..` nem URL), para quando o serviço de upload não está
  ligado.

## Cadastro, perfil e busca de profissionais

Cadastro e perfil (`POST /v1/profissional/cadastro`, `GET/PATCH /v1/profissional/perfil`): ver
`docs/api-rotas-profissional.md`. Aqui o que o app usa para ligar as telas:

| Método e caminho | Quem pode | Resposta |
|---|---|---|
| `GET /v1/catalogo/categorias` | qualquer pessoa logada | lista `{id, nome, slug, icone, pai_id}` das categorias **ativas**, na ordem do catálogo. Os `id` vão em `categorias` do cadastro |
| `GET /v1/catalogo/cidades` | qualquer pessoa logada | lista `{id, nome, uf}` das cidades **ativas**, em ordem alfabética. Os `id` vão em `regioes[].cidade_id` |
| `GET /v1/profissionais` | cliente ou profissional | busca, abaixo |
| `GET /v1/profissionais/{id}` | qualquer pessoa logada | perfil público: `{id, nome (abreviado), bio, nivel_verificacao, nota_publica, servicos_concluidos, categorias, regioes, cidades ("Belo Horizonte/MG"), no_trato_desde, disponibilidade, portfolio, avaliacoes[]}`. Só aprovado; senão `404` |

**Busca** `GET /v1/profissionais?servico=&categoria_id=&cidade_id=&bairro=&pagina=1&limite=20`
(`limite` 1 a 50). Só profissionais **aprovados** e de usuário ativo; categoria suspensa do
profissional não conta. `servico` procura no nome da categoria (sem acento, sem maiúsculas, inclui as
filhas); `categoria_id` é exato (os dois juntos: interseção); `cidade_id` e `bairro` filtram a região
(quem atende a cidade toda também entra no bairro). Ordem: melhor nota (sem nota por último), mais
serviços, id. Resposta:

```json
{"itens": [{"id": "…", "nome": "Maria S.", "bio": "…", "nivel_verificacao": "verificado",
            "nota_publica": 4.9, "servicos_concluidos": 30, "categorias": ["<id>"]}],
 "pagina": 1, "limite": 20, "total": 1, "tem_mais": false}
```

Sem documento, telefone, e-mail, endereço nem o nome completo. Abra o perfil por `id`.

## Orçamento: selo do profissional e taxa

- `GET /v1/pedidos/{id}/orcamentos` ganhou `profissional_nivel_verificacao`, `profissional_nota` e
  `profissional_servicos_concluidos` (nulos se o perfil não tem o dado).
- `POST /v1/orcamentos/resumo` ganhou `taxa_bps` e `taxa_percentual` (taxa **efetiva**: taxa ÷ valor,
  já com faixas e mínimo; ex.: `7.5`). O app só mostra, não calcula.
- `GET /v1/profissional/pedidos-abertos/{id}`: detalhe de um pedido aberto, mesma visibilidade da lista
  (`404` fora dela), com `orcamentos_recebidos` e `ja_orcou`; sem endereço exato.

## Profissional: responder disputa e atender retrabalho

| Método e caminho | Quem pode | Resposta |
|---|---|---|
| `GET /v1/pedidos/{id}/disputa` | cliente, profissional, equipe | a disputa (`estado`, `resposta_ate`, valor congelado) |
| `POST /v1/pedidos/{id}/disputa/resposta` | só o profissional contratado, dentro do prazo de resposta (configuração de disputas) | a disputa em `em_analise`. Sem corpo: é o "recebi e vou responder"; as provas dele vão pelo chat/evidência. Prazo vencido: `409` |
| `GET /v1/pedidos/{id}/retrabalho` | cliente e profissional | lista `{pedido_id, estado, aberto_em, atender_ate, descricao, atendido_em}` |
| `POST /v1/pedidos/{id}/retrabalho/atender` | só o profissional contratado | corpo `{etapa: "aceitar"\|"iniciar"\|"resolver"}`; devolve o retrabalho |

Retrabalho: `aberto` → `aceito` → `em_execucao` → `resolvido`, nessa ordem (pular etapa: `409`).
Repetir a mesma etapa é seguro. Depois de `atender_ate` (prazo da configuração) não dá mais para
atender: `409`, e o caso segue por suporte e análise de problemas. Quem não é o profissional do
pedido: `403` (cliente) ou `404`.

## O que ainda falta (depende do João ou de outra tarefa)

- **Migration APLICADA em 30/10/2026:** `supabase/migrations/20261030140000_upload_destino_portfolio.sql`
  (rollback em `supabase/rollback/upload_destino_portfolio_rollback.sql`). Só passa a importar quando
  as solicitações de upload forem gravadas em `upload_solicitacoes` (hoje ficam em memória).

- **Migration aplicada em 30/10/2026:** `supabase/migrations/20261030130000_pedido_recusas.sql`
  (rollback em `supabase/rollback/pedido_recusas_rollback.sql`). Sem ela, `POST .../recusar` em modo
  `postgres` responde erro. Precisa do OK do João (ver formato `PRECISO DO SEU OK` no relatório).
- **Cobrança em modo `postgres`:** o `ServicoPagamento` ainda usa repositórios de cobrança, aditivo
  e termos **em memória** e a fábrica Postgres não o liga (nenhuma cobrança é gravada no banco).
  Enquanto isso, `POST .../cobranca` responde `503` no app real; funciona com o serviço ligado em
  teste. Falta o adaptador Postgres (tabela `pagamentos` já existe) para ligar em produção.
- Aditivos em modo `postgres` (sem o serviço de pagamento) decidem no banco, mas **não criam
  cobrança** do aditivo.
