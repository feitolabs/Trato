# Revisão de segurança e de correção do Trato

> Revisão feita em 29/10/2026, na branch `claude/revisao-seguranca-df4e31` (a partir de `develop`).
> **Só leitura de código + testes novos.** Nenhum código-fonte foi alterado. Nada foi escrito em banco real e nenhum serviço externo foi chamado (só consultas de leitura ao PyPI e ao pub.dev para as dependências).
> Os testes que reproduzem os achados críticos e altos estão em `backend/tests/api/test_revisao_seguranca_xfail.py` (todos `xfail(strict=True)`: hoje falham, de propósito).

Em português simples: o desenho de segurança do banco é bom (RLS fechada, colunas escondidas, ledger imutável). Os problemas graves estão **entre o backend e o banco**: o dinheiro ainda mora em memória, e as regras de dinheiro do backend e as do banco não batem.

## Resumo

| Gravidade | Qtde | Itens |
|---|---|---|
| Crítico | 1 | C1 |
| Alto | 8 | A1 a A8 |
| Médio | 14 | M1 a M14 |
| Baixo | 8 | B1 a B8 |

Como ler: `arquivo:linha` é onde está o problema. "Teste" é o `xfail` que reproduz (rode com `pytest --runxfail <arquivo>::<teste>` para ver a falha de verdade).

**Ordem sugerida de correção:** C1 → A3/A5/A7 (dinheiro) → A1/A2 (autorização) → A4 (antes de ligar o ledger ao banco) → A6 → A8 → médios.

---

## CRÍTICO

### C1. Em modo Postgres, ledger, disputas, garantias, avaliações e eventos do webhook ficam em memória
- **Onde:** `backend/src/trato/api/fabrica.py:76-79` (e a docstring das linhas 7-10 admite). O roteador de pagamento (`api/rotas_pagamento.py`, `instalar_pagamento`) **nunca é ligado** na fábrica (`fabrica.py`, `app.py:14-21`); só os testes o ligam.
- **Cenário:** com `TRATO_PERSISTENCIA=postgres`, o webhook `payment_intent.succeeded` muda o pedido para `pago_retido` **no banco**, mas o lançamento da cobrança vai para o `LedgerEmMemoria`. Depois:
  1. O servidor reinicia (deploy, crash): o pedido está "pago", o ledger está vazio. Reembolso, repasse e disputa não têm de onde tirar o valor (`SaldoInsuficiente`/`EstornoInvalido`).
  2. Com 2 workers do uvicorn, cada processo tem o seu ledger e o seu "evento já processado": o webhook cai num worker, o cliente consulta o saldo noutro e vê R$ 0.
  3. O estado de dedupe do webhook (`EventosWebhookEmMemoria`) some no restart: o Stripe reenvia o evento (até 3 dias) e ele é processado de novo.
  4. Disputas abertas somem no restart; o valor "congelado" some junto.
  5. `POST /v1/pedidos/{id}/cobranca`, `/aditivos` e `/disputa/decisao` **não existem** em produção (404).
- **Como reproduzir:** teste `test_c1_modo_postgres_nao_guarda_dinheiro_em_memoria` (monta o contexto Postgres sem conectar e confere os tipos dos repositórios).
- **Correção:** implementar `LedgerPostgres` (tabelas `lancamentos`/`partidas`/`pagamentos`/`eventos_webhook` da F3.5, com `unique(provedor, evento_id)`), `DisputasPostgres`, `GarantiasPostgres`, `AvaliacoesPostgres`; ligar `ServicoPagamento` na fábrica; **recusar subir** com `TRATO_AMBIENTE=producao` se algum repositório de dinheiro for em memória. Os repositórios de pagamento (`cobrancas`, `aditivos`, `termos`) também são só em memória (`pagamentos/memoria.py`) e precisam de tabela.

---

## ALTO

