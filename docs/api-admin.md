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
| `incidentes_ver`, `incidentes_tratar` | lider_suporte, mediador, seguranca, administrador |
| `incidentes_encerrar` | lider_suporte, seguranca, administrador |
| `avaliacoes_moderar` | lider_suporte, mediador, seguranca, administrador |
| `lgpd_pedidos_gerenciar` | dpo, administrador |
| `lgpd_revisao_automatizada` | seguranca, dpo, administrador |
| `conta_retorno_analisar` | lider_suporte, mediador, seguranca, administrador |
| `conta_retorno_aprovar` | lider_suporte, administrador |
| `materiais_contestacao_analisar` | lider_suporte, mediador, seguranca, administrador |
| `materiais_contestacao_aprovar` | lider_suporte, administrador |

## 0. Quem sou eu

| Método e caminho | Papel | Resposta |
|---|---|---|
| `GET /v1/admin/eu` | qualquer membro vigente da equipe | `{id, papel, nome?, alcada_centavos}` (o painel chama logo após o login) |

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

### 3.1 Financeiro: contestações, alertas, conciliação, fechamento (08/11/2026)

Prefixo `/v1/admin/financeiro`. Nada aqui move dinheiro nem marca "pago" (D13). Código em
`backend/src/trato/api/admin/rotas_financeiro.py`.

| Método e caminho | Papel | O que faz |
|---|---|---|
| `GET /contestacoes?status=em_aberto\|aberta\|em_analise\|ganha\|perdida\|encerrada` | pagamentos_ver | Contestações de cartão (chargeback), da mais urgente (prazo de provas) para a mais antiga. `{id, pedido_id, pedido_numero, valor_centavos, motivo_legivel, status, prazo_provas, horas_para_prazo, repasse_liberado, …}` |
| `GET /alertas` | pagamentos_ver | `{pagamentos_parados[], repasses_com_falha[], estornos_pendentes[], eventos_em_revisao[], contestacoes_em_aberto, minutos_pagamento_parado, provedor_ligado}`. Parado = cobrança sem confirmação há mais de `alerta_pagamento_parado_minutos` (Configurações; 30 até ser aprovada). |
| `POST /cobrancas/{id}/consultar` | pagamentos_conciliar | Pergunta ao provedor o status da cobrança e devolve uma orientação. Auditado. **Não** marca pago: se o provedor já recebeu, a orientação é reenviar o aviso assinado. |
| `GET /conciliacao?dia=AAAA-MM-DD` | pagamentos_ver | Extrato do provedor × ledger espelho no dia (Brasília): cobrança por id do provedor, estorno e contestação por pedido, folga de 2 h para o aviso atrasado. `{confere, divergencias[], linhas[], cobrado_provedor_centavos, cobrado_trato_centavos, taxas_provedor_centavos}`. Auditado. |
| `GET /fechamentos?ultimos=12` | pagamentos_ver | Meses e se estão fechados / podem fechar. |
| `GET /fechamentos/{AAAA-MM}` | pagamentos_ver | Totais recalculados do ledger; se fechado, o retrato gravado, o hash e `confere` (recalculado == gravado). |
| `POST /fechamentos/{AAAA-MM}/fechar` `{motivo}` | pagamentos_conciliar | Só mês já terminado. Grava o retrato (imutável) e, no banco, trava lançamentos com data nesse mês. 409 se já fechado. Auditado. |
| `POST /fechamentos/{AAAA-MM}/exportar` | relatorios_exportar | CSV (Excel-BR) do mês por código de uso único (`/v1/admin/relatorios/baixar/{codigo}`). |
| `POST /profissionais/{usuario_id}/extrato` `{inicio, fim, motivo}` | relatorios_exportar | Extrato de recebimentos do profissional em PDF, por código de uso único. Auditado com motivo. |

Webhooks novos tratados (`TIPOS_STRIPE`): `charge.dispute.created|updated|closed` (contestação; perdida vira
estorno do serviço no ledger; sem saldo, fica em revisão) e `transfer.reversed` /
`payout.failed` (repasse que falhou: fica em revisão com o motivo do provedor). `GET /v1/admin/webhooks/eventos`
passou a trazer `revisao` (o motivo, quando o evento está para revisar).

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
`auditoria.cadeia_verificada`,
`seguranca.incidente_lista_consultada|consultado|aberto|medida|andamento|encerrado`,
`avaliacao.ocultada|ocultacao_revertida|revisao_em_analise|revisao_decidida`,
`lgpd.pedido_titular_em_analise|respondido`,
`conta.impedimento_revogado`, `conta.retorno_em_analise|aprovado|recusado`, `bloqueio.medida_aplicada`,
`material.contestacao_em_analise|contestacao_decidida|contestacao_financeiro_aprovado`.

