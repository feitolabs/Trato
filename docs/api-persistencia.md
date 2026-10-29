# API: persistência no Postgres (Supabase)

O backend tem dois modos, escolhidos por `TRATO_PERSISTENCIA` no `.env`:

| Modo | Para quê | O que usa |
|---|---|---|
| `memoria` (padrão) | testes rápidos | repositórios em `trato/api/memoria.py`; sem contexto ligado as rotas respondem 503 |
| `postgres` | desenvolvimento/produção | repositórios em `trato/persistencia/`, `DATABASE_URL`, auth com o JWT do Supabase |

A fábrica é `trato.api.fabrica`: `criar_app_da_config()` (usada por `trato/main.py`) e
`criar_contexto_postgres(banco, config)` (monta o `Contexto`; os testes usam esta).
Os repositórios em memória **continuam** e são o que a suíte rápida (`backend/tests/api`) usa.

## O que o João precisa fornecer (só no `.env` dele, nunca no git nem no chat)

| Variável | O que é | Onde pegar |
|---|---|---|
| `TRATO_PERSISTENCIA` | `postgres` para ligar o banco | — |
| `DATABASE_URL` | URL de conexão ao Postgres | Supabase > Settings > Database > Connection string |
| `SUPABASE_JWT_SECRET` **ou** `SUPABASE_JWKS_URL` | validar o token do usuário | JWT secret (HS256) ou `https://<projeto>.supabase.co/auth/v1/.well-known/jwks.json` (chaves assimétricas) |
| `TRATO_CODIGO_SEGREDO` | segredo dos códigos de check-in/out | gerar um valor longo e aleatório; **não trocar depois** (os códigos são recalculados dele) |
| `TRATO_BANCO_PAPEL` | papel de cada transação (padrão `service_role`) | normalmente não precisa mexer |

Não é preciso a `service_role key` da API REST: o backend fala direto com o Postgres. O
`service_role` aqui é o **papel do Postgres**, assumido a cada transação (`set local role`), o que
limita o backend aos privilégios que as migrations deram a ele.

### Antes de ligar no banco real (depende do João)

1. **Aplicar as migrations** pendentes (F3.5 a F3.8 estão só preparadas). Com `service_role` o backend
   precisa dos privilégios das tabelas da F3.2, que **só chegam na F3.8b**. A F3.8b depende da F3.5
   e da F3.6. Enquanto elas não estiverem aplicadas, o caminho é conectar com o usuário dono do
   projeto e deixar `TRATO_BANCO_PAPEL=` vazio (menos seguro: o dono pode desligar gatilhos).
2. **Publicar a configuração versionada** (`config_versoes` vigente) com ao menos:
   `adiantamento_bps`, `prazo_resposta_disputa_horas`, `prazo_decisao_disputa_dias_uteis`,
   `prazo_congelar_disputa_horas`, mais as **faixas de taxa** (`config_faixas_taxa`, decisão P2).
   Sem isso a API responde **503** ("configuração não publicada") em vez de usar um número do código.
   Opcionais (sem eles o prazo fica "não configurado"): `validade_pedido_horas`,
   `prazo_pagamento_pendente_horas`, `prazo_confirmacao_cliente_horas`,
   `tolerancia_comparecimento_horas` (**chave nova**, precisa de linha em `config_definicoes`),
   `garantia_retrabalho_dias_padrao`, `prazo_retrabalho_atendimento_dias`.
3. **Decidir a taxa "progressiva"** (P2): hoje a taxa da faixa vale para o valor **inteiro**
   (`persistencia/config.py: taxa_bps_da_faixa`). Se for por degrau, é uma função só.
4. **Escrever no banco real exige o OK do João** (CLAUDE.md). Nada aqui foi rodado nele.

## Rodar

```bash
cd backend
py -3.11 -m venv .venv
.venv/Scripts/python -m pip install -e ".[dev]"
# modo postgres:
#   no .env: TRATO_PERSISTENCIA=postgres e as variáveis da tabela acima
.venv/Scripts/python -m uvicorn trato.main:app --reload
```

## Testes

```bash
.venv/Scripts/python -m pytest -q                    # tudo (integração roda se o pgserver existir)
.venv/Scripts/python -m pytest -q -m "not integracao" # só os rápidos, em memória
.venv/Scripts/python -m pytest tests/integracao -q   # só a integração
```

`tests/integracao/` sobe um **Postgres local descartável** (`pgserver`, pasta temporária, apagado no
fim) e aplica as migrations F3.2, F3.3, F3.4 e F3.7 (stubs do Supabase vêm de
`supabase/testes/banco_local.py`). Sem `pgserver` instalado, os testes são **pulados**. Nunca
tocam no Supabase. O que cobrem: criar pedido → orçamento → aceite/contrato → pagamento (ator
sistema) → agendamento → check-in/out → conclusão → conversa → notificação → auditoria e a
verificação da cadeia (incluindo detecção de adulteração); JWT (assinatura, validade, audiência,
`alg=none`, papel vindo do banco, conta bloqueada); privilégios do `service_role`; configuração
ausente (503).

