# Correção dos achados de dinheiro da revisão de segurança

Branch `claude/fix-dinheiro-bae05e`. Achados de `docs/revisao-seguranca.md`: C1, A3, A4, A5, A6, A7, M1 a M5.
Nada foi escrito no Supabase real. Os testes de banco rodaram só em Postgres local descartável (pgserver).

Em português simples: o dinheiro deixou de morar na memória do servidor. Agora o ledger, a disputa, a garantia,
a avaliação, os avisos do provedor e as ordens de repasse ficam no banco, e cada operação de dinheiro grava tudo
numa transação só (ou nada).

## O que mudou, achado por achado

| Achado | Correção | Onde | Teste |
|---|---|---|---|
| **C1** dinheiro em memória | Repositórios Postgres: `LedgerPostgres` (lançamentos, partidas, contas), `DisputasPostgres`, `GarantiasPostgres` (garantia e retrabalho), `AvaliacoesPostgres`, `EventosWebhookPostgres`, `RepassesPostgres`. A fábrica os liga e **recusa subir** se algum for em memória (`exigir_dinheiro_no_banco`). `Contexto.transacao()` junta pedido + ledger + disputa + evento + auditoria numa transação (`Banco.transacao` agora é reentrante). | `persistencia/ledger.py`, `persistencia/dinheiro.py`, `api/fabrica.py`, `api/contexto.py` | `test_c1_*`, `tests/integracao/test_dinheiro_postgres.py` |
| **A4** ledger Python × banco | O enum fica só com tipos do CHECK do banco (`cobranca, retencao, taxa, repasse, estorno`); liberação e pagamento ao profissional são `repasse` com pares de contas diferentes, gorjeta é `cobranca` para `liberado`. Estorno **inverte o lançamento inteiro**, uma vez só. O estorno parcial do pedido estorna os originais por inteiro e lança de novo a parte mantida. Lançamento sempre ligado a contrato; `evento_webhook_id` no lançamento. Sem saldo próprio. | `financeiro/ledger.py` | `test_a4_*`, `test_ledger.py`, `test_estorno_parcial_do_pedido_passa_pelos_gatilhos_do_banco` |
| **A5** trava de idempotência | `i.chave.startswith(prefixo)` (era `i.id`). Além disso, a decisão é uma transação única no Postgres. | `api/admin/rotas_disputas.py` | `test_a5_*`, `test_disputa_persiste_e_a_decisao_usa_a_taxa_congelada` (refazer = 409, ledger igual) |
| **A6** concorrência | Pedido: `select … for update` + compare-and-set (`update … where status = <lido>`); outra requisição que mudou o estado vira `ConflitoDeEstado` (409). Ledger: o contrato é travado (`for update`) enquanto o lote é conferido e gravado, em ordem fixa. Evento de webhook: `pg_advisory_xact_lock` por evento. Chave do dinheiro vem de dado estável (`din/<pedido>/<operação>`), não de `len()`. | `persistencia/pedidos.py`, `persistencia/ledger.py`, `persistencia/dinheiro.py`, `pagamentos/orquestrador.py` | `test_a6_*`, `test_duas_transicoes_simultaneas_do_pedido_uma_so_vence`, `test_dois_estornos_simultaneos_…`, `test_o_mesmo_lancamento_chegando_junto_…` (threads + Barrier em Postgres) |
| **A7** ordem do estorno | Intenção primeiro: a transação grava ledger + ordem de estorno (+ repasse); **só depois do commit** (`Contexto.depois_do_commit`) o provedor é chamado, com a chave da ordem. Falha do provedor deixa a ordem `pendente`; `ServicoPagamento.reenviar_estornos()` reconcilia. | `pagamentos/orquestrador.py`, `pagamentos/modelos.py` (`OrdemEstorno`) | `test_a7_*`, `tests/api/test_fix_dinheiro.py` |
| **A3** taxa da disputa | A taxa vem do contrato (`taxa_bps_aplicada` + mínimo em `regras_aplicadas`) ou dos termos congelados, nunca da configuração de hoje. Sem taxa congelada: 503, não recalcula. | `pagamentos/taxa.py` (`taxa_congelada`), `persistencia/contratos.py`, `api/admin/rotas_disputas.py` | `test_a3_*`, e o teste de disputa em Postgres |
| **M1** valor pago | Evento sem valor **inteiro** ou diferente da cobrança não confirma; compara `amount_received` (ou `amount`). | `pagamentos/provedor/stripe_formato.py`, `orquestrador.py` | `test_m1_*` |
| **M2** 422 em loop | Divergência é guardada para revisão (`marcar_revisao`, coluna `eventos_webhook.erro`) e responde 200. | `orquestrador.py`, `persistencia/dinheiro.py` | `test_webhook_de_pagamento_com_valor_diferente_nao_confirma` |
| **M3** `charge.refunded` | Concilia: o que passa do que o Trato mandou devolver entra no ledger como estorno e gera alerta; se não der para lançar (já liberado), só alerta (200). | `orquestrador.py` | `test_m3_*` |
| **M4** taxa única | `taxa_da_versao` + `calcular_taxa` (percentual **ou mínimo**, nunca acima do valor) usados no contrato, na calculadora (`TaxaPostgres`) e na liquidação. O mínimo é o parâmetro `taxa_minima_centavos` da versão (ausente = sem mínimo). | `persistencia/config.py`, `contratos.py`, `app_extras.py` | `test_taxa_do_postgres_respeita_o_minimo_como_a_calculadora` |
| **M5** liquidação | `payout.paid`/`transfer.paid` só liberam o **repasse** a que o aviso se refere (id da transferência, ou `repasse_id` nos metadados na 1ª vez), com o valor líquido exato. Sem repasse ou valor errado: revisão + 200. Repasse é liberado uma vez só. | `orquestrador.py`, `financeiro/repasses.py`, `persistencia/dinheiro.py` | `test_liquidacao_*`, `test_repasse_e_liberado_uma_vez_so` |

