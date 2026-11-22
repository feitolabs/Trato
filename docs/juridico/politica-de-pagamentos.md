# Política de Pagamentos — Trato

> **Versão 1.1 — rascunho para revisão do advogado — 22/11/2026**
> *(Versão anterior: rascunho inicial.)*
> **RASCUNHO PARA REVISÃO JURÍDICA. Não é texto final.** Quem escreveu não é advogado.
> Não publicar antes de revisão de advogado de meios de pagamento e de confirmação **por escrito** do parceiro.
> Este texto reflete as decisões do João até 22/11/2026 (D15 caminho A, app 100% gratuito, Tratinhos e SAC 08:00–20:00). Se o parceiro ou o advogado não confirmarem um item, o item **sai**.
> Relacionados: `termos-de-uso.md`, `politica-de-cancelamento-e-disputa.md`, `docs/provedores-pagamento.md`, `docs/v2-impacto.md`, `docs/decisoes-moedas-e-exclusividade.md`.

## 1. Em uma frase

O pagamento é **processado pelo parceiro de pagamento Stripe Brasil Soluções de Pagamento Ltda.** O Trato **não é banco, não guarda saldo próprio e não faz saque**. O Trato registra e mostra o que o parceiro confirma.

## 2. Quem faz o quê

| Quem | Papel |
|---|---|
| Cliente | Escolhe o método (Pix ou cartão) e paga o valor do orçamento aceito |
| Parceiro de pagamento (Stripe) | Recebe, confirma o pagamento, processa liquidação, reembolsos e contestações, conforme seu contrato |
| Profissional | Recebe o valor integral do serviço após a conclusão e liberação |
| Trato | Calcula e mostra os valores em centavos, registra o pedido, analisa problemas e pede ao parceiro as ações permitidas |

`[A VALIDAR PELO ADVOGADO: o desenho atual com Stripe, retenção até confirmação do cliente e repasse posterior configura custódia ou instituição de pagamento? Quem é titular de cada conta e quem liquida no contrato do Stripe?]`

## 3. Métodos e parcelas

- **Métodos do piloto:** **Pix**, **cartão de crédito à vista** e **cartão de crédito parcelado**.
- **Sem surpresa no checkout:** antes de pagar, o cliente vê o **preço total, o número de parcelas, o valor de cada parcela e qualquer acréscimo de parcelamento**.
- **Quem arca com os custos do meio de pagamento:** o **Trato absorve** o custo do Stripe no **Pix** e no **cartão de crédito à vista**. No **cartão parcelado**, o custo financeiro do parcelamento fica por conta do **cliente** `[A VALIDAR PELO ADVOGADO: transparência e repasse do custo de parcelamento ao consumidor]`.
- **Pedido mínimo:** `[A VALIDAR PELO ADVOGADO: há necessidade de informar valor mínimo do pedido nesta política, se adotado pela operação?]`.

## 4. Como o app mostra o status

| Status no app | Significa |
|---|---|
| Aguardando pagamento | O pedido foi aceito; o parceiro ainda não confirmou |
| Pago | **Somente** depois que o parceiro confirma via aviso assinado (webhook) |
| Em análise | Há um caso de problema aberto |
| Reembolso solicitado | Pedido feito ao parceiro; ainda não concluído |
| Reembolsado | O parceiro confirmou a devolução |
| Repasse concluído | O parceiro confirmou que liquidou ao profissional |

O app nunca mostra "pago" ou "reembolsado" por conta própria. Se houver diferença entre o app e o parceiro, vale o registro do parceiro.

## 5. Gratuidade e valor líquido do profissional

- **Taxa do Trato: 0% (gratuito).** O aplicativo é **100% gratuito e sem taxa** para clientes e profissionais nesta fase ("Sem taxa para você. O Trato é gratuito enquanto crescemos.").
- O profissional recebe o **valor cheio** do orçamento aceito (o custo do Pix e do cartão à vista é absorvido pelo Trato).
- Os valores são calculados pelo servidor do Trato, em centavos inteiros, e congelados na proposta aceita.
- Eventuais cobranças futuras de taxa ou assinatura só valerão mediante aviso prévio e atualização desta política `[A VALIDAR PELO ADVOGADO: cláusula para eventual cobrança futura]`.

## 6. Pagamento único e aditivos

- O pagamento é feito em **valor único integral** após o aceite do orçamento (não há pagamento adiantado de parte do valor nem pagamento por etapas).
- Se surgir trabalho extra durante a execução, o profissional envia um **aditivo** no aplicativo, que só vale após aprovação e pagamento pelo cliente dentro do app.

## 7. Descontos com Tratinhos e cupons