## Como as peças se encaixam

- **Conexão** (`persistencia/conexao.py`): pool psycopg 3; `Banco.transacao()` abre uma transação
  curta, assume o papel, faz COMMIT. Os gatilhos adiados (total do orçamento e da nota) disparam
  no COMMIT e o erro também é traduzido. `prepare_threshold=None` (compatível com o pooler do
  Supabase em modo transação).
- **Erros** (`persistencia/erros.py` e `api/erros.py`): `NaoEncontrado` 404, `Duplicado` 409,
  `RegraDoBanco` 409 (gatilho/restrição), `DadosInvalidos` 422, `ConfigNaoPublicada` 503,
  `BancoIndisponivel` 503. A mensagem do Postgres de uma restrição `CHECK` não vaza.
- **Pedido** (`persistencia/pedidos.py`): `salvar` grava pedido + histórico + auditoria + agendamento
  + presença **numa transação** e devolve o pedido como ficou. Estado `pago_e_retido` do domínio =
  `pago_retido` no banco. O app só vê "pago" quando o ator **sistema** (webhook assinado) grava a
  transição; as rotas continuam recusando `confirmar_pagamento` do cliente.
- **Aceite** (`persistencia/contratos.py`): aceita o orçamento (os outros enviados viram
  `recusado`), calcula taxa/líquido/adiantamento com a configuração **vigente**, congela as regras
  (`regras_aplicadas`, `config_versao_id`, `hash_documento`) e vincula as etapas. Gravar de novo o
  mesmo contrato não duplica. A rota grava o contrato **antes** do pedido: se faltar configuração,
  o pedido continua aberto.
- **Códigos de check-in/out**: o banco guarda só o HMAC. O backend recalcula o código do
  `TRATO_CODIGO_SEGREDO` + id do agendamento para mostrá-lo ao cliente e conferi-lo. O código nunca
  entra no `pedido_historico` (a prova é gravada sem ele, com `codigo_validado`).
- **Hora do servidor**: `presencas.registrada_em`, `mensagens.enviada_em` e `notas_material.enviada_em`
  são do banco. Por isso `check_in_em`/`check_out_em` do pedido carregado vêm do banco, não do
  relógio injetado.
- **Auditoria**: toda transição e o aceite chamam `registrar_auditoria` na **mesma transação**.
  `AuditoriaPostgres.verificar_cadeia()` devolve `None` (íntegra) ou o id da 1ª linha adulterada.
- **Leitura**: nenhum `select *`; as consultas listam as colunas (hashes de código, `corpo` original
  da mensagem e dados pessoais nunca saem por estes repositórios).
- **Auth** (`api/auth_supabase.py`): valida assinatura, `exp` (obrigatório) e `aud=authenticated`;
  aceita só HS256 (com segredo) e RS256/ES256 (com JWKS); `sub` = `usuarios.id`; papel = equipe
  ativa > profissional aprovado > cliente; conta fora de `ativo`/`restrito` não entra.

## Limites conhecidos (pendências)

- **Em modo `postgres`, ledger, disputas, garantias e eventos de webhook seguem em memória**: as
  tabelas (F3.5/F3.6) não estão no banco e a F3.5 está sendo refeita (caminho A, D15). Reiniciar
  perde esses dados; não usar assim em produção.
- **Pagamento/webhook**: não mudou (modo teste, `manipuladores_webhook` vazio). Falta o manipulador
  que traduz o evento assinado em `confirmar_pagamento`.
- **Conta com dois papéis** (profissional que também contrata): hoje vale o papel mais alto
  (profissional). Falta o app dizer com qual papel está agindo.
- **Retrabalho/remarcação**: a remarcação cria novo agendamento (o antigo vira `remarcado`), mas o
  retrabalho reaproveita o agendamento e não gera novo código de conclusão (um 2º check-out violaria
  `unique(agendamento, tipo)`). `expirar_pagamento` reabre o pedido, mas o contrato fica no banco.
- **Rotas que ainda não existem**: enviar orçamento, chat, notificações, etapas, aditivos e notas de
  material têm repositório e teste, mas **não rota HTTP** (o app ainda não as pede). Limite de
  orçamentos por pedido e janela de validade também não estão aplicados.
- **Chaves de configuração novas/provisórias**: `tolerancia_comparecimento_horas`; máscara de
  contato nas mensagens (N9) é uma regex simples.
- `expira_em` e `orcamentos_ate` do pedido ficam vazios (dependem de `validade_pedido_horas`).
