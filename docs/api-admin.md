# API administrativa (painel da equipe)

Código: `backend/src/trato/api/admin/`. Testes: `backend/tests/api/test_admin_*.py` (memória) e
`backend/tests/integracao/test_admin_postgres.py` (Postgres local descartável).
Quando existir `docs/painel-admin.md`, **ele manda nos nomes**; este arquivo é o contrato que o
backend cumpre hoje.

Em português simples: é a porta do painel interno. Cada rota diz **qual papel da equipe** pode
usá-la, pede **motivo escrito** em tudo que é sensível e deixa **rastro na auditoria**.

## Regras gerais

- **Autenticação:** `Authorization: Bearer <JWT do Supabase>`, o mesmo do app. O token só diz *quem*.
- **Autorização por papel:** a cada chamada o backend lê a linha do usuário em `equipe`. Sem linha,
  `ativo = false` ou `revogado_em` preenchido: **403**. O papel nunca vem do token. Sem token ou token
  inválido: **401**. Papel sem a permissão da rota: **403**.
- **Motivo obrigatório** (`motivo` ou `justificativa`, 5 a 1000 caracteres, sem só espaços) em toda
  ação que muda algo ou revela dado pessoal. Faltando: **422**. O motivo vai para `auditoria.motivo`.
- **Auditoria:** toda escrita e toda revelação de dado pessoal chama `registrar_auditoria` **na mesma
  transação** da mudança (Postgres). A auditoria guarda *quais campos* foram revelados, nunca os valores.
- **Dinheiro:** centavos inteiros. Nenhuma rota recebe valor em reais nem percentual em float.
- **Paginação:** listas devolvem `{itens, total, limite, deslocamento}`; `limite` 1–100 (padrão 20).
- **Erros:** `{"detail": "mensagem em português"}`. 404 id inexistente (ou que não é uuid), 409 estado
  não permite, 422 corpo/valor inválido, 403 papel/alçada/segunda pessoa, 503 coisa não configurada.
- **Sem saldo próprio e sem saque** (D15, caminho A). Não existe rota de escrita em pagamentos.

## Matriz de papéis (igual à do painel, `admin/lib/nucleo/papeis.dart`)

| Permissão | Papéis |
|---|---|
| `verificacoes_ver` | cadastro, seguranca, administrador |
| `verificacoes_decidir`, `documentos_revelar` | **cadastro** (só ele abre arquivo) |
| `disputas_ver` | atendente_n2, lider_suporte, mediador, administrador |
| `disputas_decidir` | lider_suporte, mediador, administrador |
| `disputas_segunda_pessoa` | lider_suporte, administrador |
| `pagamentos_ver` | financeiro, administrador |
| `usuarios_buscar` | atendente_n1, atendente_n2, lider_suporte, cadastro, moderador, seguranca, dpo, administrador |
| `dados_pessoais_revelar` | cadastro, seguranca, dpo |
| `pedidos_buscar` | atendente_n1, atendente_n2, lider_suporte, mediador, moderador, financeiro, administrador |
| `config_ver` | financeiro, juridico, administrador |
| `config_propor` | financeiro, administrador |
| `config_aprovar` (aprovar e publicar) | administrador |
| `auditoria_ver`, `auditoria_verificar_cadeia` | seguranca, juridico, dpo, administrador |

## 1. Verificação de profissionais

