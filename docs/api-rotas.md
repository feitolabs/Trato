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
| `POST /v1/contratos/{id}/notas-material` | só o profissional contratado, serviço em andamento | `{foto_storage_path, itens[] {descricao, quantidade (decimal, até 2 casas, > 0), valor_unitario_centavos}}` (1 a 50 itens) | `201` `{id, contrato_id, itens[] {descricao, quantidade, valor_unitario_centavos, total_centavos}, total_centavos, enviada_em}`. O total sai do backend (quantidade × unitário, meio para cima) |
| `GET /v1/contratos/{id}/notas-material` | cliente e profissional do contrato | — | lista no mesmo formato |

`foto_storage_path` é o **caminho** da foto no bucket privado (o app envia o arquivo por URL assinada),
nunca uma URL nem `..`.

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

## O que ainda falta (depende do João ou de outra tarefa)

- **Migration NOVA, não aplicada:** `supabase/migrations/20261030130000_pedido_recusas.sql`
  (rollback em `supabase/rollback/pedido_recusas_rollback.sql`). Sem ela, `POST .../recusar` em modo
  `postgres` responde erro. Precisa do OK do João (ver formato `PRECISO DO SEU OK` no relatório).
- **Cobrança em modo `postgres`:** o `ServicoPagamento` ainda usa repositórios de cobrança, aditivo
  e termos **em memória** e a fábrica Postgres não o liga (nenhuma cobrança é gravada no banco).
  Enquanto isso, `POST .../cobranca` responde `503` no app real; funciona com o serviço ligado em
  teste. Falta o adaptador Postgres (tabela `pagamentos` já existe) para ligar em produção.
- Aditivos em modo `postgres` (sem o serviço de pagamento) decidem no banco, mas **não criam
  cobrança** do aditivo.
