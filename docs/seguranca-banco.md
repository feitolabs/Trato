# Segurança do banco do Trato (F3.3 a F3.8)

> **Status: preparado e testado em banco local descartável. NADA foi aplicado no Supabase.**
> Cada migration abaixo precisa do OK explícito do João (regra do `CLAUDE.md`).
> Base: `docs/modelo-de-dados.md` (aprovado em 28/10/2026), escopo seções 3, 4, 8, 10, 11, 18, 19 e 22, `harness/DECISOES.md` e `harness/PENDENCIAS.md`.

Em português simples: o banco nasce **fechado**. O app (usuário logado) só **lê**, e só as linhas e colunas que a tela precisa.
Quem **escreve** é sempre o backend. O ledger (livro do dinheiro), as mensagens e a auditoria **não aceitam alteração nem exclusão**, nem do backend.

---

## 1. O que foi entregue

| Migration | Arquivo | Tabelas / objetos | Rollback |
|---|---|---|---|
| F3.3 | `20261029030000_f33_pedidos_orcamentos_contratos.sql` | `pedidos`, `pedidos_endereco`, `pedido_respostas`, `pedido_historico`, `midias`, `orcamentos`, `orcamento_itens`, `contratos` | `rollback/F3.3_rollback.sql` |
| F3.4 | `20261029030100_f34_execucao.sql` | `etapas`, `aditivos`, `notas_material`, `nota_material_itens`, `agendamentos`, `presencas` | `rollback/F3.4_rollback.sql` |
| F3.5 | `20261029030200_f35_dinheiro_ledger.sql` | `pagamentos`, `eventos_webhook`, `contas_ledger`, `lancamentos`, `partidas`, view `saldos_contas`, `repasses`, `chaves_pix`, `saques` | `rollback/F3.5_rollback.sql` |
| F3.6 | `20261029030300_f36_disputas_garantias_avaliacoes.sql` | `disputas`, `disputa_evidencias`, `garantias`, `retrabalhos`, `avaliacoes`, `avaliacao_criterios` | `rollback/F3.6_rollback.sql` |
| F3.7 | `20261029030400_f37_chat_notificacoes_auditoria.sql` | `conversas`, `mensagens`, `notificacoes`, `notificacao_preferencias`, `auditoria`, `registrar_auditoria()`, `verificar_cadeia_auditoria()` | `rollback/F3.7_rollback.sql` |
| F3.8a | `20261029030500_f38a_funcoes_auxiliares.sql` | schema `privado` com as funções das policies; privilégios padrão fechados | `rollback/F3.8a_rollback.sql` |
| F3.8b | `20261029030600_f38b_policies_rls.sql` | concessões por coluna + 48 policies de leitura + policy restritiva de conta bloqueada | `rollback/F3.8b_rollback.sql` |
| F3.8c | `20261029030700_f38c_storage.sql` | 4 buckets privados + 4 policies de leitura no Storage | `rollback/F3.8c_rollback.sql` |

Testes: `supabase/testes/testar_banco.py` (+ `banco_local.py`). Última saída completa: `supabase/testes/ultima_execucao.txt`.
Nenhuma migration insere dado de negócio (sem taxa, sem cidade, sem contas do ledger). A **única** exceção ao "só DDL" é o `INSERT` dos 4 buckets na F3.8c (infraestrutura do Storage, sem isso as policies não têm o que proteger).

---

## 2. Decisões de segurança