## 7. Incidentes de segurança

Prefixo `/v1/admin/incidentes` (Termos 9.3 a 9.6). Código em `backend/src/trato/api/admin/rotas_incidentes.py`
e persistência em `backend/src/trato/persistencia/incidentes.py`.

| Método e caminho | Permissão | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/admin/incidentes?status=&pedido_id=&limite=&deslocamento=` | `incidentes_ver` | — | página de `Incidente` (`limite` 1–100 padrão 20, `deslocamento` ≥ 0, `pedido_id` até 64 chars; não encerrados primeiro, menor `cautela_ate` no topo) |
| `GET /v1/admin/incidentes/{incidente_id}` | `incidentes_ver` | — | `Incidente` completo (`404` se inexistente) |
| `POST /v1/admin/incidentes` | `incidentes_tratar` | `{tipo, descricao (1–4000), contato (1–320), canal, pedido_id? (≤64)}` | `Incidente` (`201` se novo; `200` se repetido em até 5 min) |
| `POST /v1/admin/incidentes/{incidente_id}/medidas` | `incidentes_tratar` | `{tipo, descricao (1–1000)}` | `Incidente` atualizado (`200`) |
| `POST /v1/admin/incidentes/{incidente_id}/status` | `incidentes_tratar` | `{status: cautela_adotada\|em_apuracao}` | `Incidente` atualizado (`200`) |
| `POST /v1/admin/incidentes/{incidente_id}/encerrar` | `incidentes_encerrar` | `{desfecho (10–4000)}` | `Incidente` encerrado (`200`) |

Valores aceitos (`extra="forbid"` em todos os corpos; strings com espaços das pontas removidos exceto em `/status`):
- `tipo` (incidente): `furto_roubo`, `agressao_ameaca_assedio`, `acidente_dano`, `pessoa_diferente`, `comportamento_suspeito`, `pagamento_por_fora`, `outro`.
- `canal`: `app`, `telefone`, `whatsapp`, `email`, `painel`.
- `tipo` (medida): `bloquear_contato`, `preservar_registros`, `reter_valor`, `cancelar_pedido_reembolso`, `outro` (`suspender_conta` fica fora — exige medida de conta das cláusulas 20.2 e 20.4).
- `status`: `aberto`, `cautela_adotada`, `em_apuracao`, `encerrado`.
- `Incidente`: `id, protocolo, canal, tipo, descricao, contato?, pedido_id?, status, aberto_em, cautela_ate, cautela_adotada_em?, responsavel_id?, desfecho?, encerrado_em?, medidas[{id, tipo, descricao, origem (analista|automatica), aplicada_em}]`.

Regras e códigos de erro:
- **Tabelas ausentes (503):** todas as 6 rotas checam `contexto.incidentes.disponivel()`; sem as tabelas `incidentes_seguranca` e `incidente_medidas` no banco, respondem **503**.
- **Abertura e validações:** `tipo = pessoa_diferente` exige `pedido_id` (**422** se ausente); `pedido_id` inexistente responde **404**. `cautela_ate` é calculado como `aberto_em + incidente_seguranca_cautela_horas` (configuração). Quando há `pedido_id`, a transação trava o pedido para não cruzar com liberação em andamento.
- **Conflitos de estado (409):** registrar medida ou mudar status em incidente já `encerrado` responde **409**; mudar status para `cautela_adotada` sem nenhuma medida registrada responde **409**; encerrar novamente com outro `desfecho` responde **409**.
- **Idempotência:** repetir `POST /v1/admin/incidentes` com os mesmos `tipo`, `descricao`, `canal`, `contato` e `pedido_id` em até **5 minutos** devolve **200** com o incidente já aberto (sem duplicar auditoria). Repetir medida idêntica `(tipo, descricao)`, status já atual ou `encerrar` com o mesmo `desfecho` devolve **200** sem duplicar registro nem auditoria.
- **Escopo e auditoria:** nada aqui move dinheiro, cancela pedido ou suspende conta; enquanto houver incidente não encerrado vinculado ao `pedido_id`, o saldo do pedido permanece retido (`api/liberacao.py`), e encerrar pode soltar esse valor. Todas as rotas gravam na auditoria (`entidade = "incidentes_seguranca"`, ações `seguranca.incidente_*`) sem incluir `contato` nem `descricao` na trilha (no encerramento, `desfecho[:500]` vai no `motivo`).

## 8. Moderação de avaliações

Prefixo `/v1/admin/avaliacoes` (Termos 12.6, 12.7 e 20.5). Código em `backend/src/trato/api/admin/rotas_avaliacoes.py`. Todas as rotas exigem `avaliacoes_moderar` e respondem **503** quando as tabelas ainda não existem no banco (`disponivel() == False`).

| Método e caminho | Permissão | Corpo | Resposta |
|---|---|---|---|
| `POST /v1/admin/avaliacoes/{avaliacao_id}/ocultar` | `avaliacoes_moderar` | `{motivo, explicacao (10–2000)}` | `OcultacaoOut` (`201`) |
| `POST /v1/admin/avaliacoes/{avaliacao_id}/reverter-ocultacao` | `avaliacoes_moderar` | `{motivo (10–2000)}` | `OcultacaoOut` (`200`) |
| `GET /v1/admin/avaliacoes/revisoes?status=&avaliacao_id=&limite=&deslocamento=` | `avaliacoes_moderar` | — | página de `RevisaoAvaliacaoAdminOut` (`limite` 1–200 padrão 50, `deslocamento` ≥ 0) |
| `POST /v1/admin/avaliacoes/revisoes/{revisao_id}/analisar` | `avaliacoes_moderar` | — | `RevisaoAvaliacaoAdminOut` (`200`) |
| `POST /v1/admin/avaliacoes/revisoes/{revisao_id}/decidir` | `avaliacoes_moderar` | `{status (aceita\|recusada), resposta (10–2000), ocultar_motivo?, mesmo_analista_justificativa? (10–1000)}` | `RevisaoAvaliacaoAdminOut` (`200`) |

Valores aceitos (`extra="forbid"` e `str_strip_whitespace=True` em todos os corpos):
- `motivo` / `ocultar_motivo`: `ofensa_ou_ilegal`, `dados_pessoais`, `sem_pedido_real_ou_falsa`, `nao_participou`, `ordem_judicial`.
- `status` (revisão): `aberta`, `em_analise`, `aceita`, `recusada`.
- `OcultacaoOut`: `id, avaliacao_id, motivo, explicacao, analista_id, ocultada_em, status_anterior, autor_avisado_em?, revertida_em?, revertida_por?`.
- `RevisaoAvaliacaoAdminOut`: `id, protocolo, avaliacao_id, tipo, ocultacao_id?, solicitante_id, justificativa, anexos[], canal, aberta_em, responder_ate, status, analista_id?, resposta?, mesmo_analista_justificativa?, decidida_em?, ocultacao_aplicada_id?`.

Regras, efeitos e códigos de erro:
- **Ocultar (`201`):** `404` se a avaliação não existe; `409` se já possui ocultação ativa. Auditoria: `avaliacao.ocultada` (entidade `avaliacoes`).
- **Reverter ocultação (`200`):** `404` se a avaliação não existe; `409` se não há ocultação ativa. Auditoria: `avaliacao.ocultacao_revertida` (entidade `avaliacoes`).
- **Iniciar análise (`200`):** passa a revisão para `em_analise` (`404` se inexistente, `409` se já decidida). Só registra auditoria (`avaliacao.revisao_em_analise`, entidade `avaliacao_revisoes`) quando muda de fato (`cod == "ok"`).
- **Decidir revisão (`200`, transacional):** `404` se inexistente; `409` se já decidida. Aceitar revisão `tipo = "revisao"` sem ocultação ativa exige `ocultar_motivo` (**422** se ausente) e aplica a ocultação na mesma transação; aceitar `tipo = "contestacao_ocultacao"` reverte a ocultação ativa na mesma transação. Contestação analisada pelo mesmo analista da ocultação exige `mesmo_analista_justificativa` (**422**, Termos 20.5). Repetição idempotente devolve `200` sem nova auditoria; quando decide (`cod == "ok"`), registra `avaliacao.revisao_decidida` (entidade `avaliacao_revisoes`, `motivo = resposta`).

## 9. Pedidos de titular LGPD

Prefixo `/v1/admin/lgpd/pedidos` (Termos 14.9 e 14.10). Código em `backend/src/trato/api/admin/rotas_lgpd_titular.py`. Todas as rotas respondem **503** quando a tabela ainda não existe no banco (`disponivel() == False`).

| Método e caminho | Permissão | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/admin/lgpd/pedidos?status=&tipo=&usuario_id=&limite=&deslocamento=` | `lgpd_revisao_automatizada` (todos os tipos exigem `lgpd_pedidos_gerenciar`) | — | página de `PedidoTitularAdminOut` (`limite` 1–200 padrão 50, `deslocamento` ≥ 0) |
| `POST /v1/admin/lgpd/pedidos/{pedido_id}/analisar` | `lgpd_revisao_automatizada` (outros tipos exigem `lgpd_pedidos_gerenciar`) | — | `PedidoTitularAdminOut` (`200`) |
| `POST /v1/admin/lgpd/pedidos/{pedido_id}/responder` | `lgpd_revisao_automatizada` (outros tipos exigem `lgpd_pedidos_gerenciar`) | `{status (atendido\|atendido_parcial\|negado), resposta (10–4000), motivo_nao_atendido? (10–2000), criterios_informados? (10–2000)}` | `PedidoTitularAdminOut` (`200`) |

