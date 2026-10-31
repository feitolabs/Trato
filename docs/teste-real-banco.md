# Teste real contra o Supabase (backend em `postgres`) — 31/10/2026

Backend subido da worktree com `TRATO_PERSISTENCIA=postgres` em `127.0.0.1:8000` (`.env` copiado do repo principal,
git-ignorado, valores nunca impressos). Stripe em modo teste.

## Dados de teste criados no banco (rodada 2, com OK do João)

Criados por `python harness/teste_real_fluxo.py setup` e `fluxo`. Todos com prefixo `teste_`; e-mails `@example.test`.

| O quê | Quantidade | Detalhe |
|---|---|---|
| Usuários no Supabase Auth + `public.usuarios` | 4 | `teste_cliente`, `teste_profissional`, `teste_admin`, `teste_financeiro` (@example.test) |
| `equipe` | 2 | admin (administrador) e financeiro |
| Config versionada **vigente** (valores de TESTE) | 1 versão, 10 parâmetros, 1 faixa | taxa 7,5% (750 bps) em qualquer valor; **não é decisão de taxa**; motivo começa com `teste_` |
| Cidade / categoria / pergunta | 1 / 1 / 1 | `teste_Cidade`, `teste_Pintura` (seeds reais ficam intactos) |
| Pedido + orçamento + contrato | 1 / 1 / 1 | pedido "teste_ Pintar a sala", orçamento de 10000 centavos aceito |
| Stripe | nada criado | a cobrança parou antes (achado 7) |
| Ledger, `eventos_webhook`, `pagamentos` | 0 | |

Estado antes: todas essas tabelas com 0 linhas (exceto seeds: `contas_ledger` 4, `categorias` 3, `categoria_perguntas` 15, `cidades` 1).

**Como limpar (só o João, como dono):** rode `docs/teste-real-banco-limpeza.sql` no SQL Editor do Supabase. Ele desliga gatilhos
só na transação (`session_replication_role = replica`), apaga as tabelas que estavam vazias, as linhas `teste_*` e os usuários
`teste_*@example.test`. Não toca nos seeds. **Não executei** esse SQL e não testei o `replica` neste banco; se o Supabase negar, apague
os usuários pelo painel (Authentication) e peça-me uma limpeza por outra via. Depois confira: tabelas voltam a 0, `contas_ledger` 4, `categorias` 3, `cidades` 1.

## O que passou

| Verificação | Resultado |
|---|---|
| Backend sobe com Postgres real | OK. `GET /saude` = 200 (`supabase_configurado: true`, `stripe_modo_teste: true`). **Não existe `/health`**, só `/saude`. |
| Conexão ao Supabase (`DATABASE_URL`, PostgreSQL 17.11) | OK, leitura em transação `read_only` |
| Rotas protegidas sem token | OK: `/v1/me`, `/v1/pedidos`, `/v1/catalogo/*`, `/v1/admin/config/vigente` dão 401 |
| Webhook sem assinatura / assinatura inválida | OK: 400 "Assinatura do webhook inválida." (nada gravado) |
| Migrations aplicadas x `supabase/migrations/` | Nomes batem para as 13 primeiras (versões/timestamps diferem: o Supabase regravou os números; sem impacto) |
| `transfer.paid` | Corrigido (abaixo), com teste |

## Migrations: o que falta no banco

Aplicadas (16): f32, revogar_execute, f33, f34, f37, f35, f36, f38a/b/c, `seed_cidade_categorias_contas_ledger`,
notificacoes_dispositivos_agendador, ordens_estorno, fix_acesso, pedido_recusas, profissional_disponibilidade_portfolio_uploads.

**Faltam** (existem em `develop`, não no banco):
- `20261030140000_b2_grants_por_coluna.sql`
- `20261030140000_upload_destino_portfolio.sql`

**Diferença de rastreio:** a migration `seed_cidade_categorias_contas_ledger` está aplicada no banco (cidade BH inativa,
3 categorias, 4 contas do ledger) mas **não existe como arquivo em `supabase/migrations/`** (os seeds estão em `supabase/seeds/`).