1. **Negar por padrão.** RLS ligado em todas as 48 tabelas do `public`. `anon` não tem nenhum privilégio em nenhuma tabela, view ou função.
2. **O app só lê (N11).** `authenticated` recebe apenas `SELECT`, por **coluna**. Não existe policy de `INSERT`/`UPDATE`/`DELETE`. Nem `TRUNCATE`.
3. **Colunas sensíveis ficam fora da concessão** (só o backend lê): hash dos códigos de 4 dígitos (`agendamentos`, só 10 mil combinações: o hash seria quebrado na hora), IP e dispositivo do aceite e custo do Stripe (`contratos`), pagador, meio, ids do Stripe e custos (`pagamentos`), texto **original** da mensagem (`mensagens.corpo`), lat/lng das mídias (o EXIF pode entregar a casa do cliente antes da contratação), CNPJ e reverificação (`perfis_profissional`), `status` e termos (`usuarios`), analista e fornecedor (`verificacoes`), avaliação interna do mediador (`disputas.procedente`, `relato_ma_fe`, `decidida_por`, `aprovada_por`), CPF e telefone de qualquer outra pessoa (`usuarios_privados` só do dono).
4. **Funções:** todas `SECURITY DEFINER` com `set search_path = ''`, nomes qualificados e `EXECUTE` revogado de `public` e `anon` (lição do `rls_auto_enable`). As funções das policies ficam no schema `privado`, que a API não expõe e ao qual `anon` nem tem `USAGE`. As funções de gatilho também têm o `EXECUTE` revogado. Só `registrar_auditoria` e `verificar_cadeia_auditoria` são executáveis (apenas pelo `service_role`).
5. **Privilégios padrão fechados (F3.8a).** Observado no projeto (leitura): tabelas novas nascem com `TRUNCATE`, `REFERENCES`, `TRIGGER` (e `MAINTAIN`) para `anon`, `authenticated` e `service_role`. A RLS **não** protege contra `TRUNCATE`. A F3.8a fecha o padrão e a F3.8b fecha as 15 tabelas da F3.2. Cada migration também declara os privilégios do `service_role` de forma explícita (só o que a tabela precisa; nunca `TRUNCATE`), então funciona com qualquer padrão da plataforma.
6. **Imutabilidade em duas camadas** (trigger que levanta exceção **e** `REVOKE`): `lancamentos`, `partidas`, `auditoria`, `mensagens` (só `lida_em` preenche uma vez), `pedido_historico`, `midias`, `presencas`, `nota_material_itens`, `disputa_evidencias`, `avaliacao_criterios`. Congelados por coluna: `contratos` (só o `status` muda), `config_*` aprovada, orçamento enviado, etapa ligada ao contrato, garantia, aditivo decidido, disputa decidida.
7. **Ledger de partidas dobradas.** `constraint trigger` adiado: no `COMMIT`, débitos = créditos e pelo menos 2 partidas. Partida só entra na transação em que o lançamento nasceu. Só o estorno corrige, e precisa **inverter exatamente** as partidas do original (um lançamento só é estornado uma vez, mesmo contrato). Idempotência única em lançamento, repasse, saque e pagamento. Saldo nunca é coluna: view `saldos_contas` (`security_invoker`, então a RLS vale para quem consulta).
8. **Auditoria com cadeia de hash (N16).** `registrar_auditoria()` serializa, numera e encadeia (`hash_anterior`, `hash`), com horário do servidor. `verificar_cadeia_auditoria()` acusa a primeira linha adulterada ou removida. Ação financeira, bloqueio e revelação de dado pessoal exigem motivo.
9. **Alçada (escopo 18.5).** Só mediador ativo decide disputa. Reembolso acima da alçada dele exige uma segunda pessoa (líder de suporte ou administrador), diferente de quem decidiu. Alçada nula vale como zero.
10. **Regras que o banco também checa (defesa em profundidade, além do backend):** cliente não orça o próprio pedido; só profissional aprovado e verificado envia orçamento; contrato só nasce de orçamento aceito, com o mesmo valor; só o cliente do contrato paga; chave Pix só com CPF/CNPJ do próprio dono; saque só para chave própria, ativa e verificada; check-out exige check-in; presença e mensagem usam a hora do servidor; só as partes escrevem no chat; webhook com assinatura inválida nunca é "processado".
11. **Conta bloqueada ou anonimizada não lê nada** (policy restritiva em todas as tabelas) e os pedidos abertos de cliente bloqueado somem para os profissionais.
12. **Storage:** buckets privados; sem policy de escrita (upload só por URL assinada do backend); documentos só `cadastro`; fotos do pedido e anexos de chat pela mesma regra de `midias`.