| Método e caminho | Papel | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/admin/verificacoes?status=&limite=&deslocamento=` | verificacoes_ver | — | página de `Verificacao`. Sem `status`: `enviada` e `em_analise` |
| `GET /v1/admin/verificacoes/{id}` | verificacoes_ver | — | `Verificacao` |
| `POST /v1/admin/verificacoes/{id}/documentos/{doc}/url` | **cadastro** | `{motivo}` | `{url, expira_em_segundos}` (60 s) |
| `POST /v1/admin/verificacoes/{id}/decisao` | cadastro | `{aprovar: bool, motivo}` | `Verificacao` |

`Verificacao`: `id, profissional_id, profissional_nome, nivel_solicitado, status, enviada_em, decidida_em,
motivo_recusa, cpf_mascarado ("***.***.***-09"), documentos: [{id, tipo, validade_em, mascarado: true}]`.

- O caminho do arquivo no storage **nunca** sai. O arquivo só abre pela URL assinada, que grava
  `dado_pessoal.documento_revelado` na auditoria **antes** de assinar. Sem assinador configurado: **503**.
- Aprovar: `verificacoes.status = aprovada` e `perfis_profissional` vira `aprovado` com o nível pedido.
  Recusar: `recusada` com `motivo_recusa`; o perfil só vira `recusado` se ainda estava `em_analise`.
  Decidir de novo uma verificação já decidida: **409**.

## 2. Disputas

| Método e caminho | Papel | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/admin/disputas?estado=&limite=&deslocamento=` | disputas_ver | — | página de `DisputaResumo` (padrão: tudo que não está `decidida`; prazo de decisão mais curto primeiro) |
| `GET /v1/admin/disputas/{pedido_id}` | disputas_ver | — | `DisputaDetalhe` |
| `POST /v1/admin/disputas/{pedido_id}/decisao` | disputas_decidir | `{resultado, justificativa, percentual_cliente_bps?, valor_cliente_centavos?}` | `DisputaDetalhe` |
| `POST /v1/admin/disputas/{pedido_id}/aprovacao` | disputas_segunda_pessoa | `{justificativa}` | `DisputaDetalhe` |

`resultado`: `liberar_tudo`, `reembolso_total`, `reembolso_parcial` (exige exatamente um entre
`percentual_cliente_bps` 1–9999 e `valor_cliente_centavos`), `nova_visita`.
`DisputaResumo`: `pedido_id, estado (aberta|em_analise|aguardando_aprovacao|decidida), motivo,
valor_congelado_centavos, aberta_em, resposta_ate, decisao_ate, atrasada, sem_resposta`.
`DisputaDetalhe` soma: `cliente{id,nome}, profissional{id,nome}, estado_pedido, decisao, decidido_por,
aprovado_por, aguardando_segunda_pessoa, divisao{para_profissional,para_cliente,retido _centavos},
evidencias[{origem,em,ator_papel,ator_id,dados}] (provas do pedido, sem códigos de check-in/out),
linha_do_tempo[{em,tipo,acao,de,para,ator_papel,ator_id}], lancamentos_da_decisao[]`.

Regras (todas já existem em `disputas/`, `pedidos/estados.py` e `financeiro/ledger.py`):

- **Alçada:** `equipe.alcada_centavos` do decisor (vazia = 0). Valor congelado **acima** da alçada: a
  disputa fica `aguardando_aprovacao`, nada se move, e **outra pessoa** (lider_suporte ou administrador)
  aprova em `/aprovacao`. Quem decidiu não aprova a própria decisão (**403**). O aprovador também precisa
  de alçada ≥ valor, exceto o administrador. Dentro da alçada a decisão vale na hora.
- **Efeito de uma decisão final** (na ordem, e tudo que pode recusar roda antes de gravar):
  1. pedido: `EM_DISPUTA` → `concluido` (liberar_tudo, parcial), `cancelado` (reembolso_total) ou
     `retrabalho` (nova_visita), pela máquina de estados; conclusão abre a garantia;
  2. ledger (**espelho**, caminho A): `estornar_pedido` para a parte do cliente e `repartir_custodia`
     para a parte do profissional, com a taxa de `contexto.taxa` (configuração). Sem taxa ligada: **503**.
     A devolução real ao cliente acontece no parceiro de pagamento, fora desta API;
  3. disputa vira `decidida`; 4. auditoria `financeiro.disputa_decidida` com a justificativa.
- **Idempotência:** chaves do ledger `disputa/<pedido>/...`. Repetir depois de uma falha no meio refaz o
  que faltou sem duplicar lançamento; repetir depois de concluído responde **409**.
- Disputa `aberta` dentro do prazo do profissional não se decide (**409**); vencido o prazo, a decisão
  encerra a espera ("sem resposta") e segue.

## 3. Pagamentos e conciliação (SOMENTE LEITURA)

