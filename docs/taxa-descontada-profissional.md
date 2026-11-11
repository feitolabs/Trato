# Taxa descontada do profissional (decisão do João, 10/11/2026)

Substitui a decisão de 31/10/2026 (`docs/taxa-somada-parcelado.md`) no que diz respeito a quem paga a taxa e ao reembolso.
Dinheiro só no backend, centavos inteiros, ledger imutável, idempotência.

## A regra

| | Antes (taxa somada) | Agora (taxa descontada) |
|---|---|---|
| Cliente paga | serviço + taxa | **o valor do orçamento** |
| Profissional recebe | o orçamento inteiro | **orçamento − taxa** |
| Quando a taxa sai | na confirmação do pagamento | **na conclusão, antes de creditar a carteira** |
| Reembolso total | devolve só o serviço; a taxa fica | **devolve 100%; o Trato não fica com taxa** |

Exemplo (7,5% = 750 bps, mínima R$ 3,00 = 300): orçamento 10000 -> cobrança **10000**, taxa 750, profissional **9250**, Trato **750**.
Orçamento 3000 -> 7,5% = 225 < mínimo -> taxa 300, profissional 2700.

A taxa é calculada sobre o orçamento e congelada no aceite. O profissional vê a taxa e o líquido na calculadora, antes de enviar. O cliente não vê taxa nenhuma: paga o orçamento.

## Como funciona no backend

- `pagamentos/taxa.py`: `montar_total` devolve `cobrado = serviço + parcelamento` e `líquido = serviço − taxa`.
- Webhook de pagamento: o ledger recebe só `cobranca` (cliente -> custódia). O valor fica retido inteiro. Se parcelado, o custo sai da custódia na hora (`separar_custo_parcelamento`, chave `cob/<id>/parcelamento`).
- Conclusão (`_registrar_intencao`) e decisão de disputa (`_planejar_dinheiro`): `repartir_custodia` desconta `calcular_taxa(restante, taxa congelada)`. O repasse sai com `taxa_centavos` preenchida e `valor_liquido_centavos` = o que entra na carteira.
- Contrato sem taxa congelada: a decisão de disputa que paga o profissional responde `503` (nunca recalcula pela configuração de hoje).
- `contratos.liquido_profissional_centavos` = `valor_total − taxa`. Sem mudança de schema.
- `GET /v1/pedidos/{id}/pagamento` não traz mais `taxa_centavos`. `POST /v1/orcamentos/resumo` traz `liquido_centavos` = orçamento − taxa e `total_cliente_centavos` = orçamento.

## Reembolso

`estornar_pedido` devolve até `cobrado − custo do parcelado`, proporcionalmente entre custódia, parte do profissional e taxa já descontada.

- **Antes de concluir** (cancelamento, disputa): nenhuma taxa saiu. Devolve o valor retido inteiro.
- **Depois de concluir** (retrabalho que vira disputa): `valor_congelado` = retido + a liberar + taxa descontada, para o reembolso total chegar a 100%.
- **Custo do parcelado não volta** (o provedor não devolve).
- Saiu `cancelamento_devolve_taxa` e `taxa_reembolsavel`: a questão do art. 49 do CDC sobre devolver a taxa deixa de existir, porque o cliente não paga taxa.

## Assumido (confirmar com o João)

- **Disputa com reembolso parcial:** a taxa incide sobre o que ficou para o profissional. Ex.: orçamento 100000, cliente recebe 25000; o profissional fica com 75000 menos 7,5% (5625) = 69375.
- **Aditivo:** o cliente paga o valor do aditivo; a taxa é calculada na conclusão sobre serviço + aditivos, o que evita contar o mínimo duas vezes.

## Pontos abertos

- O custo do Stripe no Pix e no cartão à vista continua saindo da taxa. Em **reembolso total o Trato não recebe taxa e ainda pode arcar com esse custo**: o Stripe não devolve a tarifa da cobrança estornada.
- Texto dos termos (seção 4, `rotas_legal.py`) atualizado para dizer que a taxa sai do profissional: **validar com o Emanoel**.