### Diferenças em relação ao modelo aprovado
Estão listadas, com o motivo, em `docs/modelo-de-dados.md`, seção 13. Resumo: CPF/telefone só do dono (equipe pelo backend, com auditoria); `perfis_publicos` virou concessão por coluna (sem view `SECURITY DEFINER`); `codigo` do ledger único por usuário; `midias.bucket`; contas de sistema do ledger sem seed; `notificacao_preferencias.atualizado_em`; N1 também consulta pedido/contrato/pagamento (escopo 18.5).

---

## 3. Quem lê e quem escreve (por tabela)

Legenda: **dono** = a própria linha; **parte** = cliente ou profissional do contrato; **backend** = `service_role`. Escrita do app: **nenhuma**, em todas as tabelas.
Equipe: N1/N2 = atendente_n1/n2; Lid = lider_suporte; Med = mediador; Fin = financeiro; Seg = seguranca; Cad = cadastro; Mod = moderador; Adm = administrador; Jur = juridico; DPO = dpo.

| Tabela | O app lê | Equipe lê | Escrita (backend) |
|---|---|---|---|
| `usuarios` | dono; profissionais aprovados; contraparte (só nome/foto) | qualquer papel | insert/update |
| `usuarios_privados` | **só o dono** | ninguém direto (backend, com motivo) | insert/update |
| `equipe` | própria linha | Adm | insert/update |
| `cidades`, `categorias`, `categoria_perguntas` | ativas | qualquer papel (inclui inativas) | insert/update |
| `perfis_profissional` | dono; perfis aprovados (sem CNPJ) | Cad, N1, N2, Lid, Med | insert/update |
| `profissional_categorias`, `profissional_regioes` | dono; de perfis aprovados | Cad | insert/update/delete |
| `verificacoes` | dono (sem analista/fornecedor) | Cad | insert/update |
| `verificacao_documentos` | **ninguém** (nem o dono) | **só Cad** | insert/update/delete |
| `config_definicoes/versoes/parametros/faixas_taxa` | ninguém | Fin, Jur, Adm | insert/update (rascunho)/delete (rascunho) |
| `pedidos` | dono; profissional contratado/que orçou/que conversou; profissional aprovado da categoria e região (se aberto) | N1, N2, Lid, Med, Fin, Seg | insert/update |
| `pedidos_endereco` | dono; profissional do contrato ativo **depois** de `liberado_em` | Seg (contrato ativo), Med (com disputa) | insert/update |
| `pedido_respostas`, `pedido_historico` | quem vê o pedido | (idem pedidos) | insert (+update respostas); histórico só insert |
| `midias` | por finalidade (pedido / chat / disputa / demais) | N2, Lid, Med, Seg (chat só Med com disputa) | só insert |
| `orcamentos`, `orcamento_itens` | autor (inclui rascunho); cliente do pedido (sem rascunho) | N1, N2, Lid, Med, Fin (sem rascunho) | insert/update/delete (só rascunho) |
| `contratos` | parte (sem IP, dispositivo e custo Stripe) | N1, N2, Lid, Med, Fin, Seg | insert; update só de `status` |
| `etapas` | parte do contrato; antes do aceite, quem vê o orçamento | N1, N2, Lid, Med, Fin | insert/update |
| `aditivos`, `notas_material`, `nota_material_itens` | parte | N2, Lid, Med, Fin (aditivo também N1) | insert/update; itens só insert |
| `agendamentos` | parte (sem hash dos códigos) | N1, N2, Lid, Med, Fin, Seg | insert/update |
| `presencas` | parte | N2, Lid, Med, Fin, Seg | só insert |
| `pagamentos` | parte (colunas limitadas, sem pagador/meio/custos) | N1, N2, Lid, Med, Fin | insert/update |
| `eventos_webhook` | ninguém | Fin | insert/update (só retorno do processamento) |
| `contas_ledger` | só as contas do próprio usuário | Fin | insert/update |
| `lancamentos`, `partidas` | só os que tocam a conta do próprio usuário | Fin | **só insert**; nunca update/delete |
| `saldos_contas` (view) | só as contas do próprio usuário | Fin | — |
| `repasses` | profissional dono | Fin, Med | insert/update |
| `chaves_pix` | **só o dono** (chave completa) | ninguém direto | insert/update |
| `saques` | profissional dono | Fin | insert/update |
| `disputas` | parte (sem avaliação interna) | N2, Lid, Med, Fin | insert/update |
| `disputa_evidencias` | parte (só as visíveis) | N2, Lid, Med (todas, com nota interna); Fin (só visíveis) | só insert |
| `garantias`, `retrabalhos` | parte | Med | insert/update |
| `avaliacoes`, `avaliacao_criterios` | pública: nota do cliente ao profissional; nota do profissional ao cliente só ele, o avaliador e o profissional que o atende | Mod (todas) | insert; update só resposta/status |
| `conversas` | parte | Med (com disputa) | insert/update |
| `mensagens` | parte, **só `corpo_exibido`** | Med (com disputa), **sem** o original | insert; só `lida_em` muda, uma vez |
| `notificacoes`, `notificacao_preferencias` | dono | ninguém | insert/update |
| `auditoria` | ninguém | Adm, DPO, Seg, Jur | só por `registrar_auditoria()` |