Valores aceitos (`extra="forbid"` e `str_strip_whitespace=True` em `ResponderPedidoTitularIn`):
- `tipo`: `confirmacao`, `acesso`, `correcao`, `anonimizacao_bloqueio_eliminacao`, `portabilidade`, `eliminacao_consentimento`, `compartilhamento`, `nao_consentir`, `revogacao_consentimento`, `revisao_decisao_automatizada`.
- `decisao_automatizada`: `ocultacao_contato`, `documentos_rosto`, `alerta_fraude`, `ordem_resultados`, `outra`.
- `status` (pedido): `aberto`, `em_analise`, `aguardando_titular`, `atendido`, `atendido_parcial`, `negado`.
- `PedidoTitularAdminOut`: `id, protocolo, usuario_id?, contato?, tipo, decisao_automatizada?, referencia_tipo?, referencia_id?, descricao, canal, exclusao_id?, aberto_em, responder_ate, status, analista_id?, resposta?, motivo_nao_atendido?, criterios_informados?, respondido_em?`.

Regras, alcance e códigos de erro:
- **Alcance por papel (403):** quem tem apenas `lgpd_revisao_automatizada` (ex.: `seguranca`) só consulta e trata pedidos de `tipo = revisao_decisao_automatizada` — no `GET` sem `tipo`, o filtro é forçado para `revisao_decisao_automatizada`; informar outro `tipo` no `GET` ou agir em pedido de outro `tipo` em `/analisar` ou `/responder` responde **403**. Todos os tipos exigem `lgpd_pedidos_gerenciar` (`dpo`, `administrador`).
- **Validações em `/responder` (422):** `status` `atendido_parcial` ou `negado` exige `motivo_nao_atendido` (Termos 14.9); pedido de `tipo = revisao_decisao_automatizada` exige `criterios_informados` (Termos 14.10).
- **Conflitos e idempotência:** `404` se inexistente; `409` se o pedido já foi respondido. Repetição sem mudança de estado (`cod != "ok"`) devolve `200` sem duplicar auditoria.
- **Auditoria:** `lgpd.pedido_titular_em_analise` e `lgpd.pedido_titular_respondido` (entidade `lgpd_pedidos_titular`), gravando apenas metadados (`status`, `tipo`, `protocolo`), sem texto livre nem dados pessoais na trilha.

