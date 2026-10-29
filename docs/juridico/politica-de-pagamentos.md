# Política de Pagamentos — Trato

> **RASCUNHO PARA REVISÃO JURÍDICA. Não é texto final.** Quem escreveu não é advogado.
> Não publicar antes de revisão de advogado de meios de pagamento e de confirmação **por escrito** do parceiro.
> Este texto descreve o desenho desejado (D15, caminho A). Se o parceiro ou o advogado não confirmarem um item, o item **sai**.
> Os pontos `[A DEFINIR: ...]` dependem do João (P1, P2, P6, P7) ou do jurídico.
> Relacionados: `termos-de-uso.md`, `politica-de-cancelamento-e-disputa.md`, `docs/provedores-pagamento.md`, `docs/v2-impacto.md`.
> Versão: `[A DEFINIR]`. Data: `[A DEFINIR]`.

## 1. Em uma frase

O pagamento é **processado por um parceiro de pagamento** `[A DEFINIR: P7/P16 — nome]`. O Trato **não é banco, não guarda saldo seu e não faz saque**. O Trato registra e mostra o que o parceiro confirma.

## 2. Quem faz o quê

| Quem | Papel |
|---|---|
| Cliente | Escolhe o método e paga |
| Parceiro de pagamento | Recebe, confirma, divide o valor entre profissional e Trato, liquida e processa reembolsos e contestações, conforme o contrato dele |
| Profissional | Recebe a parte dele pelo parceiro, após cadastro no parceiro |
| Trato | Calcula e mostra os valores, registra o pedido, analisa problemas e pede ao parceiro as ações permitidas |

`[A DEFINIR: P7 — quem é o titular de cada conta e quem liquida. Preencher só com o texto confirmado em contrato.]`

## 3. Métodos e parcelas

- Métodos do piloto: `[A DEFINIR: P2/P3 — Pix, cartão à vista, cartão parcelado]`.
- Antes de pagar o cliente vê: **preço total, número de parcelas e qualquer acréscimo**. Sem taxa surpresa no checkout.
- Quem arca com o custo do método e do parcelamento: `[A DEFINIR: P3]`.
- Pedido mínimo: `[A DEFINIR: P3]`.

## 4. Como o app mostra o status

| Status no app | Significa |
|---|---|
| Aguardando pagamento | O pedido foi aceito; o parceiro ainda não confirmou |
| Pago | **Somente** depois que o parceiro confirma |
| Em análise | Há um caso de problema aberto |
| Reembolso solicitado | Pedido feito ao parceiro; ainda não concluído |
| Reembolsado | O parceiro confirmou a devolução |
| Repasse concluído | O parceiro confirmou que liquidou ao profissional |

O app nunca mostra "pago" ou "reembolsado" por conta própria. Se houver diferença entre o app e o parceiro, vale o registro do parceiro.

## 5. Taxa e divisão

- Taxa do Trato: `[A DEFINIR: P2 — taxa única do piloto e mínimo, se houver]`.
- O profissional vê, **antes de aceitar**: valor bruto, taxa do Trato, custos por método e valor líquido.
- Os valores vêm do sistema do Trato, em centavos, e são os mesmos da proposta aceita (versão congelada).

## 6. Pagamento em partes e por etapas

`[A DEFINIR: P4/P7 — 30% depois do aceite e o restante ao encerrar; pagamento por etapas. Só entram se o parceiro permitir por contrato. Se não permitir, o pagamento é feito de uma vez, e o texto desta seção é apagado.]`

## 7. Liberação ao profissional

- O repasse segue o prazo do parceiro e a janela da Política de Cancelamento e Disputa: `[A DEFINIR: P1/P17]`.
- Com um caso aberto, o Trato **pede** ao parceiro que pause o repasse, **na medida em que o parceiro permitir**. `[A DEFINIR: P7/P16]`
- Liquidar é ato do parceiro. O Trato não "libera" dinheiro por conta própria.

## 8. Reembolso

- Cancelamento ou decisão de disputa podem gerar reembolso total ou parcial.
- Quem executa é o parceiro. O prazo depende do método e do parceiro (Pix e cartão têm prazos diferentes). `[A DEFINIR: P16 — prazos reais.]`
- Se o profissional já recebeu e não há saldo: `[A DEFINIR: P7 — quem cobre e como se cobra do profissional. Texto só com base em contrato.]`
- O Trato não promete reembolso garantido.

## 9. Contestação no banco ou no cartão (chargeback)

- O cliente pode contestar com o banco ou o emissor do cartão; as regras são do parceiro e da bandeira.
- O profissional concorda que valores devolvidos por contestação podem ser descontados do que ele tem a receber `[A DEFINIR: JURÍDICO + P7 — cláusula no contrato do profissional]`.
- O Trato junta as provas do pedido quando o parceiro permitir.

## 10. Cadastro do profissional no parceiro

- Para receber, o profissional faz o cadastro (identidade e dados de recebimento) no parceiro. `[A DEFINIR: P16 — se o cadastro ocorre na tela do parceiro e quais dados o Trato recebe.]`
- Saque ou transferência para a conta bancária: feito pelo parceiro, conforme regras dele. O Trato não faz saque.

## 11. Tela "Carteira" / extrato

A tela mostra **extrato** do que o parceiro registrou: pagamentos, taxas, repasses, reembolsos. Não mostra saldo do Trato nem botão de saque do Trato (D15).

## 12. Segurança

- Dados de cartão são tratados pelo parceiro; o Trato não guarda número do cartão.
- Avisos do parceiro (webhooks) chegam assinados e são processados uma única vez (idempotência).
- Conciliação diária entre o registro do Trato e o relatório do parceiro. Diferença gera alerta e análise humana.

## 13. Notas fiscais e tributos

`[A DEFINIR: CONTADOR — nota da taxa do Trato; obrigações sobre os repasses; informações ao profissional.]`

## 14. Dúvidas e problemas

Pelo suporte do app. Ver Política de Cancelamento e Disputa. `[A DEFINIR: canais e horários — OPERAÇÕES.]`

---

### Anexo — nota interna (apagar na versão final)

- Termos que **não** usar para descrever este fluxo: ver D13 em `harness/DECISOES.md`. Use "pagamento processado por parceiro", "retido pelo parceiro" **somente** se o contrato confirmar, e "repasse".
- Conferir com Adv. pagamentos: se dividir o pagamento e pedir pausa de repasse mantém o Trato fora de atividade regulada (itens 1 e 11 de `docs/advogado-e-contador.md`).