### A1. Código de 4 dígitos do check-in/check-out sem limite de tentativas
- **Onde:** `backend/src/trato/pedidos/estados.py:479-481` (`_exigir_codigo`) e `api/rotas_pedidos.py:164-200` (`mudar_estado`). Não existe contador de erros nem rate limit em nenhum lugar do backend.
- **Cenário:** o profissional abre `fazer_check_out` e tenta `0000`, `0001`… até acertar. São 10 mil combinações: minutos com um script. Resultado: conclui o serviço sem o cliente presente; depois do prazo de confirmação o dinheiro é liberado. Vale também para o check-in (prova de presença). O banco guarda só o hash, mas isso não ajuda: o ataque é pela API.
- **Reproduzir:** teste `test_a1_codigo_certo_e_recusado_depois_de_muitos_erros` (30 erros seguidos e o código certo ainda passa com 200).
- **Correção:** contador de tentativas por agendamento (ex.: 5 erros bloqueiam por 15 min e avisam o cliente e o suporte); registrar cada erro na auditoria; rate limit por usuário e IP na borda; considerar 6 dígitos. Tabela/colunas: `agendamentos.tentativas_codigo`, `bloqueado_ate`.

### A2. Qualquer usuário de equipe lê pedido, saldo, extrato, cobranças e chat (a matriz de permissões do painel é contornada)
- **Onde:** `api/servicos.py:13-16` (`eh_participante` devolve `True` para `PapelUsuario.EQUIPE`, sem olhar o papel real nem `Permissao`); usado por `rotas_pedidos.py` (ver, eventos), `rotas_financeiro.py:85-118` (saldo, extrato), `rotas_pagamento.py:143-153` (cobranças, aditivos) e `rotas_app.py:212-245` (pagamento). `rotas_app.py:276-285` (`_conversa_do_pedido`) deixa a equipe ler qualquer conversa passando `?profissional_id=`.
- **Cenário:** um moderador, um atendente N1, o jurídico ou o cadastro (papéis que a matriz em `api/admin/papeis.py` e o `docs/seguranca-banco.md` §3 proíbem de ver dinheiro e chat) chama `GET /v1/pedidos/{id}/extrato` ou `/mensagens?profissional_id=…` com o próprio token e lê tudo. O painel esconde, a API não. Também não há auditoria dessa leitura (R1 do doc de banco).
- **Pior caso, a decisão da disputa:** `POST /v1/pedidos/{id}/disputa/decisao` (`api/rotas_pagamento.py:216-267`) só exige `PapelUsuario.EQUIPE`. Qualquer subpapel (até moderador ou jurídico) decide a disputa e move dinheiro, com a alçada **global** da configuração (não a do operador, `equipe.alcada_centavos`), sem segunda pessoa (a docstring diz "não implementado") e sem registro na auditoria. A rota correta é a do admin (`rotas_disputas.py`, com `DISPUTAS_DECIDIR`, alçada própria e auditoria); a do app deveria ser removida.
- **Reproduzir:** testes `test_a2_equipe_sem_permissao_nao_le_financeiro[saldo|extrato]`, `test_a2_equipe_sem_permissao_nao_le_chat` e `test_a2_equipe_sem_permissao_nao_decide_disputa`.
- **Correção:** nas rotas de uso do app, equipe só passa por `exigir(Permissao.…)` do admin (`api/admin/contexto.py`): `PAGAMENTOS_VER` para saldo/extrato/cobranças, `PEDIDOS_BUSCAR` para o pedido, e chat só `mediador` com disputa. Em `eh_participante` trocar `return True` por `False` e mover o acesso da equipe para `/v1/admin/...` com auditoria.

### A3. Taxa recalculada na decisão da disputa, fora da versão congelada do contrato
- **Onde:** `api/admin/rotas_disputas.py:214-217` usa `contexto.taxa.calcular(restante)`; `persistencia/app_extras.py:87-96` (`TaxaPostgres`) lê a **versão vigente** da configuração. No caminho do orquestrador, `pagamentos/orquestrador.py:308` cai em `self.config().taxa` (vigente) quando não acha `termos`, e os `termos` só são gravados **depois** da transição (`orquestrador.py:273`, gancho), em memória (C1). O contrato do banco tem `taxa_bps_aplicada`/`taxa_trato_centavos`/`config_versao_id` congelados (`persistencia/contratos.py:90-91,134`), mas o domínio `Contrato` (`api/repositorios.py:34-47`) não carrega a taxa e ninguém a lê de volta.
- **Cenário:** o contrato é aceito com 10% (R$ 1.000 → taxa R$ 100). O financeiro publica uma nova versão com 25%. A disputa é decidida (`liberar_tudo`): o espelho lança taxa de R$ 250. O profissional recebe R$ 150 a menos do que o contrato prometeu; o contrato (hash do documento) diz outra coisa. Escopo: "taxa congelada no aceite".
- **Reproduzir:** teste `test_a3_taxa_da_disputa_nao_muda_se_a_config_mudar_depois_do_aceite` (mesmo contrato, config muda: taxa lançada vai de 10.000 para 25.000).
- **Correção:** ler `contratos.taxa_bps_aplicada` (e a regra de arredondamento/mínimo da `config_versao_id` do contrato) e passar para `repartir_custodia`; nunca chamar `ProvedorTaxa` fora da calculadora do orçamento. Gravar os termos **na mesma transação** do aceite.

