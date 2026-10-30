# Política de Cancelamento, Disputa e Liberação — Trato

> **RASCUNHO PARA REVISÃO JURÍDICA. Não é texto final.** Quem escreveu não é advogado.
> Não publicar antes de revisão de advogado do consumidor e do parceiro de pagamento. Normas citadas
> (CDC arts. 26 e 49, entre outras) vêm do escopo e **não foram reconferidas**.
> Todos os prazos abaixo são **provisórios** e ficam em tabela de configuração, não no código.
> Os pontos `[A DEFINIR: ...]` dependem do João (P1, P2, P6, P7, P17) ou do jurídico.
> Atende P17 (política única) e absorve P1 (48 h × 7 dias).
> Relacionados: `termos-de-uso.md`, `politica-de-pagamentos.md`, `docs/advogado-e-contador.md` (itens 3, 5, 6, 13).
> **Versão: `[A DEFINIR: ex.: 0.1-rascunho]`. Vigência: `[A DEFINIR]`.**

## 1. Princípios

1. **Uma política só**, versionada. Toda mudança gera nova versão, com data de vigência e aceite registrado.
2. **Duas coisas diferentes:**
   - **Janela de proteção do repasse:** prazo **interno do Trato** em que o pagamento fica sujeito à análise de problema antes de ser liberado ao profissional.
   - **Prazos legais do consumidor:** arrependimento, garantia legal e reclamação por vício. Estes vêm da lei. **O Trato não os reduz.**
3. **Nunca renúncia automática de direito.** Nenhuma ação passiva do cliente (não responder, deixar o prazo passar, tocar em "concluir") significa que ele abriu mão de direito. O texto do app não pode sugerir isso.
4. O app mostra a regra **antes** de o cliente confirmar. A política tem versão e o contrato do pedido registra qual versão valeu.
5. Decisão de disputa é de **analista humano**, com justificativa e canal de resposta.
6. O Trato **não promete reembolso garantido nem cobertura de danos**. O dinheiro segue o fluxo do parceiro de pagamento (ver Política de Pagamentos).

## 2. Tabela de prazos (provisórios, em configuração)

| Item | Valor provisório | Observação |
|---|---|---|
| Prazo para o cliente pagar após o aceite | `[A DEFINIR: P17]` | Depois dele o aceite perde a validade |
| Cancelamento sem custo pelo cliente | mais de 24 h antes do serviço (do escopo) `[A DEFINIR: P17]` | Chave `prazo_cancelamento_reembolso_integral_horas` |
| Janela de proteção do repasse após a conclusão | `[A DEFINIR: P1/P17 — 7 dias (observações) ou 48 h + 7 dias (protótipo)]` | Chave `janela_chargeback_dias` / `prazo_liberacao_dias` |
| Confirmação pelo cliente após conclusão | `[A DEFINIR: P1/P17]` | Silêncio **não** encerra direitos (ver 1.3) |
| Prazo para abrir caso com congelamento do repasse | `[A DEFINIR: P17]` | Chave `prazo_congelar_disputa_horas`. Só congela o repasse. **Não** limita o direito legal |
| Resposta do analista | `[A DEFINIR: OPERAÇÕES]` | Sem promessa de resposta imediata |
| Direito de arrependimento (compra fora do estabelecimento) | **Prazo legal** `[A DEFINIR: Adv. consumidor — aplicação ao serviço agendado pelo app]` | A lei prevalece |
| Garantia legal e reclamação por vício | **Prazos legais** `[A DEFINIR: Adv. consumidor]` | A lei prevalece |

## 3. Regras por situação

### 3.1 Aceite e pagamento
- O cliente aceita uma proposta; o app mostra preço total, parcelas e acréscimos.
- O serviço só é confirmado após **confirmação do pagamento pelo parceiro**. Antes disso o app mostra "aguardando pagamento", nunca "pago".
- Prazo para pagar: `[A DEFINIR: P17]`. Se falhar o pagamento, o pedido volta para "aguardando".

