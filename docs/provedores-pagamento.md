# Provedores de pagamento para o marketplace (comparação)

> **Rascunho de pesquisa. Não é parecer jurídico, regulatório nem financeiro.**
> Data da consulta: **29/10/2026**. Cada dado traz o link e a data. Taxa de página pública vale só como
> referência: o contrato real vem da **proposta escrita** (P16). Onde não é público: **a confirmar com proposta**.
> Nenhum valor aqui foi inventado. Tarifas de terceiros (sites não oficiais) estão marcadas como tal.
> Nada foi contratado, nenhum contato foi feito. Decisão A/B de custódia: D15 (caminho A).

Relacionados: `docs/pedido-de-proposta-provedores.md`, `docs/simulacao-margem.md`, `docs/v2-impacto.md`, `harness/PENDENCIAS.md` (P2, P3, P7, P16).

## 1. Resumo em 10 linhas

- Nenhum provedor foi confirmado como "marketplace com retenção até a conclusão" para o Trato. Isso é perguntado na proposta.
- **Stripe:** documentação melhor e tarifa pública de cartão e Pix. Pix no Brasil aparece como "somente convite" na página de preços (a confirmar).
- **Asaas:** tabela pública completa (Pix, cartão à vista e parcelado) e split por `walletId` documentado. Chargeback e KYC da subconta: a confirmar.
- **Pagar.me:** split com recebedores e regra de quem responde por chargeback documentada. Preço público só de Pix e cartão à vista.
- **Mercado Pago:** split 1:1 documentado (comissão do marketplace). Tabela oficial não abriu na consulta. Só há referência de terceiros.
- **Iugu:** site fala em split e subcontas; sem tarifa pública encontrada.
- A simulação de margem (`docs/simulacao-margem.md`) usa 1,19% no Pix e 3,99% + R$ 0,39 no cartão. Isso bate com a página da Stripe, mas o Pix da Stripe é "por convite". **Conferir.**

## 2. Quadro comparativo

Legenda: ✔ confirmado em fonte oficial · ◐ indício ou parcial · ✖ não suporta · **AC** = a confirmar com proposta.

| Critério | Stripe Connect | Asaas | Pagar.me (Stone) | Mercado Pago | Iugu |
|---|---|---|---|---|---|
| Pix | ✔ pagamento único no BR; liquidação até 2 dias úteis [S2] | ✔ [A1] | ✔ [P1] | ◐ (só terceiros) [M3] | ◐ [I1] |
| Cartão à vista | ✔ [S1] | ✔ [A1] | ✔ [P1] | ◐ [M3] | ◐ [I1] |
| Cartão parcelado | **AC** (página não traz) [S1] | ✔ 2–6x, 7–12x, 13–21x [A1] | **AC** [P1] | ◐ [M3] | **AC** |
| Split | ✔ Connect [S3] | ✔ por `walletId`, fixo ou % [A2] | ✔ por `recipient_id`, fixo ou % [P2] | ✔ split 1:1 com `application_fee` [M1] | ◐ split e multisplit, segundo o site [I1] |
| Retenção até a conclusão | **AC** (não confirmado para Pix BR) | **AC** | **AC** | **AC** | **AC** |
| Marketplace / subadquirência | Contas conectadas; contrato de conta conectada em PT [S5] | Subcontas [A2] | Recebedores (PSP) [P2] | Vendedor liga conta via OAuth [M1] | Subcontas [I1] |
| Taxa publicada | Ver 3.1 | Ver 3.2 | Ver 3.3 | Ver 3.4 | Não encontrada |
| Prazo de recebimento | Pix até T+2 [S2]; cartão **AC** | Antecipação cartão até 2 dias úteis [A1]; prazo normal **AC** | "Próximo dia útil" (com asterisco sem explicação) [P1] | 3 opções: na hora, 14 ou 30 dias (terceiros) [M3] | **AC** |
| Chargeback | Taxa R$ 55,00 por contestação recebida [S1]; no Pix, decisão do parceiro é final [S2] | Split estornado junto da cobrança [A3]; regra de chargeback **AC** | `liable` define quem responde [P2] | **AC** (página de split não trata) [M1] | **AC** |
| KYC do prestador | Verificação via Connect [S4]; documentos exigidos para BR **AC** | **AC** | **AC** | Conta própria do vendedor [M1] | **AC** |
| Saque / repasse | Repasse (payout) à conta bancária; tarifa em 3.1 [S4] | **AC** | **AC** | Conta Mercado Pago do vendedor [M1] | **AC** |
| Reembolso | Pix: até 90 dias, parcial ou total [S2] | Estorno desfaz os repasses do split [A3] | **AC** | Proporcional vendedor/marketplace; sem saldo do vendedor, o marketplace não reembolsa tudo [M1] | **AC** |
| Python / Flutter | API REST. SDK Python e pacote Flutter: **AC** (não verificado nesta rodada) | API REST; SDK **AC** | API REST; SDK **AC** | API REST; SDK **AC** | API REST (site cita 140+ endpoints) [I1] |