Quem **não** pode (conferido nos testes): N1 não vê documentos, ledger, saques, chat nem endereço; Med não vê ledger nem saques; Fin não vê chat nem endereço; Cad não vê pedidos, pagamentos nem contratos; Mod não vê nada financeiro.

---

## 4. Evidência dos testes (banco local descartável)

Ambiente: Postgres 16.2 embutido (`pgserver`), stubs de `auth.uid()` (lê o JWT por `set_config`), roles `anon`/`authenticated`/`service_role`, `storage.buckets/objects`. Reprodução:

```bash
python -m venv /fora/do/projeto/venv && /fora/do/projeto/venv/bin/pip install pgserver psycopg2-binary pglast
/fora/do/projeto/venv/bin/python -I -X utf8 supabase/testes/testar_banco.py . /pasta/temporaria real
```

Resultado (cada rodada aplica as 10 migrations em ordem, roda a suíte, desfaz tudo com os rollbacks, reaplica e roda a suíte de novo):

| Modo | Verificações | Falhas |
|---|---|---|
| `real` (privilégios padrão **observados** no projeto) | **574 OK** | 0 |
| `permissivo` (padrão antigo do Supabase; sem a parte de rollback) | **279 OK** | 0 |
| Sintaxe (`pglast`) em 20 arquivos `.sql` | 20 OK | 0 |
| `harness/verificar.py` (segredos, backend, app) | TUDO OK | 0 |

Resumo por assunto (saída curta):

- **(a) A não lê o que é de B:** pedido, endereço, orçamento, chat, anexo, pagamento, contrato, saldo, extrato, CPF/telefone, notificação. OK.
- **(b) Profissional e endereço:** vê o pedido aberto da categoria e cidade certas **sem** endereço; outra categoria, outra cidade e profissional em análise não veem nada; contratado mas com `liberado_em` nulo não vê; depois de liberado vê; quem orçou e perdeu nunca vê; contrato cancelado tira o acesso. OK.
- **(c) Documentos:** `cadastro` lê (tabela e Storage); N1, N2, Med, Fin, Seg, Adm, DPO, o próprio profissional, cliente e `anon` não. OK.
- **(d) Ledger:** `UPDATE`/`DELETE`/`TRUNCATE` falham para o dono e para o `service_role`; partida desequilibrada, lançamento com uma partida só ou sem partidas, partida zero, partida em lançamento fechado e chave de idempotência repetida são recusados; estorno correto passa e devolve o saldo; estorno que não inverte, em outro contrato ou repetido é recusado. OK.
- **(e) Mensagens e auditoria:** não editam nem apagam (dono e `service_role`); `lida_em` preenche uma vez; auditoria só entra por `registrar_auditoria`, a cadeia de hash fecha e **detecta** adulteração e remoção de linha. OK.
- **(f) Configuração e contrato:** versão aprovada não muda nem se apaga; contrato só muda `status`. OK.
- **(g) Superfície:** `anon` não lê nenhuma das 49 tabelas/views, não tem privilégio algum, não executa nenhuma função; nenhuma policy usa `using (true)`; nenhuma função `SECURITY DEFINER` sem `search_path` vazio nem executável pelo app; o app não tem `INSERT/UPDATE/DELETE/TRUNCATE` em tabela nenhuma; `service_role` lê tudo, grava onde deve e nunca faz `TRUNCATE`. OK.
- **(h) Rollback:** para cada migration (F3.8c até F3.3) o estado do banco depois do rollback é **idêntico** ao de antes dela (tabelas, colunas de privilégio, funções, gatilhos, policies, índices, restrições, buckets, privilégios padrão); reaplicar reproduz o mesmo estado; a suíte inteira passa de novo no banco reconstruído. OK.