### A4. O ledger do Python e o do banco divergem (vai quebrar quando forem ligados)
- **Onde:** `financeiro/ledger.py:55-62` (`TipoLancamento`: `liberacao`, `gorjeta`, `retencao`…) x `supabase/migrations/20261029030200_f35_dinheiro_ledger.sql` (CHECK de `lancamentos.tipo`: `cobranca, retencao, taxa, custo_stripe, repasse, reembolso, estorno`). E `ledger.py` `estornar_pedido` (estorno **parcial**, proporcional) x gatilho `ledger_conferir_equilibrio` (estorno tem de **inverter exatamente** as partidas do original) + `estorna_id unique` (um original só é estornado uma vez).
- **Cenário:** ao trocar `LedgerEmMemoria` pelo ledger do banco: (a) `liberar()` e `registrar_gorjeta()` falham com `check_violation`; (b) uma disputa com `reembolso_parcial` (25%) gera estorno de R$ 250 sobre cobrança de R$ 1.000 e o banco recusa; (c) o modelo do banco não tem a conta `a_liberar → liberado` por lançamento do mesmo jeito. O dinheiro fica preso em meio de transação.
- **Reproduzir:** testes `test_a4_tipos_do_ledger_python_cabem_no_check_do_banco` e `test_a4_estorno_parcial_do_python_cabe_no_banco`.
- **Correção:** escolher um modelo só. Opção: estorno parcial = estorno do original **mais** novo lançamento da parte mantida; ou permitir estorno parcial no banco (valor ≤ restante) com gatilho que confere a soma. Alinhar o enum `TipoLancamento` ao CHECK (ou o contrário) e ter **um teste que roda o mesmo cenário nos dois ledgers**.

### A5. A trava de idempotência da decisão de disputa compara o campo errado e trava a disputa para sempre
- **Onde:** `api/admin/rotas_disputas.py:203`: `any(i.id.startswith(prefixo) …)`. `Lancamento.id` é um uuid; o prefixo `disputa/<pedido>/` está em `Lancamento.chave`.
- **Cenário:** o admin decide `reembolso_parcial`. O ledger recebe os lançamentos (linha 251), a gravação do pedido falha (banco caiu). O admin repete: a trava nunca dispara, o plano é refeito sobre o ledger já alterado e dá `ChaveReutilizada` (409) em `disputa/<pedido>/rep/retencao` (valores diferentes com a mesma chave). A disputa não decide mais; o dinheiro já se mexeu pela metade.
- **Reproduzir:** teste `test_a5_refazer_a_decisao_nao_planeja_dinheiro_de_novo` (levanta `ChaveReutilizada`).
- **Correção:** trocar por `i.chave.startswith(prefixo)` e, melhor, fazer ledger + disputa + pedido + auditoria numa **única transação** (C1). Se já existe o prefixo, devolver o resultado gravado.