## 10. Impedimentos de cadastro e retorno de conta

Prefixo `/v1/admin/conta` (Termos 20.9) e extensão de encerramento em `/v1/admin/medidas`. Código em
`backend/src/trato/api/admin/rotas_retorno_conta.py` e `backend/src/trato/api/admin/rotas_medidas.py`.
Todas as rotas de `/v1/admin/conta` respondem **503** quando as tabelas ainda não existem no banco (`disponivel() == False`).

### Encerramento com impedimento em `POST /v1/admin/medidas` (`medidas_aplicar`)
- Novos campos de entrada (`AplicarIn`): `infracao_grave` (`bool`, padrão `false`), `impedir_nova_conta` (`bool`, padrão `false`) e `identificadores_impedimento` (`{cpf?, email?, telefone?}`, opcional). A saída (`MedidaAdminOut`) expõe `infracao_grave` e `impedir_nova_conta`.
- Regras: `infracao_grave = true` exige `tipo = "encerramento"` (**422** `infracao_grave_invalida`); `impedir_nova_conta = true` exige `infracao_grave = true` (**422** `impedimento_exige_grave`) e tabela de impedimentos disponível (**503** `indisponivel`).
- Os impedimentos são gravados como HMAC dos identificadores (`cpf`, `email`, `telefone`, lidos de `identificadores_impedimento` ou do cadastro do usuário) usando a variável de ambiente `CONTA_IMPEDIMENTO_PEPPER`; sem `CONTA_IMPEDIMENTO_PEPPER` configurada, responde **503** (`pepper_ausente`). Os identificadores brutos não são armazenados nem devolvidos.
- A auditoria `bloqueio.medida_aplicada` registra `infracao_grave`, `impedir_nova_conta` e `impedimentos_registrados` em `depois`.