Observação: toda API REST funciona no backend Python com um cliente HTTP. O Flutter só mostra a tela de pagamento do parceiro; **nenhuma regra de dinheiro roda no app** (regra do projeto).

## 3. Detalhes por provedor

### 3.1 Stripe (Connect)

- **Cartão nacional:** 3,99% + R$ 0,39 por transação. **Pix:** 1,19% por Pix pago, "disponível somente por convite". **Boleto:** R$ 3,45. Contestação recebida: R$ 55,00. Smart Disputes: 30% do valor contestado, só em contestação ganha. Parcelamento, antecipação e prazo em dias: **não constam** na página. [S1] — consultado em 29/10/2026.
- **Connect (tarifas):** se a Stripe cobra os usuários, sem tarifa extra para a plataforma. Se a plataforma define o preço: R$ 6 por conta ativa no mês; repasse de 0,25% + R$ 0,67; roteamento de fundos 0,25% (linha de leitura difícil, **conferir**). Tipos Express, Custom e Standard não aparecem na página. [S3] — 29/10/2026.
- **Pix:** contas no Brasil aceitam Pix único, liquidação em BRL, **Connect aparece como suportado**. Liquidação até 2 dias úteis. Reembolso em até 90 dias. Contestação só em casos limitados (fraude, invasão de conta); não dá para contestar a decisão do parceiro. Valor máximo padrão por pagamento: equivalente a US$ 3.000. Sem captura manual nem parcial. Para cobrança direta ou com `on_behalf_of`, a conta conectada precisa ter Pix ativado. [S2] — 29/10/2026.
- **Dúvida aberta:** a página de preços diz "somente por convite" e a de Pix diz que contas BR aceitam. Também não achei como o Pix funciona com `transfer_data` (split). **Perguntar na proposta.**
- **Risco para o Trato:** em cobrança "destination", a Stripe debita disputas e taxas da conta da plataforma (resultado de busca em docs.stripe.com, 29/10/2026) [S6]. Ou seja, o Trato pode ficar com o chargeback. Ver pergunta de saldo negativo.
- **Para a V2:** a Stripe não promete retenção até a conclusão para Pix. Sem confirmação por escrito, não usar essa palavra de retenção em texto nenhum.

### 3.2 Asaas

Tarifa padrão por transação recebida (consulta 29/10/2026) [A1]:

| Meio | Padrão | Promocional (3 meses) |
|---|---|---|
| Pix | R$ 1,99 | R$ 0,99 |
| Cartão à vista | R$ 0,49 + 2,99% | R$ 0,49 + 1,99% |
| 2 a 6 parcelas | R$ 0,49 + 3,49% | R$ 0,49 + 2,49% |
| 7 a 12 parcelas | R$ 0,49 + 3,99% | R$ 0,49 + 2,99% |
| 13 a 21 parcelas | R$ 0,49 + 4,29% | R$ 0,49 + 3,29% |

- Percentuais do parcelado incidem sobre o valor total da venda. A página manda consultar o contrato da conta.
- Antecipação de cartão: 1,25% ao mês na seção principal; a FAQ da mesma página indica 1,25% (à vista) e 1,70% (a prazo). **Conflito na fonte: conferir.**
- Taxa de split, subconta e chargeback: **não constam**. **AC.**
- **Split:** a cobrança fica na conta que a criou; parte vai às carteiras (`walletId`) por valor fixo ou %. Incide sobre o valor líquido (`netValue`). Estornar a cobrança estorna os repasses. Excesso de split bloqueia e dá 2 dias úteis para corrigir. [A2][A3] — 29/10/2026.
- A documentação cita um produto de split para "conta de custódia" do próprio Asaas. **Não usar sem advogado** (D13, D15).

### 3.3 Pagar.me (Stone)

- Preço público: **Pix 0,99%**; **crédito à vista 4,19%**; recebimento "próximo dia útil" com asterisco não explicado. Parcelado, boleto, antecipação, split: **sem valor** na página. [P1] — 29/10/2026.
- **Split:** disponível só para clientes PSP. Várias regras por recebedor, fixo ou %. Obrigatório: ao menos um recebedor responde pelo **chargeback**, um pelas **taxas** e um pelo **restante dos recebíveis**. [P2] — 29/10/2026.
- Liquidação, KYC do recebedor e prazo: **AC**.