### A6. Sem controle de concorrência: transições do pedido e do dinheiro são "ler, decidir, gravar"
- **Onde:** `persistencia/pedidos.py:204` (`update public.pedidos set status = %s where id = %s and status <> %s`: não confere o estado **anterior**); rotas `rotas_pedidos.py:164-200`, `:257`, `:334`, `rotas_pagamento.py:216-266`, `rotas_disputas.py:297-328` (lêem o pedido, validam, gravam sem trava); `ledger.py` `Livro.lancar_varios` copia a lista e depois a troca (sem lock em `Livro`; o lock fica só no `LedgerEmMemoria`), e `ServicoPagamento._planejar` lê fora do lock; `orquestrador.py:299` gera a chave `din/{pedido}/{n}` com `n = len(lançamentos)` (duas chamadas simultâneas geram a mesma chave ou chaves diferentes para o mesmo efeito).
- **Cenário:** o cliente toca "confirmar conclusão" e, ao mesmo tempo, o sistema/outra aba envia "abrir disputa" (ou "cancelar"). As duas leem `em_confirmacao`, ambas passam na máquina de estados, as duas gravam; vence a última. Resultado possível: pedido `concluido` com disputa aberta e dinheiro já repartido, ou repartição duas vezes pelo ledger em memória. O FastAPI roda rotas `def` em threads, então a corrida é real.
- **Reproduzir:** o teste `test_a6_atualizacao_do_pedido_confere_o_estado_anterior` só confere o SQL (estático). A corrida em si precisa de Postgres e threads: dois `POST /v1/pedidos/{id}/acoes/confirmar_conclusao` e `/disputa` com `threading.Barrier`, ou duas conexões executando `salvar` com o mesmo estado de origem.
- **Correção:** `update … where id = %s and status = %s` (compare-and-set com o estado lido) e erro 409 se `rowcount = 0`; `select … for update` do pedido dentro da transação; no ledger do banco, `lancamentos.chave_idempotencia unique` + tudo na mesma transação; a chave de `aplicar_dinheiro` deve vir de dado estável (id do evento/decisão), não de `len()`.

### A7. Estorno no Stripe antes de gravar no ledger: se o ledger falha, o dinheiro saiu e o sistema não sabe
- **Onde:** `pagamentos/orquestrador.py:289-322` (`aplicar_dinheiro`, `_estornar_no_provedor` 317-336). Ordem: planeja → **estorna no Stripe** (e já soma `estornado_centavos` na cobrança, em memória) → `ledger.lancar_varios`.
- **Cenário:** o Stripe devolve R$ 500 ao cliente; a gravação no ledger falha (ou o processo morre). Na retentativa, `parte = min(falta, valor - estornado_centavos)` dá 0 para a cobrança já estornada, sobra `falta` e o código levanta `ErroFluxo("Não há pagamento confirmado suficiente…")`. O cliente já recebeu, o ledger não registra, e a ação nunca mais conclui. O Stripe é idempotente pela `Idempotency-Key` por 24 h, mas o estado local não é.
- **Reproduzir:** teste `test_a7_falha_no_ledger_depois_do_estorno_pode_ser_repetida` (o ledger falha uma vez; a repetição devolve 409 em vez de 200).
- **Correção:** padrão "intenção primeiro": gravar a ordem de estorno (`repasses`/`pagamentos` com estado `estorno_pedido`) **antes** de chamar o Stripe; chamar o Stripe com chave derivada do id da ordem; tratar o webhook `charge.refunded` (hoje não faz nada, ver M3) como a confirmação que fecha o lançamento no ledger.

### A8. Documentos, selfie e antecedentes: equipe de cadastro lê direto no Storage, sem registro de quem viu
- **Onde:** `supabase/migrations/20261029030700_f38c_storage.sql:35-36` e `…030600_f38b…sql:135-136` (`eh_equipe('cadastro')` lê `verificacao_documentos` e o bucket `verificacao` inteiro). O próprio `docs/seguranca-banco.md` lista como R1. Retenção: `verificacao_documentos.excluir_em` sem regra (N10).
- **Cenário:** um analista de cadastro com token válido baixa 5 mil documentos (RG, selfie) pelo Storage/PostgREST. O banco não registra leitura; o escopo exige "quem, quando e por quê". Um token de equipe roubado vaza a base inteira de documentos.
- **Reproduzir:** o teste `test_a8_equipe_nao_le_documentos_direto_no_storage` confere a existência da policy (estático). Para ver o efeito: com um usuário de cadastro de teste, `select` em `verificacao_documentos` e `GET` do objeto; não executado aqui (sem banco real).
- **Correção:** tirar a policy de leitura da equipe; entregar só por URL assinada **do backend** (60 s) que chama `registrar_auditoria('dado_pessoal.revelado', motivo)`; limitar volume por operador/hora; definir `excluir_em` (a decisão jurídica é do João/advogado).

