# Política de Cancelamento, Disputa e Liberação — Trato

> **Versão 1.1 — rascunho para revisão do advogado — 22/11/2026**
> *(Versão anterior: rascunho inicial.)*
> **RASCUNHO PARA REVISÃO JURÍDICA. Não é texto final.** Quem escreveu não é advogado.
> Não publicar antes de revisão de advogado do consumidor, trabalhista e do parceiro de pagamento. Normas citadas (CDC arts. 26 e 49 e Decreto 13.135/2026, entre outras) vêm dos documentos anteriores do projeto e **não foram reconferidas**.
> Todos os prazos abaixo ficam em tabela de configuração do servidor e refletem as decisões do João até 22/11/2026.
> Relacionados: `termos-de-uso.md`, `politica-de-pagamentos.md`, `docs/decisoes-moedas-e-exclusividade.md`, `docs/advogado-e-contador.md`.

## 1. Princípios

1. **Uma política só**, versionada. Toda mudança gera nova versão, com data de vigência e aceite registrado.
2. **Duas coisas diferentes:**
   - **Janela de proteção do repasse:** prazo **interno do Trato** em que o pagamento fica sujeito à análise de problema antes de ser liberado ao profissional.
   - **Prazos legais do consumidor:** arrependimento, garantia legal e reclamação por vício. Estes vêm da lei. **O Trato não os reduz.**
3. **Nunca renúncia automática de direito.** Nenhuma ação passiva do cliente (não responder, deixar o prazo passar, tocar em "concluir") significa que ele abriu mão de direito. O texto do app não pode sugerir isso.
4. O app mostra a regra **antes** de o cliente confirmar. A política tem versão e o contrato do pedido registra qual versão valeu.
5. Decisão de disputa é de **analista humano**, com justificativa escrita e canal para contestar.
6. O Trato **não promete reembolso garantido nem cobertura de danos**. O dinheiro segue o fluxo do parceiro de pagamento (**Stripe Brasil** — ver Política de Pagamentos).

## 2. Tabela de prazos (configuração vigente e pontos a validar)

| Item | Valor definido até 22/11/2026 | Observação |
|---|---|---|
| Prazo para o cliente pagar após o aceite | Configurável no servidor | Depois dele o aceite perde a validade `[A VALIDAR PELO ADVOGADO: prazo adequado e aviso ao consumidor]` |
| Cancelamento sem custo pelo cliente | Antes do aceite ou mais de **24 h** antes do serviço | Chave `prazo_cancelamento_reembolso_integral_horas` |
| Confirmação pelo cliente após conclusão | **48 horas** após o check-out com código | Se o check-out for sem código, exige confirmação explícita do cliente. Silêncio **não** encerra direitos (ver 1.3) |
| Janela de proteção / congelamento do repasse após a conclusão | **Até 48 horas** após a conclusão (decisão de 20/11/2026: `prazo_congelar_disputa_horas = 48`, `prazo_liberacao_dias = 0`) | *Conflito anterior:* D16 e Termos 1.0 citavam 48 h + 7 dias. Só congela o repasse; **não** limita o direito legal `[A VALIDAR PELO ADVOGADO: janela de 48 h vs. 7 dias frente ao CDC]` |
| Liberação dos Tratinhos de avaliação | **7 dias** após a avaliação, sem disputa | Prazo separado do repasse em dinheiro; validade dos Tratinhos: **90 dias** |
| Atendimento (SAC) e resposta do analista | Equipe própria das **08:00 às 20:00** | Sem promessa de resposta imediata `[A VALIDAR PELO ADVOGADO: prazo máximo de resposta e enquadramento no Decreto 13.135/2026]` |
| Direito de arrependimento (compra fora do estabelecimento) | **Prazo legal** (art. 49 do CDC citado nos rascunhos) | A lei prevalece `[A VALIDAR PELO ADVOGADO: aplicação ao serviço agendado ou iniciado pelo app]` |
| Garantia legal e reclamação por vício | **Prazos legais** (art. 26 do CDC citado nos rascunhos) | A lei prevalece `[A VALIDAR PELO ADVOGADO: redação de garantia legal e contratual]` |

## 3. Regras por situação

### 3.1 Aceite e pagamento
- O cliente aceita uma proposta; o app mostra preço total, parcelas e acréscimos de parcelamento (Pix e cartão à vista não têm acréscimo; o app é 100% gratuito e sem taxa).
- O serviço só é confirmado após **confirmação do pagamento pelo parceiro (Stripe)** via webhook assinado. Antes disso o app mostra "aguardando pagamento", nunca "pago".
- Se o pagamento falhar ou expirar o prazo para pagar, o pedido não é confirmado.

### 3.2 Cancelamento pelo cliente
- **Antes do aceite:** cancelamento livre e sem custo.
- **Mais de 24 h antes do serviço agendado:** reembolso integral pelo meio de pagamento, no prazo do parceiro.
- **Menos de 24 h antes do serviço:** `[A VALIDAR PELO ADVOGADO: é válido reter valor proporcional de deslocamento/tempo comprovado por check-in e qual limite é seguro?]`. Qualquer valor retido precisa estar **visível antes** da confirmação do cancelamento e ser proporcional ao que de fato ocorreu.
- **Serviço já iniciado a pedido do cliente e desistência no prazo legal:** `[A VALIDAR PELO ADVOGADO: regra de reembolso proporcional no direito de arrependimento]`.
- **Desconto em Tratinhos em caso de estorno:** no estorno total, a reserva de desconto é devolvida; no estorno parcial, não é devolvida `[A VALIDAR PELO ADVOGADO: validade dessa regra e efeito sobre bônus de avaliação em pedido estornado]`.
- O reembolso segue o fluxo e o prazo do parceiro. O app mostra o status real (solicitado, concluído).