## Como rodar

```bash
python harness/verificar.py                     # backend com o .venv do projeto
```

Os testes de integração precisam do `pgserver`, que o `.venv` do projeto não tem (eles ficam pulados). Para rodá-los, num venv
**fora** do projeto:

```bash
python -m venv /tmp/venvpg && /tmp/venvpg/bin/pip install "fastapi" "pydantic-settings" "psycopg[binary]" psycopg-pool "pyjwt[crypto]" pytest httpx pgserver
cd backend && PYTHONPATH=src /tmp/venvpg/bin/python -m pytest tests/integracao -q
```

## Limites desta entrega (nada disto foi feito, de propósito)

1. **`ServicoPagamento` ainda não é ligado na fábrica Postgres.** Cobranças, aditivos e termos (`pagamentos/memoria.py`) e as
   ordens de estorno continuam em memória no serviço; falta escolher o provedor por configuração (Stripe sandbox) e ter
   tabela para eles. No modo Postgres hoje valem os manipuladores simples de `api/webhook_pagamento.py` (pagamento confirmado
   e recusado), que já gravam no ledger/pedido na mesma transação. A migration abaixo prepara as ordens de estorno.
2. A decisão no banco exige **mediador ativo** em `disputas.decidida_por` (gatilho `disputas_validar`). Quem decide pela API
   admin com outro papel leva 409 do banco. É a regra do banco, não mudei.
3. Detalhes que o banco não guarda e a leitura aproxima: `aprovado_em` (vale a hora da decisão); `sem_resposta` (derivado de não
   haver evidência `resposta`); o estado `aguardando_aprovacao` é `em_analise` com a decisão já proposta.
4. `repasses` é criada ao concluir (confirmação do cliente, acordo ou decisão da disputa). Quem pede a transferência ao parceiro
   (e põe `repasse_id` nos metadados) ainda não existe: depende do modelo de contas (P7).
5. Contas do ledger (`contas_ledger`) são criadas **sob demanda** pelo backend na primeira vez que aparecem (a F3.5 diz que o
   seed delas fica para depois, com OK). Se preferir seed fixo, é só uma migration de seed.
6. O teste `test_a7_*` usa `t-equipe` na rota `/v1/pedidos/{id}/disputa/decisao`. A sessão `fix-acesso` (A2) vai restringir essa
   rota: quem integrar os dois ramos precisa dar a permissão ao `t-equipe` no teste (ou usar a rota do admin).

---

PRECISO DO SEU OK

**O que:** aplicar no Supabase a migration `supabase/migrations/20261030120000_ordens_estorno.sql`. Cria a tabela `ordens_estorno`
(fila de estornos pedidos ao provedor) e a coluna `pagamentos.estornado_centavos`.

**Por quê:** é o que permite, no Postgres, gravar a intenção de estorno **antes** de chamar o provedor (A7) e reenviar o que ficou
pendente. Sem ela, o fluxo de estorno só funciona com a fila em memória (testes).

**Risco:** baixo. Só cria tabela nova e uma coluna com valor padrão 0; não mexe em dado existente. RLS ligado, sem acesso para
`anon`/`authenticated`; `service_role` sem DELETE/TRUNCATE. Testada no Postgres local (aplica, protege e desfaz).

**Como desfazer:** `supabase/rollback/ordens_estorno_rollback.sql` (apaga a tabela e a coluna; só tem dado depois que o
`ServicoPagamento` for ligado ao banco).

**Posso continuar?** Sem o seu OK a migration fica só como arquivo, não aplicada.

(Nenhuma outra correção exigiu mudança de esquema: o ledger, a disputa, a garantia, a avaliação, os eventos e os repasses usam
as tabelas da F3.5/F3.6 já aplicadas, sem alterar nenhuma migration existente.)