Estado do Supabase conferido só por leitura (29/10/2026): 2 migrations aplicadas (F3.2 e a revogação do `rls_auto_enable`); 15 tabelas, sem dados; advisor de segurança só com 15 avisos `INFO` (RLS sem policy, esperado até a F3.8b).

---

## 5. Riscos que restam

| # | Risco | O que fazer |
|---|---|---|
| R1 | **Leitura direta pela equipe não gera log no banco** (RLS não registra leitura). Vale para `verificacao_documentos` e para o Storage de documentos (`cadastro`). O escopo exige "quem, quando e por quê". | O painel deve entregar documentos por URL assinada do **backend**, que chama `registrar_auditoria` (`dado_pessoal.revelado`, com motivo). Opção mais segura: tirar a policy de leitura da equipe e deixar só o backend. **Decisão do João.** |
| R2 | **Dono do banco e `service_role` comprometidos.** Triggers e `REVOKE` barram o backend, mas o dono da tabela (`postgres`) pode desligar trigger. | Guardar a string de conexão do `postgres` fora do backend; o backend usa só `service_role`. A cadeia de hash da auditoria denuncia adulteração depois. Rotina periódica chamando `verificar_cadeia_auditoria()`. |
| R3 | **`select *` do app falha** nas tabelas com coluna escondida (`permission denied`). | Regra para o app: sempre listar as colunas. Já combinar com a sessão do app/backend. |
| R4 | **Realtime e GraphQL.** Não foi testado se o Realtime entrega colunas sem permissão de `SELECT`. | Não ligar Realtime em `mensagens`, `agendamentos`, `pagamentos` e `contratos` antes de testar no projeto real. Desligar `pg_graphql` se não for usado. |
| R5 | **Texto livre** (`pedidos.titulo/descricao`, `pedido_respostas`) pode conter endereço ou telefone e é visível ao profissional antes da contratação. | Mascarar no backend ao criar o pedido (como no chat). |
| R6 | **EXIF das fotos** (a coluna `lat/lng` fica oculta, mas o arquivo pode carregar GPS). | Backend remove EXIF no envio. |
| R7 | **Código de 4 dígitos** guardado como hash tem só 10 mil possibilidades; o cliente não consegue "rever" o código se só existe o hash. | Hash com segredo do servidor (HMAC), limite de tentativas e expiração; mostrar o código ao cliente só na criação. |
| R8 | **CPF em texto puro** em `usuarios_privados`. | Avaliar criptografia em repouso (Vault/pgsodium) com o DPO. |
| R9 | **JWT de conta bloqueada** vale até expirar. A RLS já nega leitura, mas o backend precisa banir a sessão no Auth. | Fluxo de bloqueio no backend: `status`, banir no Auth, auditoria. |
| R10 | **Alçada por reembolso, não por "valor decidido".** Decisão `liberar_tudo` (valor vai ao profissional) não passa por segunda pessoa. | Confirmar a definição de alçada (P/N abaixo). |
| R11 | **Desempenho não medido.** Policies chamam funções por linha; `auditoria` usa lock consultivo (grava uma por vez). | Medir com volume antes do piloto; índices já existem para os caminhos principais. |
| R12 | **Não testado:** PostgREST/Storage reais, JWT real do Supabase, `pg_graphql`, Realtime, `EXCLUDE` de faixas da taxa (precisa de `btree_gist`, que já está no projeto), Postgres 17 (testei no 16). | Rodar `get_advisors` e uma checagem de acesso com dois usuários reais logo depois de aplicar a F3.8b. |
| R13 | `restrito` ainda lê (só `bloqueado` e `anonimizado` são barrados). | Confirmar o significado de "restrito". |
| R14 | Sem seed das contas do ledger, da taxa e das cidades. | Dependem de P2, P3, P4, P6, P7, P8. Cada seed pede OK. |