---

## MÉDIO

### M1. Webhook: o valor pago pode não ser conferido
`pagamentos/orquestrador.py:190`: `if evento.valor_centavos is not None and … != cobranca.valor_centavos`. Se o evento vier sem `amount` inteiro (`stripe_formato.py` `_inteiro` devolve `None`), a conferência é pulada e a cobrança vira paga. Também usa `amount` e não `amount_received` (pagamento parcial/captura menor). O handler simples (`api/webhook_pagamento.py:53`) usa `amount_received` e está certo.
*Correção:* exigir valor inteiro e igual; comparar `amount_received`.

### M2. Webhook com valor divergente responde 422 e o Stripe repete por dias
`orquestrador.py:191` levanta `ErroFluxo(…, 422)`; a chave de idempotência é liberada (`idempotencia.py`) e o Stripe reenvia por até 3 dias, sem alerta. *Correção:* guardar o evento como `divergente`, responder 200 e abrir alerta para o financeiro.

### M3. `charge.refunded` não faz nada
`orquestrador.py:237` (`_estorno_confirmado`) é vazio. Reembolso feito no painel do Stripe (ou falha de estorno assíncrono do Pix) não entra no ledger: o saldo no Trato fica maior que o dinheiro real. *Correção:* conciliar: se o estorno não veio de uma ordem nossa, lançar o estorno no ledger e abrir alerta.

### M4. Duas fontes da taxa e mínimo ignorado no caminho Postgres
`pagamentos/taxa.py:34-43` (`calcular_taxa`: percentual **ou o mínimo**, nunca acima do valor) x `persistencia/contratos.py:21-23,90` e `persistencia/app_extras.py:92-96` (só bps da faixa, **sem mínimo**, sem teto). A calculadora do profissional (`rotas_app.py:254-266`) usa um caminho, o contrato outro e a liquidação outro. A regra "base 7,5%, mínima configurável" (CLAUDE.md) não está no caminho que vai ao banco. *Correção:* um único serviço de taxa que recebe a versão de configuração e é usado nos três lugares; teste de igualdade.

### M5. Liquidação (`payout.paid`/`transfer.paid`) libera dinheiro por um evento genérico
`orquestrador.py:240-260` + `stripe_formato.py:11-17`: qualquer evento assinado com `metadata.cobranca_id` ou `transfer_group = <pedido>` move `a_liberar → liberado` sem conferir valor nem destinatário. Hoje depende do modelo de contas (P7). *Correção:* só liberar com evento ligado a uma ordem de repasse nossa (valor e conta batendo).

### M6. Conta bloqueada continua lendo o Storage, e a policy restritiva não cobre tabelas futuras
`…f38b…sql:245-254`: o `loop` cria `conta_ativa_obrigatoria` só nas tabelas que existem **hoje** em `public`; tabela criada depois nasce sem ela. As policies de `storage.objects` (`…f38c…sql`) não chamam `privado.conta_ativa()`. O JWT bloqueado vale até expirar (R9). *Correção:* policy restritiva também em `storage.objects`; checagem no teste de superfície ("toda tabela de `public` tem a restritiva"); banir sessão no Auth ao bloquear.

### M7. Quem perdeu o orçamento continua vendo o pedido e o histórico dele
`…f38a…sql:144-175` (`pode_ver_pedido`): `exists (select … from orcamentos where profissional_id = auth.uid())` sem filtrar por status; a mesma função libera `pedidos`, `pedido_respostas` e `pedido_historico` (policy `…f38b…:149-156`). O histórico (`prova` em JSON) guarda motivo, descrição de disputa, localização e foto do check-in do profissional que ganhou. O doc de banco só garante que o perdedor não vê o endereço.
*Como confirmar:* usuário B com orçamento `recusado` no pedido de A fecha contrato com C; `select prova from pedido_historico where pedido_id = …` como B. Não executado aqui.
*Correção:* após o contrato, o perdedor só vê o pedido se `p.status = 'aberto'`; `pedido_historico` só para as partes e a equipe.

