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

## Decisão do João: custo do Stripe e parcelado (31/10/2026)

- O Trato **absorve** o custo do Stripe no **Pix** e no **cartão à vista** (sai da taxa de 7,5%).
- No **parcelado**, na hora de pagar, o cliente paga **4% a mais** por ser a prazo.

Exemplo (serviço R$ 100,00, taxa R$ 7,50, total R$ 107,50): à vista = R$ 107,50; parcelado = R$ 107,50 + 4% = R$ 111,80 (se os 4% incidirem sobre o total).
Em aberto: os 4% incidem sobre o total (serviço + taxa) ou só sobre o serviço? É igual para qualquer número de parcelas? Os 4% voltam ao cliente em
reembolso? Confira se 4% cobre o custo do Stripe no parcelado (a página pública não traz o valor do parcelamento: conferir antes de lançar).
No código, o campo `adicional_parcelamento_bps` (`pagamentos/custo.py`) já existe, hoje vazio; 4% = 400 bps.

## Decisão do João: a taxa não é reembolsada (31/10/2026)

Em reembolso, a **taxa do Trato (7,5%) não volta** para o cliente; é o padrão de mercado. Só o valor do serviço é devolvido.
Exemplo: cliente pagou R$ 107,50 (serviço R$ 100,00 + taxa R$ 7,50); reembolso total devolve R$ 100,00.
Em aberto (não decidido): o acréscimo de 4% do parcelado também fica com o Trato? Reembolso parcial em disputa: a taxa fica integral ou proporcional?
Para o Emanoel: se o serviço não foi prestado (cancelamento antes de começar, direito de arrependimento do CDC), reter a taxa é permitido?
Hoje o código devolve só o valor do serviço em reembolso (a taxa nunca volta) e já faz isso na disputa; conferir ao mudar para taxa somada.

Posição do João: reter a taxa também vale quando o serviço nem começou e o cliente cancela. **Risco jurídico a confirmar com o Emanoel antes de lançar:** o art. 49
do CDC (contratação fora do estabelecimento, como no app) dá 7 dias de arrependimento e manda devolver "os valores eventualmente pagos, a qualquer título".
Isso pode incluir a taxa do Trato no arrependimento. Não é parecer jurídico; é um ponto a validar. Se confirmado, o desenho passa a ser: arrependimento
dentro de 7 dias e antes do serviço começar devolve tudo; depois disso a taxa não volta.

## Decisão do João: taxa mínima (31/10/2026)

`taxa_minima_centavos = 300` (R$ 3,00), conforme o exemplo aceito pelo João ("pode ser"); alterável na tabela de configuração.
Com serviço de R$ 30,00 (mínimo sugerido): taxa R$ 3,00; cartão à vista custa ~R$ 1,71 sobre R$ 33,00; sobra ~R$ 1,29. Pix sobra mais.
Falta a decisão se a taxa mínima também se soma ao pedido (assume-se que sim, como a taxa de 7,5%).
Resumo da config de dinheiro decidida: `taxa_bps = 750`, `taxa_minima_centavos = 300`, `prazo_liberacao_dias = 0`,
`prazo_confirmacao_cliente_horas = 48`, `janela_chargeback_dias = 7`, adicional do parcelado 400 bps. Nada disso foi gravado no banco real.

## Decisão do João: base dos 4% e reembolso do acréscimo (31/10/2026)

- Os 4% do parcelado incidem sobre o **valor total** (serviço + taxa do Trato). Ex.: R$ 107,50 × 4% = R$ 4,30; cliente paga R$ 111,80 parcelado.
- O acréscimo **não é reembolsado** (o Stripe também não devolve o custo dele). Em reembolso total no parcelado, o cliente recebe só o valor do serviço
  (R$ 100,00 neste exemplo); taxa de R$ 7,50 e acréscimo de R$ 4,30 ficam com o Trato.
Ainda não decidido: o acréscimo vale para qualquer número de parcelas (2x a 12x)? Sujeito à validação jurídica do Emanoel (art. 49 do CDC, arrependimento em 7 dias).

## CORREÇÃO (31/10/2026): o parcelado repassa o custo REAL do provedor, não 4% fixos

O João esclareceu: **ele não define a taxa de juros do parcelado; quem define é o provedor (terceiro), e o Trato também não absorve esse custo.**
Isto SUBSTITUI o "4% a mais" e a "base dos 4%" registrados acima (eram exemplos, não decisão).
- No cartão parcelado, o cliente paga o **custo de parcelamento cobrado pelo provedor** para aquele número de parcelas, repassado integralmente.
- No Pix e no cartão à vista continua valendo: o Trato absorve o custo do provedor (sai da taxa de 7,5%).
- Taxa de 7,5% (mín. R$ 3,00) não muda e continua não reembolsável; o custo repassado do parcelamento também não volta (o provedor não devolve).

Consequências para o código: o adicional por parcela não é constante no sistema; vem de uma tabela de **custo do provedor por número de parcelas** (hoje
`adicional_parcelamento_bps` em `pagamentos/custo.py`, vazio) ou do cálculo do próprio provedor, e o app mostra ao cliente, antes de pagar, o total por parcelas.
Em aberto: a página pública do Stripe não traz o custo do parcelado (`docs/provedores-pagamento.md`), então ele precisa vir da proposta/contrato do provedor
antes de lançar; o Mercado Pago e o Pagar.me têm tabelas próprias. Pergunta para o Emanoel: repassar o custo do parcelamento ao consumidor exige informar o valor
total e o custo antes da contratação (CDC, transparência)?