---

## 6. Pontos para advogado e contador (o agente não decide)

- **Retenção** de documentos, selfie e antecedentes criminais (`verificacao_documentos.excluir_em` fica em branco): prazo, base legal e descarte (N10).
- **Direito ao esquecimento (LGPD) × imutabilidade** de mensagens, auditoria, ledger e contratos: como anonimizar sem apagar (o modelo prevê só `usuarios.status = 'anonimizado'`).
- **Guardar e ler o texto original das mensagens** (`mensagens.corpo`, N9): quem pode, por quanto tempo, com que registro.
- **Custódia do valor retido** e uso de instituição de pagamento autorizada; **nota fiscal** da taxa; **chargeback** de 7 dias (D3) e saldo negativo (N7); **responsabilidade solidária (CDC)**.
- **Biometria e dados sensíveis** (selfie, antecedentes): consentimento (`verificacoes.consentimento_lgpd_em` existe), finalidade e fornecedor (P10).
- **Registro de acesso a dado pessoal pela equipe** e **acesso temporário com justificativa** (escopo 22.4): o banco só prepara a trilha; o procedimento é do DPO/jurídico.
- **Prazo de guarda da auditoria e dos logs**.

---

## 7. Decisões de regra de negócio usadas como provisórias (não inventei)

| Ref. | Uso nas migrations |
|---|---|
| P1 | `repasses.liberar_em` sem valor padrão; nenhum prazo no banco |
| P2 | `config_faixas_taxa` vazia; nada calcula taxa no banco |
| P3 | `contratos.liquido_profissional_centavos` e `pagamentos.acrescimo_cliente_centavos` aceitos, sem fórmula |
| P4 | `orcamentos.sinal_material_centavos`; gatilho `sinal_material` em `repasses` |
| P7, P8 | Sem contas de sistema e sem fundo/reserva; `retrabalhos.custo_centavos` só registra |
| P10, P11 | `verificacoes.fornecedor_ref`, `notificacoes.canal` sem provedor |
| N1 | Papel único por usuário na `equipe`; ser profissional = ter `perfis_profissional` |
| N8 | Região = cidade com bairro opcional |
| N9 | `corpo` + `corpo_exibido`; original ilegível para o app; `lida_em` único |
| N10 | `excluir_em` sem prazo |
| N11 | App só lê; escrita pelo backend |
| N12 | `pedidos_endereco.liberado_em` gravado pelo backend |
| N16 | Cadeia de hash na auditoria (implementada) |
| 18.5 | Alçada: mediador decide; reembolso acima do teto dele exige líder de suporte ou administrador; teto nulo = zero |
| (novo) | Convenção do prefixo da ação da auditoria (`financeiro.`, `pagamento.`, `repasse.`, `saque.`, `estorno.`, `reembolso.`, `bloqueio.`, `dado_pessoal.`) para exigir motivo: **confirmar** |
| (novo) | Buckets: 10 MB (5 MB no avatar) e tipos de arquivo: **confirmar** |

---

## 8. PLANO DE APLICAÇÃO