| Método e caminho | Papel | Resposta |
|---|---|---|
| `GET /v1/admin/pagamentos?pedido_id=&status=&apenas_divergentes=` | pagamentos_ver | página de `{lancamento_id, pedido_id, valor_centavos, estornado_centavos, status (confirmado\|estornado_parcial\|estornado), data, referencia_provedor, divergente}` |
| `GET /v1/admin/pagamentos/resumo` | pagamentos_ver | `{confirmado_centavos, estornado_centavos, retido_centavos, taxa_trato_centavos, divergencias, atualizado_em}` |
| `GET /v1/admin/webhooks/eventos` | pagamentos_ver | página de `{provedor, evento_id, tipo, recebido_em, pedido_id, referencia, valor_centavos}` (sem o payload bruto) |
| `GET /v1/admin/lancamentos?pedido_id=&tipo=` | pagamentos_ver | página de lançamentos (`id, pedido_id, tipo, valor_centavos, data, debito, credito, estorno_de`) |
| `GET /v1/admin/contratos/{pedido_id}/extrato` | pagamentos_ver | `{pedido_id, estado, valor_contrato_centavos, saldo{cliente_pagou,retido,a_liberar,liberado,taxa_trato _centavos}, lancamentos[]}` |

"Pagamento" é a cobrança do ledger-espelho cruzada com o pedido. `divergente` = cobrança sem pedido, sem
contrato ou sem referência do provedor. O saldo é **por pedido** (espelho); não há saldo próprio do Trato
nem rota de saque, chave Pix ou repasse.

## 4. Usuários e pedidos

| Método e caminho | Papel | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/admin/usuarios?q=&status=` | usuarios_buscar | — | página de `{id, nome, status, tipo (cliente\|profissional\|equipe), criado_em, nivel_verificacao, status_profissional}`; `q` = trecho do nome ou o id |
| `GET /v1/admin/usuarios/{id}` | usuarios_buscar | — | idem, **sem dados pessoais** |
| `POST /v1/admin/usuarios/{id}/dados-pessoais` | dados_pessoais_revelar | `{motivo}` | `{cpf, telefone, data_nascimento, telefone_confirmado_em, email_confirmado_em}` |
| `GET /v1/admin/pedidos?q=&estado=&cliente_id=&profissional_id=` | pedidos_buscar | — | página de `{id, titulo, estado, cliente_id, cliente_nome, profissional_id, valor_centavos, criado_em}` |
| `GET /v1/admin/pedidos/{id}` | pedidos_buscar | — | `{id, estado, cliente, profissional, aberto_em, concluido_em, valor_contrato_centavos, pagamento_confirmado, tem_disputa, eventos[]}` |

- Revelar dado pessoal é `POST` porque deixa rastro: `dado_pessoal.revelado` (o banco recusa essa ação sem
  motivo). O e-mail mora em `auth.users` e **não** é devolvido (o backend não lê esse schema).
- O detalhe do pedido nunca traz códigos de início/conclusão nem o endereço.

## 5. Configuração versionada

| Método e caminho | Papel | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/admin/config/definicoes` | config_ver | — | catálogo `[{chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao}]` |
| `GET /v1/admin/config/vigente` | config_ver | — | `Versao` com parâmetros e faixas (404 se não houver) |
| `GET /v1/admin/config/versoes` / `.../{id}` | config_ver | — | histórico (sem itens) / `Versao` completa |
| `POST /v1/admin/config/versoes` | config_propor | `{motivo, parametros[], faixas[], vigente_desde?, partir_da_vigente=true}` | `Versao` em `rascunho` (201) |
| `POST .../versoes/{id}/enviar` | config_propor | `{motivo}` | `aguardando_aprovacao` |
| `POST .../versoes/{id}/aprovar` | **config_aprovar** | `{motivo}` | `aprovada` |
| `POST .../versoes/{id}/publicar` | config_aprovar | `{motivo}` | `vigente` |
| `POST .../versoes/{id}/reverter` | config_propor | `{motivo}` | **nova** `Versao` `aguardando_aprovacao` (201), cópia da `{id}` |
| `DELETE .../versoes/{id}` | config_propor | `{motivo}` | 204 (só rascunho e aguardando aprovação) |

`parametros[]`: `{chave, valor, escopo_tipo=global, escopo_id?, escopo_texto?}`.
`faixas[]`: `{de_centavos, ate_centavos (null = sem teto), taxa_bps, escopo_*}`.
`Versao`: `id, numero, status, motivo, criada_por, aprovada_por, vigente_desde, revertida_de, criado_em, parametros, faixas`.