## Estado dos dados (contagens)

`usuarios` 0, `equipe` 0, `config_definicoes` 0, `config_versoes` 0, `contas_ledger` 4, `categorias` 3,
`cidades` 1 (Belo Horizonte, `ativa = false`), `pedidos` 0, `lancamentos` 0, `eventos_webhook` 0.

**Falta antes de qualquer pagamento funcionar:** seed 2 (config/taxa), que depende de (a) primeiro administrador em `equipe`
(+ um segundo membro para a aprovação dupla), (b) valores de `taxa_bps`, `taxa_minima_centavos`, `prazo_liberacao_dias`
(P1/P2, do João). Sem versão vigente a API responde 503 nas rotas de dinheiro (comportamento desejado). Cidade inativa
também impede criar pedido.

## `transfer.paid` (corrigido)

`transfer.paid` não é evento do Stripe. Eventos reais de transferência: `transfer.created`, `transfer.updated`,
`transfer.reversed`; liquidação em banco: `payout.paid`. Removido de `TIPOS_STRIPE`
(`backend/src/trato/pagamentos/provedor/stripe_formato.py`) e dos docs; `payout.paid` continua como liquidação.
Teste: `backend/tests/test_eventos_stripe_validos.py`. Comando do `stripe listen` fica:

```bash
stripe listen --events payment_intent.succeeded,payment_intent.payment_failed,charge.refunded,payout.paid --forward-to http://127.0.0.1:8000/v1/webhooks/stripe
```

`transfer.created`/`transfer.reversed` **não são tratados**; se o modelo de contas (P7) usar Connect com transferências,
decidir qual deles libera o repasse e se `transfer.reversed` estorna. Decisão do João.

## Achados

7. **BLOQUEIO: o pagamento não está ligado ao Postgres.** `criar_app_da_config` nunca chama `instalar_pagamento`, e não existem
   repositórios Postgres de cobrança, aditivo e termos (só `CobrancasEmMemoria`, `AditivosEmMemoria`, `TermosEmMemoria`). No app real:
   `POST /v1/contratos/{id}/cobranca` responde **503 "Pagamento ainda não configurado"** e os manipuladores de webhook do
   `payment_intent.*` não são registrados. Provado no fluxo real: login, pedido, orçamento, resumo de taxa (750 = 7,5%) e aceite deram OK;
   a cobrança deu 503. Falta: repositórios Postgres (tabela `pagamentos` etc.), `ConfigPagamento` lida da config vigente, e ligar tudo em
   `fabrica.criar_app_da_config`. Tarefa própria (dinheiro); o resto do roteiro (Stripe 4242, webhook, ledger, idempotência) depende disso.

1. **Falta rota de orçamento do profissional.** Não há `POST` para criar/enviar orçamento (só `GET` e `POST /orcamentos/resumo`).
   O fluxo pedido → orçamento → aceite não fecha pela API; só dá para testar semeando orçamento por SQL.
2. **Catálogo exige login** (`/v1/catalogo/categorias` e `/cidades` = 401). Se a tela de cadastro precisar listar categorias
   antes do login, a rota tem de ser pública. Confirmar a intenção.
3. **Erro de log do uvicorn** (`ValueError: not enough values to unpack (expected 5, got 0)` em `uvicorn/logging.py`)
   quando o log de acesso é escrito sem terminal (redirecionado para arquivo). Não afeta as respostas. Origem a investigar
   (provável conflito do `logging` configurado com o formatter de acesso do uvicorn).
6. **A suíte em memória quebra se houver `.env` real na raiz.** Com o `.env` do João copiado para a worktree, `verificar` deu
   46 falhas em `backend/tests/api` (422/401 onde se esperava 200/503: o app de teste lê `TRATO_PERSISTENCIA=postgres`,
   provedor Stripe e segredos do ambiente). Sem o `.env`, os mesmos testes passam. Os testes deveriam limpar essas variáveis
   (fixture `monkeypatch.delenv`) para rodar igual com ou sem `.env`. **Não corrigido** (toca muitos testes): fica como pendência.
   Por isso o `.env` foi removido da worktree antes do `verificar` final.