### 3.4 Mercado Pago

- **Tabela oficial:** a página de custos retornou erro (403) na consulta de 29/10/2026. **Não usar números.** Referência de terceiros (não oficial): Pix gratuito, crédito à vista a partir de ~2,82%, 12x ~11,38%, prazos "na hora", 14 ou 30 dias [M3]. Valores mudam por perfil. **AC.**
- **Split 1:1:** cada vendedor liga a conta por OAuth. A comissão do Mercado Pago sai do vendedor primeiro; depois incide a comissão do marketplace (`application_fee` no checkout transparente, `marketplace_fee` no Checkout Pro). Reembolso é dividido proporcionalmente; se o vendedor não tem saldo, o marketplace reembolsa só a sua parte. Pagamento só com saldo entre contas Mercado Pago (sem transferência externa). Chargeback e Pix: **a página não trata.** [M1] — 29/10/2026.
- A V2 cita a documentação de split do Mercado Pago [M2]. O prestador precisaria de conta própria no Mercado Pago (atrito de cadastro).

### 3.5 Iugu

- O site fala em split por % ou valor fixo, multisplit e subcontas, API REST. Tarifa pública **não encontrada**. A página `/precos` não existe (404). [I1] — 29/10/2026.
- Cartão exige verificação prévia da conta master (segundo o site). Tudo o mais: **AC**.

### 3.6 Outros (não pesquisados a fundo)

- **Adyen for Platforms** (documentação de split de transações em docs.adyen.com [O1]): tende a exigir volume maior. **AC.**
- **Efí, Woovi, Celcoin e similares:** relevantes para Pix. **Não pesquisados nesta rodada.** Entram se os 2 provedores principais não responderem.

## 4. Leitura para decisão (sem decidir)

1. **Candidatos para pedir proposta:** Stripe Connect e um provedor brasileiro com split documentado (Asaas ou Pagar.me). O Mercado Pago entra se o atrito de o prestador abrir conta for aceitável.
2. **Ponto que decide tudo:** quem fica com saldo negativo e chargeback quando o split já saiu. Em quase todos, a página pública não responde. Ver `docs/pedido-de-proposta-provedores.md`.
3. **Margem:** ticket baixo no cartão pode dar margem negativa (ver `docs/simulacao-margem.md`). Trocar as estimativas pelas tarifas da proposta.
4. **Textos:** enquanto não houver contrato, o app diz "pagamento processado por parceiro" e nunca "pago" antes do evento do provedor (D13, D15).

## 5. Fontes (todas consultadas em 29/10/2026)

| Id | Fonte | Link |
|---|---|---|
| S1 | Stripe — preços Brasil | https://stripe.com/br/pricing |
| S2 | Stripe — Pix (docs) | https://docs.stripe.com/payments/pix |
| S3 | Stripe — preços do Connect | https://stripe.com/br/connect/pricing |
| S4 | Stripe — repasses entre países (limites de fluxo) | https://docs.stripe.com/connect/cross-border-payouts |
| S5 | Stripe — contrato de conta conectada (PT) | https://stripe.com/de-br/connect-account/legal |
| S6 | Stripe — destination charges | https://stripe.com/en-bg/docs/connect/destination-charges |
| A1 | Asaas — preços e taxas | https://www.asaas.com/precos-e-taxas |
| A2 | Asaas — split de pagamentos | https://docs.asaas.com/docs/split-de-pagamentos |
| A3 | Asaas — FAQ do split | https://docs.asaas.com/docs/faq-do-split |
| P1 | Pagar.me — preços | https://pagar.me/precos |
| P2 | Pagar.me — split | https://docs.pagar.me/reference/split-1 |
| M1 | Mercado Pago — split 1:1 marketplace | https://www.mercadopago.com.br/developers/pt/docs/split-payments/split-1-1/integration-configuration/integrate-marketplace |
| M2 | Mercado Pago — citado pela V2 (divisão de pagamento) | ver Auditoria V2, fonte [2] |
| M3 | Calculadora de terceiros (não oficial) | https://www.calculadoradetaxas.com.br/mercado-pago/taxas |
| I1 | Iugu — site institucional | https://www.iugu.com/iugu-saas |
| O1 | Adyen — split de transações | https://docs.adyen.com/pt/marketplaces/split-transactions |

Limites desta pesquisa: páginas lidas por resumo automático; valores devem ser conferidos na fonte antes de entrar em contrato ou simulação.