### M8. Fotos: o EXIF só é removido no app; o backend não tem rota de upload
`app/lib/dispositivo/preparador_imagem.dart` recodifica em JPEG (bom), mas é confiança no cliente. `servico_upload.dart` espera "o backend assina uma URL de envio", e **não existe** rota assim no backend (nenhum `signed`/`upload` em `backend/src`). O R6 do doc de banco diz "backend remove EXIF no envio": hoje é só intenção. O bucket aceita HEIC/PNG/WebP/PDF sem tratamento; as fotos do pedido (`finalidade='pedido'`) são visíveis a qualquer profissional aprovado da região (`pode_ver_midia`), com GPS no arquivo se o cliente alterar o app. Os caminhos de verificação só são validados pelo prefixo do usuário (`rotas_app.py:401-407`): não confere se o arquivo existe, o tipo, nem o tamanho.
*Correção:* processar a imagem no backend (descartar EXIF, reencodar, calcular sha256) ao confirmar o upload; só então gravar em `midias`.

### M9. Texto livre sem mascaramento nem limite
`rotas_app.py:158-159` (`comentario` até 1000, `etiquetas` sem limite de tamanho por item), título/descrição do pedido (R5) e comentários podem conter telefone/endereço. O chat mascara, o resto não. *Correção:* mascarar na entrada e limitar `etiquetas` (ex.: lista fechada).

### M10. Aceite sem IP e sem dispositivo
`persistencia/contratos.py:135,155` grava `aceite_ip`/`aceite_dispositivo` do `Contrato`, mas `rotas_pedidos.py:164-200` monta o `Contrato` sem esses campos; ficam sempre nulos. A prova do aceite (escopo 18) fica sem IP. *Correção:* ler IP (atrás de proxy: só de `X-Forwarded-For` de proxy confiável) e user-agent/dispositivo na rota e preencher.

### M11. Nada cria `public.usuarios` no cadastro (bloqueio de funcionamento)
Não há trigger em `auth.users` nem rota no backend que insira em `public.usuarios` (só o seed de exemplo, comentado). `UsuariosPostgres.perfil` devolve `None` e a API responde 401 para qualquer pessoa recém-cadastrada. Não é falha de segurança (falha fechada), mas impede o uso. *Correção:* trigger `security definer` em `auth.users` (com `search_path=''`) ou rota `/v1/me` que cria com o `sub` do token. Cuidado para o **papel nunca vir** de `raw_user_meta_data` (o cliente controla esse campo).

### M12. Sem rate limit, sem CORS configurado, `/docs` e `/openapi.json` públicos
Nenhum `slowapi`/limite, `CORSMiddleware`, `TrustedHostMiddleware` ou desligar docs em produção (`api/app.py`, `fabrica.py`). Endpoints de escrita (mensagens, avaliação, verificação, A1) ficam abertos a abuso. *Correção:* limite na borda (gateway) e por usuário; docs desligados com `TRATO_AMBIENTE=producao`; CORS só para o painel.

### M13. Sessão do app em `SharedPreferences` e backup do Android ligado
`app/pubspec.yaml`: `supabase_flutter` guarda a sessão (refresh token) por padrão em `SharedPreferences`, em texto. `AndroidManifest.xml` não define `android:allowBackup="false"`: o backup do Android pode copiar o token. Não há `flutter_secure_storage`. *Correção:* `allowBackup=false` (ou regras de exclusão), `flutter_secure_storage` como `localStorage` do Supabase (`FlutterAuthClientOptions`).

### M14. `--dart-define-from-file=.env` pode embutir segredo no app
`.env.example` e `docs/login-configuracao.md` mandam usar `--dart-define-from-file=.env`. Se alguém apontar para o `.env` **da raiz** (que tem `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_URL`, `STRIPE_SECRET_KEY`), todos viram constantes do APK/IPA (extraíveis). O doc pede um `.env` só com 4 chaves, mas nada impede o erro. *Correção:* no `verificar.py` (ou no CI de build) recusar `--dart-define*` com nome que contenha `SERVICE_ROLE`, `SECRET`, `DATABASE_URL`; guardar o `.env` do app em `app/.env.app` (e no `.gitignore`).