### 3.2 Cancelamento pelo cliente
- Mais de `[A DEFINIR: 24 h]` antes: reembolso integral pelo meio de pagamento, no prazo do parceiro.
- Menos que isso: `[A DEFINIR: P17 + Adv. consumidor — retenção de deslocamento ou tempo gasto]`. Qualquer valor retido precisa estar **visível antes** da confirmação do cancelamento e ser proporcional ao que de fato ocorreu (prova de chegada pelo check-in).
- Serviço já iniciado a pedido do cliente e desistência dentro do prazo legal: `[A DEFINIR: Adv. consumidor]`.
- O reembolso segue o fluxo e o prazo do parceiro. O app mostra o status real (solicitado, concluído).

### 3.3 Cancelamento pelo profissional
- Cancelar com motivo válido **não gera penalidade automática** nem reduz posição de ninguém.
- O cliente recebe reembolso integral e é avisado para escolher outra proposta.
- Faltas repetidas e sem motivo: análise humana, com contraditório. `[A DEFINIR: Adv. trabalhista — evitar efeito de subordinação.]`

### 3.4 Falta e remarcação
- Falta do profissional: reembolso integral.
- Falta do cliente (profissional presente, provado por check-in): `[A DEFINIR: P17 — valor retido]`.
- Remarcação: uma vez, de comum acordo registrado no app. `[A DEFINIR: P17]`

### 3.5 Conclusão e confirmação
- O profissional marca como concluído. O cliente confirma ou relata problema.
- Se o cliente não responde no prazo de confirmação, o pedido segue para a liberação ao profissional **sem prejuízo dos direitos legais do cliente**, e o cliente ainda pode relatar problema depois, pelos canais de suporte. `[A DEFINIR: Adv. consumidor — redação.]`

### 3.6 Disputa
1. O cliente (ou o profissional) abre um caso: categoria, descrição, fotos relacionadas ao serviço.
2. Se o caso é aberto dentro do prazo da janela, o Trato **pede ao parceiro de pagamento** que o repasse fique pausado, **somente se e como o parceiro permitir** `[A DEFINIR: P7/P16]`. O Trato não move dinheiro por conta própria.
3. A outra parte responde no prazo `[A DEFINIR]`.
4. Um **analista humano** decide, com **justificativa escrita** e canal para contestar a decisão.
5. Resultados possíveis: manter o pagamento ao profissional; reembolso total ou parcial; retrabalho pelo profissional; encaminhar para o parceiro (chargeback) ou para a via judicial.
6. Reembolso por decisão da disputa é executado pelo parceiro, nas condições dele e **conforme saldo e regras do parceiro**. `[A DEFINIR: P7 — quem cobre fundos insuficientes.]`
7. A decisão da plataforma **não impede** o cliente de buscar seus direitos (parceiro, banco, órgão de defesa do consumidor ou Justiça).

### 3.7 Retrabalho
- Quando cabe, o mesmo profissional corrige sem custo ao cliente, em prazo combinado.
- Se o profissional não corrige, o caso volta para a disputa.
- **O Trato não paga retrabalho nem terceiro** (sem garantia financiada pelo Trato). `[A DEFINIR: JURÍDICO — redação alinhada ao CDC.]`

### 3.8 Chargeback e contestação junto ao banco ou cartão
- O cliente pode contestar a compra no seu banco ou cartão. Isso segue regras da bandeira e do parceiro.
- O Trato apresenta as provas do pedido (aceite, check-in, fotos, chat) quando o parceiro permitir.
- Quem arca com o valor, se perder: `[A DEFINIR: P7/P16 + Adv. consumidor e contrato do profissional]`.

## 4. O que o app mostra ao usuário (resumo para o time de produto)

- Antes de pagar: preço total, parcelas, regra de cancelamento resumida e link para esta política.
- Antes de cancelar: quanto será devolvido e quanto será retido, com motivo.
- Na conclusão: o prazo de confirmação **e** a frase de que o cliente continua com os direitos que a lei garante.
- Nunca: texto de renúncia automática, "sem direito a reclamação", "reembolso garantido" ou promessas proibidas pela D13.

## 5. Dependências antes de publicar

| Dependência | Quem |
|---|---|
| Janela e prazos (P1, P17) | João + Adv. consumidor |
| O que o parceiro permite (pausa de repasse, reembolso, chargeback) | Parceiro (P7, P16) |
| Arrependimento, serviço iniciado, garantia legal | Adv. consumidor |
| Penalidades e faltas sem risco trabalhista | Adv. trabalhista |
| Atendimento: canais, horários e Decreto 13.135/2026 | Adv. consumidor + Operações |