**Ordem (não pode mudar):** F3.3 → F3.4 → F3.5 → F3.6 → F3.7 → F3.8a → F3.8b → F3.8c. Cada uma depende da anterior.
Aplicar uma de cada vez, pelo `apply_migration`, com o texto do arquivo, **depois do seu OK**. O Supabase registra a versão com a hora da aplicação; o arquivo local é renomeado para essa versão (como foi feito na F3.2).
Depois da F3.8b: rodar `get_advisors` e a checagem de acesso com dois usuários reais.
Entre a F3.3 e a F3.8b as tabelas novas ficam **fechadas** (RLS sem policy): é seguro parar em qualquer ponto.
Todas as migrations são só estrutura: sem dados de negócio.

---

PRECISO DO SEU OK
**O que:** aplicar a migration **F3.3** (`20261029030000_f33_pedidos_orcamentos_contratos.sql`): cria 8 tabelas (`pedidos`, `pedidos_endereco`, `pedido_respostas`, `pedido_historico`, `midias`, `orcamentos`, `orcamento_itens`, `contratos`), 2 funções genéricas de proteção, gatilhos de imutabilidade e conferência do total do orçamento. Contrato guarda `config_versao_id` e `regras_aplicadas` congelados.
**Por que:** é a base do fluxo (pedido → orçamento → contrato).
**Risco:** baixo. Só DDL, sem dados. Tabelas nascem com RLS ligado e sem acesso para o app.
**Como desfazer:** `supabase/rollback/F3.3_rollback.sql` (apaga as 8 tabelas; só antes de existir dado real).
**Posso continuar?**

---

PRECISO DO SEU OK
**O que:** aplicar a **F3.4** (`20261029030100_f34_execucao.sql`): `etapas`, `aditivos`, `notas_material`, `nota_material_itens`, `agendamentos`, `presencas` (check-in e check-out), com hora do servidor e itens de nota imutáveis.
**Por que:** execução do serviço, prova de presença e nota de material (D8, D9).
**Risco:** baixo. Só DDL; depende da F3.3.
**Como desfazer:** `supabase/rollback/F3.4_rollback.sql`.
**Posso continuar?**

---

PRECISO DO SEU OK
**O que:** aplicar a **F3.5** (`20261029030200_f35_dinheiro_ledger.sql`): `pagamentos`, `eventos_webhook`, `contas_ledger`, `lancamentos`, `partidas` (ledger imutável com equilíbrio conferido no `COMMIT`), view `saldos_contas`, `repasses`, `chaves_pix`, `saques`. **Não cria contas do ledger** (depende de P7/P4/P8).
**Por que:** guardar o dinheiro com partidas dobradas e só estorno como correção.
**Risco:** **médio, pelo peso da tabela, não pela operação**: depois que houver lançamento real, a F3.5 não pode mais ser desfeita sem perder o livro. Convém revisar o desenho do ledger antes (seção 2, item 7).
**Como desfazer:** `supabase/rollback/F3.5_rollback.sql` (só antes de haver dinheiro real; depois, nunca).
**Posso continuar?**

---

PRECISO DO SEU OK
**O que:** aplicar a **F3.6** (`20261029030300_f36_disputas_garantias_avaliacoes.sql`): `disputas` (com regra de alçada e segunda pessoa), `disputa_evidencias`, `garantias`, `retrabalhos`, `avaliacoes`, `avaliacao_criterios`; fecha as chaves `repasses.congelado_por_disputa_id` e `lancamentos.disputa_id`.
**Por que:** disputa com valor congelado (D7), garantia e avaliações.
**Risco:** baixo a médio. A regra de alçada é provisória (seção 7); o João confirma depois sem refazer tabela (só a função `disputas_validar`).
**Como desfazer:** `supabase/rollback/F3.6_rollback.sql`.
**Posso continuar?**

---