---

## BAIXO

- **B1. JWT sem verificar `iss`.** `api/auth_supabase.py:45-51`: confere assinatura, `exp`, `sub` e `aud`, e o algoritmo vem de uma lista fixa (sem `none`, sem confusão HS/RS). Falta `issuer=f"{SUPABASE_URL}/auth/v1"`. Baixo porque a chave é do projeto.
- **B2. Colunas internas expostas por `grant select` na tabela inteira** (`…f38b…sql:51-67`): `repasses.provedor_transferencia_id`, `congelado_por_disputa_id`, `lancamentos.criado_por`/`descricao`, `aditivos.decidido_por`, `retrabalhos.custo_centavos`. Não há segredo, mas é dado interno. *Correção:* concessão por coluna.
- **B3. Erro do banco devolve mensagem do gatilho** (`persistencia/erros.py:46`): `RegraDoBanco(erro.diag.message_primary)` pode incluir uuids ("Lançamento %…"). Devolver texto fixo e registrar o detalhe.
- **B4. Webhook: dedupe só na memória e tolerância de 300 s** (`pagamentos/webhook.py`, `idempotencia.py`). Resolve com C1. O HMAC compara em tempo constante: ok.
- **B5. `alter default privileges` vale só para objetos criados pelo papel que roda a migration** (`…f38a…sql:21-23`). Tabela criada por outro papel (painel do Supabase, extensão) ainda nasce aberta. Cobrir com um teste "toda tabela de `public` tem RLS e nenhum grant a `anon`" no CI.
- **B6. Carteira: papel único** (`persistencia/usuarios.py:49-56`: equipe > profissional > cliente). Quem é profissional não pode abrir pedido como cliente com a mesma conta. Decisão de produto.
- **B7. Cobrança por cartão** (`stripe_teste.py:107`) cria o PaymentIntent sem `automatic_payment_methods`/3DS explícito e sem `capture_method`; revisar na entrada do modo real (hoje só aceita `sk_test_`: bom).
- **B8. CI e dependências** (`.github/workflows/*.yml`): as ações estão **fixadas por SHA** e `permissions: contents: read` (bom). Faltam: `pip-audit` e `flutter pub outdated` no CI, Dependabot, e lock com hash do backend (`pip install -e backend[dev]` resolve versões novas a cada rodada; `pyproject.toml` usa só `>=`). O `build.yml` entrega `SUPABASE_ANON_KEY` ao APK debug (chave pública: ok). Nenhum segredo no texto dos workflows.

---

## O que está bom (conferido)

- **Webhook:** HMAC-SHA256 do `t.payload` com `compare_digest`, tolerância de tempo, assinatura inválida/ausente = 400, corpo bruto usado (`api/rotas_webhook.py`, `pagamentos/webhook.py`). "Pago" só nasce no webhook assinado (D13).
- **JWT:** algoritmo escolhido de lista fixa, `exp`+`sub` obrigatórios, `aud=authenticated`, papel lido do **banco** a cada chamada, conta bloqueada = 401.
- **IDOR por pedido:** `carregar_pedido` devolve 404 para quem não é parte (cliente/profissional); `listar_orçamentos` filtra o profissional; chat do profissional é sempre a conversa dele.
- **Arredondamento:** tudo em `int`, meio para cima uma vez, `bool` recusado, divisão de estorno por maior resto sem perder centavo (`ledger.repartir_proporcional`).
- **Banco:** RLS em todas as tabelas, `anon` sem nada, `SECURITY DEFINER` com `search_path=''`, funções de policy em schema não exposto, colunas sensíveis fora do `grant`, ledger/auditoria/mensagens imutáveis por gatilho + `REVOKE`, cadeia de hash na auditoria, sem `using (true)`.
- **Segredos:** `.env` ignorado, `.env.example` sem valores, `SecretStr` na configuração, o provedor Stripe recusa chave que não seja de teste, nenhuma chave no código.
- **Permissões do app:** só câmera e localização "em uso", sem segundo plano; sem deep link/intent-filter além do launcher (login por `idToken`, sem redirect).

---

## Varreduras e ferramentas (item 6 e 7 do pedido)

