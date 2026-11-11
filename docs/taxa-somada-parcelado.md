# Taxa somada ao pedido e parcelado (decisão do João, 31/10/2026)

> **SUBSTITUÍDO em 10/11/2026 quanto a quem paga a taxa e ao reembolso.** A taxa agora é descontada do profissional: ver `docs/taxa-descontada-profissional.md`. O que segue valendo daqui: o parcelado (custo real do provedor, tabela configurável, vazia = desligado), agora com base no valor do serviço.

Fonte das decisões: `docs/teste-real-banco.md` (seções "Decisão do João" e "CORREÇÃO"; a correção vale sobre o resto).
Dinheiro só no backend, centavos inteiros, ledger imutável, idempotência.

## O que mudou

| Antes (taxa deduzida) | Agora (taxa somada) |
|---|---|
| Cliente pagava o valor do orçamento | Cliente paga **serviço + taxa** (+ custo do parcelado, se parcelar) |
| Profissional recebia orçamento − taxa | Profissional recebe o **orçamento inteiro** |
| Taxa saía da custódia ao concluir | Taxa sai da custódia **na confirmação do pagamento** (receita do Trato) |

Exemplo (7,5% = 750 bps, mínima R$ 3,00 = 300): orçamento 10000 -> taxa 750, cobrança **10750**, profissional **10000**, Trato **750**.
Orçamento 3000 -> 7,5% = 225 < mínimo -> taxa 300, cobrança 3300. A taxa mínima também é somada (assumido; ver perguntas).

## Como funciona no backend

- `pagamentos/taxa.py`: `calcular_taxa(servico)` (inalterada, agora sobre o SERVIÇO) e `montar_total(servico, config, custo_parcelamento)`.
- `ServicoPagamento.total_a_cobrar` / `cobrar`: o valor enviado ao Stripe é `serviço + taxa (+ custo do parcelado)`. A taxa vem da **taxa congelada no aceite**
  (termos ou contrato), nunca da configuração de hoje. Aditivo: a taxa cobrada é só o crescimento da taxa total (taxa(serviço+aditivos) − taxa(serviço)), para o mínimo não ser cobrado duas vezes.
- Webhook de pagamento (valor tem de bater com o cobrado): ledger recebe `cobranca` (cliente -> custódia, valor cobrado) e logo `taxa`
  (custódia -> taxa do Trato, valor cobrado − serviço). Fica retido **só o serviço**. Chaves: `cob/<id>` e `cob/<id>/taxa` (idempotentes).
- Conclusão, disputa e cancelamento operam sobre a custódia (= serviço). `repartir_custodia` não desconta mais taxa (taxa 0): `retencao` = serviço inteiro.
  `repasses.taxa_centavos` fica 0 e o líquido do repasse = valor do serviço.
- Disputa: `valor_congelado` = retido + a liberar = serviço (a taxa não entra na disputa).
- `contratos.liquido_profissional_centavos` = `valor_total_centavos` (sem mudança de schema).
- `GET /v1/pedidos/{id}/pagamento` traz serviço, taxa, total à vista e `opcoes_parcelamento`; `POST /v1/orcamentos/resumo` traz `total_cliente_centavos` e `liquido_centavos` = orçamento.

## Reembolso: a taxa não volta

`estornar_pedido` só devolve até `cobrado − taxa` (serviço). O estorno parcial sai da custódia e da parte do profissional, nunca da taxa.
Exemplo: cliente pagou 10750; reembolso total devolve **10000**; os 750 ficam com o Trato. Vale para disputa, cancelamento depois de pago e reembolso por fora (`charge.refunded`).
O pedido do Stripe de estorno é pelo valor do serviço.

**Regra pendente (arrependimento, art. 49 do CDC): NÃO decidida.** Existe a chave de configuração `cancelamento_devolve_taxa` (padrão `false`, parâmetro opcional
da versão de config) e o parâmetro `taxa_reembolsavel` em `estornar_pedido`. Ligada, o **cancelamento** devolve também a taxa (nunca o custo do parcelado).
Ela NÃO checa os 7 dias nem "serviço ainda não começou" (o cancelamento só existe antes de iniciar); isso depende do parecer do Emanoel.

## Parcelado: custo real do provedor, repassado

- O João **não** define a taxa do parcelado e o Trato **não** absorve. **Não existe valor padrão no código.**
- `pagamentos/parcelamento.py`: `ConfigParcelamento` (`parcelas -> bps`). **Tabela vazia = parcelado desligado**: `POST .../cobranca` com `parcelas > 1` responde `422`,
  e `opcoes_parcelamento` vem vazia (o app não mostra parcelado).
- A tabela vem da config vigente pelos parâmetros opcionais `custo_parcelamento_<N>x_bps` (N de 2 a 12). Esses parâmetros ainda **não existem** em `supabase/seeds/parametros.sql`
  (não criei migration nem seed: escrita no banco precisa do OK do João). Sem eles, o parcelado fica desligado.
- Base do cálculo (a confirmar): bps sobre `serviço + taxa`, arredondado meio para cima, uma vez. Total parcelado = serviço + taxa + custo. O custo repassado vai para a conta do Trato
  no ledger (junto da taxa, `cobrado − serviço`) e **não é reembolsável**; o custo real pago ao provedor é uma despesa à parte (reconciliação).
- `stripe_teste.py` continua recusando `parcelas != 1`: ligar o parcelamento no Stripe (plano de parcelas no PaymentIntent do cartão) é trabalho à parte e só faz sentido quando os números do provedor chegarem.
- App: a tela de pagamento mostra, para o cartão, o total por número de parcelas **quando o backend mandar**. A escolha da quantidade de parcelas **não está ligada** (hoje não há opção a escolher).

## Perguntas em aberto para o João (e o Emanoel)

1. **Custo do parcelado:** quais são os valores do provedor por nº de parcelas (2x a 12x)? Vêm de qual provedor (Stripe, Mercado Pago, Pagar.me)? O bps incide sobre `serviço + taxa` ou sobre o total já com o custo (gross-up, o provedor cobra sobre o que o cliente paga)?
2. **Taxa mínima somada:** confirma que a mínima (R$ 3,00) também é somada ao pedido (assumido que sim)?
3. **Pix e cartão à vista:** o custo do Stripe sai da taxa — e se a taxa não cobrir (pedido pequeno, cartão)? Há piso de serviço (sugerido R$ 30,00)?
4. **Arrependimento (7 dias, CDC art. 49):** devolver a taxa no cancelamento antes de o serviço começar? Dentro de 7 dias? Hoje: não devolve, regra desligada. Para o Emanoel.
5. **Disputa com reembolso parcial:** a taxa fica integral (como está) ou proporcional?
6. **Aditivo:** a taxa do aditivo é só o crescimento da taxa total (como feito) ou o percentual sobre o aditivo sozinho (N3)?
7. **Transparência do parcelado (CDC):** repassar o custo ao consumidor exige informar valor total e custo antes da contratação — a tela atual atende? Para o Emanoel.
8. **Repasse:** o custo real do provedor no cartão à vista é conciliado em `custo_stripe` ou só no relatório de margem? Hoje o ledger não lança `custo_stripe`.
9. **Pedido já pago antes desta mudança:** não há dados reais; nenhuma migração de dados necessária (o banco real não tem pagamentos).

## Verificação

`backend`: `pytest` (e2e `tests/api/test_fluxo_pagamento_e2e.py`, ledger, taxa/parcelamento) e `ruff` passam. Os testes de `tests/integracao/` (Postgres local via `pgserver`)
foram **atualizados por leitura mas não executados**: `pgserver` não está instalado nesta máquina.