- Ciclo: `rascunho → aguardando_aprovacao → aprovada → vigente → substituida | revertida`.
- **Aprovação dupla:** quem propôs não aprova (**403**), nem o administrador; o banco também recusa
  (`criada_por <> aprovada_por`). `vigente_desde` vazio vira a hora da aprovação; data futura = vigência
  agendada (publicar antes da hora: **409**).
- **Versões imutáveis:** depois de aprovada, nada edita parâmetros nem faixas (o banco recusa até o
  `service_role`). Mudar = nova versão. Não existe rota de edição.
- **Reverter** não reabre a versão antiga: cria uma versão nova com o conteúdo dela, que passa pela mesma
  aprovação. Ao publicá-la, a vigente anterior fica `revertida`.
- Validação antes do banco (422): chave fora do catálogo, valor fora de `minimo/maximo`, escopo não permitido,
  parâmetro repetido, faixas sobrepostas. Ao **enviar** e ao **publicar**: faixas sem buraco, começando em 0 e
  com a última sem teto, e os parâmetros que o resto do backend exige (`adiantamento_bps` e os três prazos de
  disputa) — sem eles a API toda responderia 503.

## 6. Auditoria

| Método e caminho | Papel | Resposta |
|---|---|---|
| `GET /v1/admin/auditoria?acao=&ator_id=&entidade=&entidade_id=&desde=&ate=` | auditoria_ver | página de `{id, ocorrida_em, ator_id, ator_tipo, acao, entidade, entidade_id, motivo, antes, depois}`, mais nova primeiro. `acao` é **prefixo** (`config.`) |
| `POST /v1/admin/auditoria/verificar-cadeia` | auditoria_verificar_cadeia | `{integra, primeira_falha_id, verificada_em}` (`verificar_cadeia_auditoria`); o próprio pedido de verificação fica registrado |

Ações gravadas por esta API: `verificacao.aprovada|recusada`, `dado_pessoal.documento_revelado`,
`dado_pessoal.revelado`, `financeiro.disputa_decisao_proposta|disputa_decidida`,
`config.rascunho_criado|enviada_para_aprovacao|aprovada|publicada|reversao_proposta|rascunho_descartado`,
`auditoria.cadeia_verificada`.

## Pendências e limites conhecidos

1. **Disputas, ledger e eventos de webhook ainda são memória em modo `postgres`** (tabelas F3.5/F3.6 não
   aplicadas; ver `docs/api-persistencia.md`). As rotas funcionam, mas a fila de disputas e os pagamentos
   ficam vazios após reiniciar. A listagem de disputas lê o dicionário do repositório em memória; quando
   existir o repositório Postgres, ele precisa de um método `listar()` (o código já o usa se existir).
   Evidências são as **provas dos eventos do pedido** (fotos, descrição); a tabela `disputa_evidencias` entra
   junto com a F3.6.
2. **URL assinada do storage:** o `AssinadorUrl` é um Protocol. Falta a implementação com a
   `service_role key` do Supabase Storage (bucket privado de verificação); sem ela a rota responde 503.
   Em `criar_admin_postgres(banco, assinador)` basta passar o assinador.
3. **Categorias e chamados** (telas F7.4 do painel) não fazem parte desta API ainda.
4. **Painel:** `decidirDisputa(... segundaPessoaEmail)` do `api_admin.dart` não existe aqui: a segunda
   pessoa é *outra pessoa logada* chamando `/aprovacao` (mais seguro que digitar e-mail). `revelarDocumento`
   → `POST .../documentos/{doc}/url`; `revelarDadosPessoais` não devolve e-mail.
5. **Alçada do aprovador** (alçada ≥ valor, exceto administrador) e a matriz de papéis acima são decisões
   minhas onde o escopo é omisso; ajustar em `rotas_disputas.py` e `papeis.py`.
6. **Auditoria da decisão de disputa** é gravada depois do efeito (disputas ainda em memória). Quando
   disputas/ledger forem Postgres, mover para a mesma transação.
7. Nada disto foi rodado no Supabase real; só em Postgres local descartável (pgserver).