4. `docs/api-persistencia.md` ainda cita a migration "que falta" para `aguardando_confirmacao`; conferir se já foi coberta.
5. Migrations aplicadas não têm o mesmo número de versão dos arquivos; o `supabase db push` pode tentar reaplicá-las.
   Alinhar com `supabase migration repair` antes de usar a CLI.

## O que depende do João (PRECISO DO SEU OK)

```
PRECISO DO SEU OK
O que:    Rodar o fluxo de pagamento ponta a ponta no Supabase REAL: criar 2 usuários no Auth (teste_cliente@example.test,
          teste_profissional@example.test), 2 em `equipe` (admin + financeiro), uma versão de config VIGENTE com valores
          de teste, pedido/orçamento/contrato semeados, PaymentIntent no Stripe teste (4242...) e webhook assinado.
Por que:  Provar cobrança, webhook, ledger espelhado e idempotência em ambiente real.
Risco:    IRREVERSÍVEL em parte: versão de config vigente é imutável (só se corrige publicando outra); lançamentos
          do ledger e `eventos_webhook` são imutáveis. Usuários do Auth e linhas de pedido podem ser apagados.
          Uma taxa de teste vigente poderia valer para dados reais se não for substituída antes do piloto.
Como desfazer: apagar usuários/pedidos de teste (script a propor); config e ledger ficam como histórico "teste_"
          (ou usar um branch do Supabase / projeto descartável, que evita o risco: recomendado).
Posso continuar?
```

Alternativa sem risco: rodar o mesmo roteiro num **branch do Supabase** ou no Postgres local (`backend/tests/integracao`,
que já cobre o fluxo completo e a idempotência do webhook), e deixar o banco real para depois de fechar a taxa.
O João também precisa rodar `stripe listen` (comando acima) para o teste com webhook real.

## Decisão do João: regra de liberação (31/10/2026)

- O repasse é liberado **assim que o cliente confirma** o serviço: `prazo_liberacao_dias = 0`.
- Sem confirmação em **48 h**, o sistema confirma sozinho: `prazo_confirmacao_cliente_horas = 48`.
- O cliente tem **7 dias para reclamar**: `janela_chargeback_dias = 7`.

Para aplicar na config real: o mínimo de `prazo_liberacao_dias` em `supabase/seeds/parametros.sql` hoje é 1 (e `supabase/testes/testar_seeds.py`
exige que 0 seja rejeitado). Falta baixar o mínimo para 0 e ajustar esse teste junto, e só então rodar o seed 2. A config de teste já no banco
(`teste_`) **não** tem `prazo_liberacao_dias`. Pendente do João: taxa mínima em centavos (0 se não houver) e confirmar `taxa_bps = 750`.

## Decisão do João: quem paga a taxa (31/10/2026)

A taxa do Trato é **7,5% sobre o total do pedido e é SOMADA ao pedido** (o cliente paga serviço + taxa). **Não é subtraída do profissional**:
o profissional recebe o valor do orçamento inteiro; a taxa é a receita do Trato.

**Conflito com o código atual:** hoje a taxa é *deduzida* (`pagamentos/taxa.py`, `POST /v1/orcamentos/resumo`: valor 10000, taxa 750,
líquido 9250; a cobrança do cliente é o valor do orçamento). O texto de `contexto.md` ("total, taxa e líquido do profissional") também parte da dedução.
Pelo modelo novo: cobrança = valor + taxa (ex.: 10000 + 750 = 10750); líquido do profissional = 10000; Trato = 750.
Muda: valor da cobrança no Stripe, lançamentos do ledger (retenção/taxa/repasse), reembolso e disputa (quanto devolver da taxa), a
calculadora de orçamento e as telas do app. Não alterado nesta rodada. Detalhes que o João ainda precisa fechar: o custo do Stripe sai da taxa
do Trato (como hoje)? Em reembolso total a taxa é devolvida ao cliente? A taxa mínima também se soma?