| Verificação | Resultado |
|---|---|
| `python harness/verificar.py --etapa segredos` | OK: nenhum segredo, `.env` ignorado |
| Histórico git (154 commits, `git log --all -p -G<padrões>`: `sk_live_`, `sk_test_…`, `rk_*`, `whsec_…`, JWT `eyJ…eyJ`, `AKIA…`, `ghp_`, `github_pat_`, `AIza…`, chave privada PEM, `postgres://usuário:senha@`, `xox*`) | Só 2 ocorrências, ambas código/teste que **checa** o prefixo `sk_live_` (`78d4dc1`, `c2fd598`); nenhum valor real |
| Arquivos sensíveis já adicionados em qualquer commit (`.env`, `.pem`, `.p12`, `.jks`, `keystore`, `google-services`, `.key`) | Nenhum |
| `pip-audit` (39 pacotes do venv do backend: fastapi 0.162, starlette 1.10, pyjwt 2.15.1, psycopg 3.3.6, cryptography 50.0.2, …) | Nenhuma vulnerabilidade conhecida. Rodado em venv temporário **fora** do projeto, com `--no-deps --disable-pip` |
| `flutter pub outdated` | 15 dependências com versão nova que o `pubspec` impede (ex.: `permission_handler_android` 12.1.0 → 14.1.1, `google_sign_in_ios` 5.9.0 → 6.3.8, `shared_preferences_foundation`); 5 travadas no `pubspec.lock` abaixo do resolvível. Sem aviso de segurança associado (o Dart não tem ferramenta tipo `pip-audit`) |
| Workflows | Ações fixadas por SHA, `contents: read`, sem segredo em texto. Ver B8 |

## O que NÃO foi possível verificar

1. **Painel admin (`admin/`)**: a pasta não existe nesta branch (está em outra, ainda não integrada). Não revisei segredos embutidos, `--dart-define`, armazenamento de token nem rotas do painel. Só revisei a **API** do painel (`backend/src/trato/api/admin/`) por leitura.
2. **Supabase real**: não consultei o projeto (nem `get_advisors`). Tudo sobre o banco vem da leitura das migrations; **nenhuma policy foi exercitada**. Os achados M7 e A8 precisam de teste com dois usuários reais depois de aplicar a F3.8b. Também não testei Realtime, GraphQL, JWT real do Supabase nem PostgREST (já listados como R4/R12 no doc de banco).
3. **Suíte SQL (`supabase/testes/testar_banco.py`, `pgserver`)**: não rodei nesta revisão (não alterei o banco nem as migrations). Os testes de integração do backend (`tests/integracao`) também não foram reexecutados por mim além do que o `verificar.py` roda.
4. **Concorrência (A6)**: descrita e localizada no código, mas **não** reproduzida com threads/duas conexões (o ambiente de teste é em memória e a corrida só aparece com Postgres real).
5. **Stripe**: nenhuma chamada real; o formato dos eventos vem do código e dos testes, não de eventos capturados.
6. **App**: não rodei o app em aparelho. Não verifiquei `nonce` do login Google/Apple (`signInWithIdToken`), regras de senha/limite de tentativas de login (são do Supabase Auth), ofuscação/ProGuard, `ATS` do iOS além das chaves de permissão, nem o `Info.plist` completo.
7. **Logs com dado pessoal**: o código não tem `logging`/`print` com dado pessoal (`print` só em `margem/relatorio.py`), mas **não revisei** a configuração de log do uvicorn/proxy, que pode registrar URL e IP, nem o log do Supabase.
8. **Retenção LGPD**: não há prazo definido no código nem no banco (N10); é decisão do advogado/DPO.
9. **Infra**: HTTPS, firewall, rotação de chaves, limite de taxa no gateway e backups estão fora do repositório.

## Como rodar os testes de reprodução

```bash
cd backend
python -m pytest tests/api/test_revisao_seguranca_xfail.py -q -rx          # 13 xfailed (problemas existem)
python -m pytest tests/api/test_revisao_seguranca_xfail.py -q --runxfail    # mostra cada falha
```

Quando um achado for corrigido, o teste vira `XPASS` e, por ser `strict`, **derruba a suíte**: tire a marca `xfail` e mantenha o teste como proteção.