### Rotas `/v1/admin/conta`

| Método e caminho | Permissão | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/admin/conta/impedimentos?medida_id=&apenas_ativos=false&limite=50&deslocamento=0` | `conta_retorno_analisar` | — | página de `ImpedimentoAdminOut` (`limite` 1–200, `deslocamento` ≥ 0) |
| `POST /v1/admin/conta/impedimentos/{impedimento_id}/revogar` | `conta_retorno_aprovar` | `{motivo (10–1000)}` | `ImpedimentoAdminOut` (`200`) |
| `GET /v1/admin/conta/retornos?status=&usuario_id=&limite=50&deslocamento=0` | `conta_retorno_analisar` | — | página de `PedidoRetornoAdminOut` (`limite` 1–200, `deslocamento` ≥ 0) |
| `POST /v1/admin/conta/retornos/{retorno_id}/analisar` | `conta_retorno_analisar` | — | `PedidoRetornoAdminOut` (`200`) |
| `POST /v1/admin/conta/retornos/{retorno_id}/aprovar` | `conta_retorno_aprovar` | `{motivo (10–2000), risco_identificado=false}` | `PedidoRetornoAdminOut` (`200`) |
| `POST /v1/admin/conta/retornos/{retorno_id}/recusar` | `conta_retorno_analisar` | `{motivo (10–2000), risco_identificado=false}` | `PedidoRetornoAdminOut` (`200`) |

Modelos e enums (`extra="forbid"` e `str_strip_whitespace=True` nos corpos):
- `status` (retorno): `aberto`, `em_analise`, `aprovado`, `recusado`.
- `ImpedimentoAdminOut`: `id, medida_id, tipo_identificador, criado_por, criado_em, revogado_em?, revogado_por?, motivo_revogacao?`.
- `PedidoRetornoAdminOut`: `id, protocolo, usuario_id, medida_id, justificativa_usuario, canal, status, solicitado_em, prazo_dias_aplicado, elegivel_a_partir_de, analista_id?, decisao_motivo?, risco_identificado, decidido_em?`.

Regras, erros e auditoria:
- **Revogar impedimento:** `404` se inexistente, `409` se já revogado. Auditoria: `conta.impedimento_revogado` (entidade `conta_impedimentos_cadastro`).
- **Analisar / aprovar / recusar retorno:** `404` se inexistente, `409` se já decidido. Em `/aprovar`, `risco_identificado = true` responde **422** (Termos 20.9). Repetições sem mudança (`cod != "ok"`) devolvem `200` sem duplicar auditoria.
- **Auditoria de retornos (entidade `conta_pedidos_retorno`):** `conta.retorno_em_analise`, `conta.retorno_aprovado` e `conta.retorno_recusado` (esta última registra `risco_identificado` em `depois`).

## 11. Contestações de nota de material

Prefixo `/v1/admin/materiais/contestacoes` (Termos 6.9). Código em `backend/src/trato/api/admin/rotas_materiais_contestacao.py`
e persistência em `backend/src/trato/persistencia/materiais_contestacao.py`. Todas as rotas respondem **503** quando a tabela
`nota_material_contestacoes` ainda não existe no banco (`disponivel() == False`).

**Nenhum dinheiro é movido por estas rotas.** `/aprovar-financeiro` só grava `aprovada_por` e marca
`efeito_financeiro = pendente_financeiro`; não executa estorno, compensação nem lançamento. O painel **não terá** o botão
dessa rota até decisão do João.

| Método e caminho | Permissão | Corpo | Resposta |
|---|---|---|---|
| `GET /v1/admin/materiais/contestacoes?status=&pedido_id=&limite=50&deslocamento=0` | `materiais_contestacao_analisar` | — | página de `ContestacaoMaterialAdminOut` (`limite` 1–200, `deslocamento` ≥ 0; menor `responder_ate` primeiro) |
| `POST /v1/admin/materiais/contestacoes/{contestacao_id}/analisar` | `materiais_contestacao_analisar` | — | `ContestacaoMaterialAdminOut` (`200`) |
| `POST /v1/admin/materiais/contestacoes/{contestacao_id}/decidir` | `materiais_contestacao_analisar` | `{status (procedente\|parcial\|improcedente), resposta (10–4000), valor_reconhecido_centavos? (inteiro ≥ 0)}` | `ContestacaoMaterialAdminOut` (`200`) |
| `POST /v1/admin/materiais/contestacoes/{contestacao_id}/aprovar-financeiro` | `materiais_contestacao_aprovar` | `{motivo (10–2000)}` | `ContestacaoMaterialAdminOut` (`200`) |

Modelos e enums (`extra="forbid"` e `str_strip_whitespace=True` nos corpos; `valor_reconhecido_centavos` é estrito: texto ou float dão **422**):
- `status` (contestação): `aberta`, `em_analise`, `procedente`, `parcial`, `improcedente`.
- `motivo` (da contestação): `nao_comprovado`, `diferente_do_combinado`.
- `efeito_financeiro`: `nenhum` (inicial), `pendente_financeiro`, `executado` (previsto no modelo; nenhuma destas rotas o grava).
- `ContestacaoMaterialAdminOut`: `id, protocolo, pedido_id, nota_id, item_id?, cliente_id, motivo, descricao, anexos[], valor_contestado_centavos, aberta_em, responder_ate, status, analista_id?, resposta?, valor_reconhecido_centavos?, decidida_em?, aprovada_por?, efeito_financeiro`.

Regras e códigos de erro (além de `401`, `403` e `503`; query, corpo ou limite inválido responde **422**):
- **Analisar:** passa para `em_analise` e grava o operador em `analista_id`. `404` se inexistente; `409` se já decidida.
- **Decidir:** pode partir de `aberta` ou `em_analise`; grava quem decidiu em `analista_id`, além de `resposta`, valor e `decidida_em`. Sem `valor_reconhecido_centavos`, `procedente` assume o valor contestado e `improcedente` assume zero; `parcial` exige valor maior que zero e menor que o contestado. `procedente` com valor diferente do contestado, `improcedente` diferente de zero ou `parcial` fora da faixa (ou sem valor): **422**. `404` se inexistente; `409` se já decidida com outro `status`, `resposta` ou valor.
- **Aprovar financeiro (4 olhos):** `404` se inexistente; `409` se não está `procedente` nem `parcial`; `403` se o aprovador é o `analista_id` (vale também para o administrador).
- **Idempotência:** repetições devolvem `200` sem nova auditoria: `/analisar` em contestação já `em_analise` (não troca o `analista_id`); `/decidir` com os mesmos `status`, `resposta` e valor (já com o padrão aplicado); `/aprovar-financeiro` em contestação que já tem `aprovada_por` (mantém o primeiro aprovador, mesmo que outra pessoa ou outro `motivo` seja enviado).
- **Auditoria (entidade `nota_material_contestacoes`):**
  - `material.contestacao_em_analise`: `depois = {status, protocolo}`; `motivo` automático com o protocolo.
  - `material.contestacao_decidida`: `depois = {status, protocolo, valor_reconhecido_centavos}`; `motivo = resposta`.
  - `material.contestacao_financeiro_aprovado`: `depois = {protocolo, efeito_financeiro, valor_reconhecido_centavos}`; `motivo` = o enviado no corpo.

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