- **Tratinhos** (`1 Tratinho = 1 centavo`, validade de **90 dias**) são um desconto promocional **pago pela empresa**. O profissional continua recebendo o valor cheio do serviço.
- **Para o cliente:** ganha Tratinhos ao avaliar um serviço concluído e pago (liberados em **7 dias** sem disputa) e usa como desconto no pagamento, respeitando o **orçamento mensal limitado** e os tetos exibidos no app.
- **Para o profissional:** ganha Tratinhos ao avaliar um cliente que atendeu e usa apenas para solicitar **exclusividade de 48 horas** em um pedido aberto elegível (**100 Tratinhos**). Os Tratinhos do profissional **nunca** viram dinheiro nem desconto.
- `[A VALIDAR PELO ADVOGADO: natureza jurídica dos Tratinhos, validade de 90 dias, limites de orçamento mensal e tratamento tributário/contábil do desconto pago pela empresa]`.

## 8. Liberação ao profissional

- O pagamento fica retido e é liberado após a confirmação do cliente e a janela de proteção de **até 48 horas após a conclusão** (decisão do João em 20/11/2026; *nota de conflito: versões anteriores citavam 48 h + 7 dias*) `[A VALIDAR PELO ADVOGADO: validade da janela de 48 h e se pedir pausa de repasse mantém o Trato fora de atividade regulada]`.
- Com um caso de disputa aberto dentro da janela, o Trato **pede** ao parceiro que pause o repasse, **na medida em que o parceiro permitir**.
- Liquidar é ato do parceiro. O Trato não movimenta dinheiro por conta própria.

## 9. Reembolso

- Cancelamento ou decisão de disputa podem gerar reembolso total ou parcial.
- Quem executa é o parceiro. O prazo depende do método (Pix e cartão têm prazos diferentes no parceiro) `[A VALIDAR PELO ADVOGADO: confirmar prazos reais do Stripe no contrato antes de publicar]`.
- Se o profissional já recebeu e não há saldo disponível: `[A VALIDAR PELO ADVOGADO: quem cobre eventual saldo negativo e como formalizar cobrança ou compensação do profissional em contrato]`.
- O Trato não promete reembolso garantido.

## 10. Contestação no banco ou no cartão (chargeback)

- O cliente pode contestar com o banco ou o emissor do cartão; as regras são do parceiro e da bandeira.
- O Trato junta as provas do pedido (orçamento, chat, check-in/check-out, fotos e notas) quando o parceiro permitir.
- Desconto de valores devolvidos por contestação no que o profissional tiver a receber: `[A VALIDAR PELO ADVOGADO: validade da cláusula de compensação de chargeback no contrato do profissional autônomo]`.

## 11. Dados de recebimento do profissional

- Hoje o profissional cadastra sua chave Pix e/ou dados bancários dentro do aplicativo para receber os repasses.
- `[A VALIDAR PELO ADVOGADO: repasse com chave Pix coletada no app vs. obrigatoriedade de cadastro/KYC e split direto na conta do profissional no Stripe Connect, além de obrigações de prevenção à lavagem de dinheiro (Lei 9.613/1998 citada no escopo)]`.
- O Trato não mantém conta bancária de saque própria nem saldo sacável no app (D15).

## 12. Tela "Carteira" / extrato

A tela mostra o **extrato** do que o parceiro confirmou: pagamentos, repasses, reembolsos e recibo/PDF do período. Não mostra saldo próprio do Trato nem botão de saque do Trato (D15).

## 13. Segurança e privacidade de dados de pagamento

- Dados de cartão são tratados pelo parceiro; o Trato não guarda número do cartão.
- Avisos do parceiro (webhooks) chegam assinados e são processados uma única vez (idempotência).
- Conciliação entre o registro do Trato e o relatório do parceiro: qualquer diferença gera alerta e análise humana.
- `[A VALIDAR PELO ADVOGADO: nomeação formal do DPO e necessidade de RIPD para os fluxos de verificação e pagamento]`.

## 14. Notas fiscais e tributos

`[A VALIDAR PELO ADVOGADO: com taxa 0% durante o piloto, qual obrigação fiscal ou nota cabe à Feito Labs, como declarar os descontos em Tratinhos custeados pela empresa e quais obrigações existem sobre os repasses aos profissionais?]`

## 15. Dúvidas e problemas

Atendimento (SAC) das **08:00 às 20:00**, por equipe própria de suporte, pela Central de ajuda do aplicativo ou pelo e-mail `suporte@trato.app.br`. Ver Política de Cancelamento, Disputa e Liberação `[A VALIDAR PELO ADVOGADO: enquadramento no Decreto 13.135/2026 (SAC)]`.

---

### Anexo — nota interna (apagar na versão final)

- Termos que **não** usar para descrever este fluxo: ver D13 em `harness/DECISOES.md`. Use "pagamento processado por parceiro", "retido pelo parceiro" **somente** se o contrato confirmar, e "repasse".
- Conferir com advogado de meios de pagamento e com o contrato escrito do Stripe se todos os itens acima correspondem ao que está contratado antes de publicar.