PRECISO DO SEU OK
**O que:** aplicar a **F3.7** (`20261029030400_f37_chat_notificacoes_auditoria.sql`): `conversas`, `mensagens` (imutáveis), `notificacoes`, `notificacao_preferencias`, `auditoria` com cadeia de hash, `registrar_auditoria()` e `verificar_cadeia_auditoria()` (só `service_role`).
**Por que:** chat sem edição nem exclusão (escopo 11.2) e trilha que ninguém apaga.
**Risco:** baixo. Mensagens e auditoria não se apagam nem se editam; qualquer correção é por registro novo. Confirme a convenção de prefixos da ação (seção 7).
**Como desfazer:** `supabase/rollback/F3.7_rollback.sql` (só antes de haver dado real).
**Posso continuar?**

---

PRECISO DO SEU OK
**O que:** aplicar a **F3.8a** (`20261029030500_f38a_funcoes_auxiliares.sql`): cria o schema `privado` com as funções que as policies usam e **fecha os privilégios padrão** do schema `public` (tabelas novas deixam de nascer com `TRUNCATE`/`REFERENCES`/`TRIGGER` para `anon` e `authenticated`).
**Por que:** as policies precisam das funções; e a plataforma deixa `TRUNCATE` aberto por padrão, que a RLS não barra.
**Risco:** médio-baixo. A mudança de padrão vale para **todas as tabelas futuras** do `public`: quem criar tabela nova precisa conceder acesso de forma explícita. Isso é o desejado, mas muda o hábito.
**Como desfazer:** `supabase/rollback/F3.8a_rollback.sql` (apaga o schema `privado` e devolve o padrão antigo; faça antes o rollback da F3.8b).
**Posso continuar?**

---

PRECISO DO SEU OK
**O que:** aplicar a **F3.8b** (`20261029030600_f38b_policies_rls.sql`): tira os privilégios que as 15 tabelas da F3.2 têm hoje (`TRUNCATE` etc.), dá ao `service_role` só o necessário, concede `SELECT` por coluna ao app e cria as 48 policies de leitura + a policy restritiva de conta bloqueada.
**Por que:** é a abertura controlada do app. Sem ela ninguém do app lê nada.
**Risco:** **o mais importante de revisar.** Policy errada vira vazamento. Está coberta por 574 verificações locais (seção 4), mas o ambiente real ainda não foi testado. Também passa a valer a regra "o app lista as colunas" (R3).
**Como desfazer:** `supabase/rollback/F3.8b_rollback.sql` (apaga todas as policies e fecha o app de novo; devolve às 15 tabelas o padrão anterior).
**Posso continuar?**

---

PRECISO DO SEU OK
**O que:** aplicar a **F3.8c** (`20261029030700_f38c_storage.sql`): cria 4 buckets **privados** (`verificacao`, `pedido-midias`, `chat-anexos`, `avatar`) com limite de 10 MB (5 MB no avatar) e tipos de arquivo, e 4 policies de **leitura** no Storage. É o único `INSERT` de todo o pacote (infraestrutura, não dado de negócio).
**Por que:** documentos só do cadastro; fotos e anexos só de quem pode ver o pedido; nada público.
**Risco:** baixo. Limites e tipos são provisórios.
**Como desfazer:** `supabase/rollback/F3.8c_rollback.sql` (remove as policies; os buckets só podem ser apagados vazios, pelo painel ou pela API do Storage).
**Posso continuar?**

---

## 9. Ordem recomendada para o João aprovar

1. Ler a seção 5 (riscos) e a seção 7 (provisórias) e decidir **R1** (leitura de documentos pela equipe) e **R10** (alçada). São as duas que podem mudar o SQL.
2. Aprovar **F3.3 e F3.4** (estrutura simples).
3. Aprovar **F3.6 e F3.7**.
4. Aprovar **F3.5** (ledger) por último dentro do bloco de tabelas, depois de olhar o desenho do ledger.
   *(A ordem de aplicação continua F3.3 → F3.4 → F3.5 → F3.6 → F3.7: a F3.6 depende da F3.5. Aprove na ordem que quiser, mas aplique nessa sequência.)*
5. Aprovar **F3.8a, F3.8b e F3.8c** nessa ordem. Rodar `get_advisors` e o teste com dois usuários reais ao final.
6. Só então os seeds (taxa, cidades, contas do ledger), que dependem de P2, P3, P4, P6, P7 e P8.