### 3.3 Cancelamento pelo profissional
- Cancelar com motivo válido **não gera penalidade automática** nem reduz posição de ninguém.
- O cliente recebe reembolso integral e é avisado para escolher outra proposta.
- Faltas repetidas e sem motivo: análise humana, com contraditório `[A VALIDAR PELO ADVOGADO: critérios de suspensão sem risco de vínculo trabalhista]`.

### 3.4 Falta e remarcação
- **Falta do profissional:** reembolso integral ao cliente.
- **Falta do cliente (profissional presente, provado por check-in):** `[A VALIDAR PELO ADVOGADO: qual regra ou valor de retenção por deslocamento é defensável e como exibir antes do pagamento?]`.
- **Remarcação:** feita de comum acordo registrado no app `[A VALIDAR PELO ADVOGADO: limite de remarcações e reflexo no prazo de cancelamento]`.

### 3.5 Conclusão e confirmação
- O profissional registra o check-out (foto e código final). Se registrar check-out sem código do cliente, precisa justificar e o sistema **não conclui automaticamente** — exige confirmação explícita do cliente.
- No check-out com código, o cliente tem **48 horas** para confirmar ou relatar problema.
- Se o cliente não responder no prazo de 48 horas, o pedido segue para a liberação ao profissional **sem prejuízo dos direitos legais do cliente**, e o cliente ainda pode relatar problema depois, pelos canais de suporte `[A VALIDAR PELO ADVOGADO: redação de confirmação por prazo sem renúncia de direitos]`.

### 3.6 Disputa
1. O cliente abre um caso pelo app com descrição e fotos relacionadas ao serviço *(nota técnica: hoje a abertura de disputa no app é do cliente; confirmar se o profissional também deve abrir pelo app ou pelo suporte)*.
2. Se o caso é aberto dentro da janela de **até 48 horas após a conclusão**, o Trato **pede ao parceiro de pagamento** que o repasse fique pausado, **somente se e como o parceiro permitir** `[A VALIDAR PELO ADVOGADO: pausa de repasse no parceiro e conformidade com contrato do Stripe]`. O Trato não movimenta dinheiro por conta própria.
3. A outra parte tem prazo para responder e apresentar provas (hoje 48 h nos rascunhos) `[A VALIDAR PELO ADVOGADO: prazo de resposta da outra parte]`.
4. Um **analista humano** decide, com **justificativa escrita** e canal para contestar a decisão.
5. Resultados possíveis: manter o pagamento ao profissional; reembolso total ou parcial; retrabalho pelo profissional; encaminhamento via parceiro (chargeback) ou via judicial.
6. Reembolso por decisão da disputa é executado pelo parceiro, nas condições dele `[A VALIDAR PELO ADVOGADO: quem cobre fundos insuficientes se o profissional já recebeu?]`.
7. A decisão da plataforma **não impede** o cliente de buscar seus direitos (parceiro, banco, órgão de defesa do consumidor ou Justiça).

### 3.7 Retrabalho
- Quando cabe, o mesmo profissional corrige sem custo ao cliente, em prazo combinado (a garantia continua contando da primeira conclusão).
- Se o profissional não corrige, o caso volta para a disputa.
- **O Trato não paga retrabalho nem terceiro** (sem garantia financiada pelo Trato) `[A VALIDAR PELO ADVOGADO: redação alinhada à responsabilidade solidária do CDC]`.

### 3.8 Chargeback e contestação junto ao banco ou cartão
- O cliente pode contestar a compra no seu banco ou cartão. Isso segue regras da bandeira e do parceiro.
- O Trato apresenta as provas do pedido (aceite, check-in, fotos, chat) quando o parceiro permitir.
- Responsabilidade em caso de perda de contestação: `[A VALIDAR PELO ADVOGADO: quem arca com o valor e cláusula de compensação no contrato do profissional]`.

## 4. O que o app mostra ao usuário (resumo para o time de produto)

- Antes de pagar: preço total, parcelas e acréscimos, regra de cancelamento resumida e link para esta política.
- Antes de cancelar: quanto será devolvido e eventual valor retido, com motivo.
- Na conclusão: o prazo de confirmação (**48 horas**) **e** a frase de que o cliente continua com os direitos que a lei garante.
- Nunca: texto de renúncia automática, "sem direito a reclamação", "reembolso garantido" ou promessas proibidas pela D13.

## 5. Atendimento (SAC) e pendências para revisão jurídica

- **Atendimento do piloto:** equipe própria de suporte das **08:00 às 20:00**, pela Central de ajuda no app e `suporte@trato.app.br`.
- `[A VALIDAR PELO ADVOGADO: o Trato se enquadra no Decreto 13.135/2026 (SAC), citado no checklist sem reconferência do texto? Quais obrigações de protocolo, canais, prazo de resposta e envio de dados à Senacon se aplicam?]`

| Tema a validar | Especialidade |
|---|---|
| Janela de 48 h (decisão 20/11) vs. 7 dias, confirmação tácita, arrependimento, cancelamento < 24 h e garantia legal | Adv. consumidor |
| Pausa de repasse, estorno, saldo negativo e chargeback no contrato do Stripe | Adv. pagamentos + Stripe |
| Faltas repetidas, suspensão e contrato próprio do profissional sem vínculo | Adv. trabalhista |
| Tratinhos (natureza jurídica, 90 dias, estorno total/parcial) | Adv. consumidor + pagamentos |
| DPO, RIPD de biometria/verificação e guarda de provas de disputa | Adv. dados (LGPD) |
| Atendimento 08:00–20:00 e Decreto 13.135/2026 (SAC) | Adv. consumidor |
