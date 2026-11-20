# Decisões: Tratinhos, orçamento de desconto e exclusividade

Registro feito pelo Mestre em 20/11/2026. Todas as decisões abaixo foram confirmadas pelo João, salvo o que estiver marcado como **EM ABERTO**.
Este arquivo vale mais que `contexto.md` e a spec da Etapa B quando houver diferença. Dinheiro: sempre centavos inteiros, só o backend decide.

## 1. Modelo do app
- O app é **100% gratuito, sem taxa** (decisão de 18/11/2026), para validar o produto e ganhar visibilidade.
- Assinaturas e taxas poderão vir no futuro. Não há promessa pública sobre isso além da frase curta aprovada: "Sem taxa para você. O Trato é gratuito enquanto crescemos."
- **Custo do Stripe: o Trato absorve** (confirmado pelo João em 20/11/2026). O profissional recebe o valor cheio do serviço.
  - **Parcelado no cartão: o custo fica por conta do cliente** (confirmado pelo João em 20/11/2026). O Trato absorve o custo do Pix e do cartão à vista. Isso confere com o que o `contexto.md` já diz.
- Quem paga o desconto em Tratinhos é a empresa.

## 2. Tratinhos (a moeda)
- Nome: **Tratinho** (plural Tratinhos). 1 Tratinho = 1 centavo. Mostrar sempre também em reais ("50 Tratinhos = R$ 0,50").
- **Cliente:** ganha 50 Tratinhos ao avaliar o profissional (serviço concluído e pago, mínimo de R$ 50, 1 bônus por profissional por mês, teto de 500 Tratinhos por mês). Os Tratinhos são liberados **7 dias depois**, se não houver disputa. Usa como desconto na tela de pagamento (máximo 20% por pedido). Validade: **90 dias**.
- **Profissional:** ganha 50 Tratinhos ao avaliar um cliente que atendeu. Só avalia clientes que atendeu, **1 avaliação por cliente, vitalícia**. Mesma carência de 7 dias sem disputa e mesma validade de 90 dias.
- Só o **cliente** usa Tratinhos como desconto em dinheiro. A moeda do profissional serve só para a exclusividade e **nunca** vira desconto pago pela empresa nem dinheiro.

## 3. Orçamento de desconto (Etapa A)
- Orçamento total: **R$ 300 por mês** (30000 centavos), em tabela de configuração.
- Teto diário: **R$ 10 por dia** (1000 centavos).
- Teto por cliente: **R$ 5 por mês** (500 centavos).
- Aviso no painel admin ao chegar a **80%** do orçamento.
- Ao esgotar (dia, mês ou teto do cliente): o app mostra "Desconto indisponível agora", com a data de volta e o motivo. Os Tratinhos ficam guardados. O dia volta amanhã; o mês e o teto do cliente voltam no dia 1º.
- Reserva do desconto atômica (dois pagamentos ao mesmo tempo não estouram o orçamento). Estorno total devolve a reserva; parcial não devolve.
- Todos os valores ficam em tabela de configuração e podem ser mudados sem alterar o código.

### Contabilidade do desconto (decisão de 20/11/2026)
- O custo do desconto de Tratinhos **não** entra no ledger nem no fechamento mensal nesta rodada. Fica para a **rodada seguinte**.
- Enquanto isso, a única trilha do que a empresa pagou de desconto é o controle do orçamento (`moedas_orcamento_mensal` e `moedas_orcamento_diario`).
- Registrar no fechamento muda o cálculo dos meses já fechados, então a conta nova deve entrar **sem alterar** os meses fechados.
- **Prazo:** decidir e implementar antes de fechar o primeiro mês com desconto ligado.

### Aplicar a migration x ligar o desconto
- A revisão da Seguranca (20/11/2026) aprovou **aplicar** a migration `20261120100000_moedas_orcamento.sql`, mas **reprovou ligar** o desconto em produção (`moedas_config.ativo`) até corrigir: saldo gasto duas vezes, reserva presa por Pix sem pagamento, devolução em dobro por webhook repetido e valor da devolução quando o valor da moeda muda. Correção recomendada: tabela de reservas por cobrança e rotina de expiração.

### Estado do banco (20/11/2026)
- **Aplicada no Supabase real com o OK do João:** `20261120100000_moedas_orcamento.sql` (5 colunas novas em `moedas_config`, tabelas `moedas_orcamento_mensal`, `moedas_orcamento_diario` e `moedas_pendentes`, funções de reserva e devolução). Conferido pelo agente Banco com SELECT.
- **Antes de aplicar, `moedas_config.ativo` já era `true`** (desconto ligado em produção, sem os limites novos). O João autorizou aplicar mesmo assim.
- **Escrita, NÃO aplicada:** `20261120200000_moedas_reservas.sql` (reservas por cobrança). Depende da anterior e do Backend corrigido.
- **Validade de 90 dias:** UPDATE de configuração ainda NÃO feito.

## 4. Exclusividade de 48 horas (Etapa B, ainda não construída)
Custa **100 Tratinhos**, máximo **3 ao mesmo tempo** por profissional.

| Item | Decisão |
|---|---|
| (a) Quem pode receber | O cliente precisa ter um **pedido aberto elegível**, para evitar spam. Isso é mais restrito do que "qualquer cliente". |
| (b) Prazo do cliente para responder | **6 horas** |
| (c) O que conta como "atender" | **Enviar o orçamento** |
| (d) Carteira | **Separada**: a carteira do profissional é separada da do cliente |
| (e) Avaliação do cliente | **1 por cliente, vitalícia** |
| (f) Cliente aceita outro orçamento antes das 48h | Libera a exclusividade e **devolve as moedas** ao profissional |
| (g) Depois de recusa | O mesmo profissional **não pode pedir exclusividade ao mesmo cliente de novo por um período** |
| (g) Validade das moedas do profissional | **90 dias**, igual às do cliente |
| (g) Categorias sem exclusividade | **Urgência**: vazamento, falta de luz e chaveiro |

Regras já decididas antes:
- O cliente pode recusar ("Recusar e ver outros", com o mesmo destaque de aceitar; os outros orçamentos continuam visíveis).
- Se o cliente **recusar ou ignorar** (passado o prazo de 6 horas), as 100 Tratinhos voltam **inteiras** ao profissional na hora.
- Se o cliente aceitar e o profissional **não atender em 48 horas**, a exclusividade é cancelada, o profissional **perde** as moedas, e outros profissionais voltam a poder enviar orçamento.
- Textos: para o profissional, "prioridade que você ganhou avaliando", nunca "comprar cliente"; para o cliente, "Sem compromisso".

**Bloqueio depois de uma recusa (item g): 30 dias** (confirmado pelo João em 20/11/2026), valor em tabela de configuração. Vale só para o mesmo profissional com o mesmo cliente; outros profissionais e outros clientes não são afetados.

**Categorias sem exclusividade (decisão de 20/11/2026):** o catálogo não tem categorias separadas de "vazamento" nem de "falta de luz". Ficam sem exclusividade a categoria **chaveiro** (`permite_exclusividade = false`) e **todo pedido marcado como urgente** pelo cliente (`pedidos.urgente = true`). Encanador e eletricista continuam liberados. O app deve avisar o cliente, ao pedir: "Marque como urgente se não puder esperar". O UPDATE que bloqueia o chaveiro é dado e só roda com o OK do João, junto da aplicação da migration `20261121100000_exclusividade_schema.sql`.

**EM ABERTO:**
- Os itens que a spec da Etapa B ainda lista como perguntas abertas e que não aparecem acima.

## 5. Pontos de abuso e segurança a cobrir
- Avaliação falsa, conluio e contas múltiplas para juntar Tratinhos (a liberação em 7 dias sem disputa ajuda; limite por CPF ou aparelho a avaliar).
- Spam de exclusividade (custo de 100 Tratinhos, máximo de 3 ao mesmo tempo, só com pedido aberto elegível).
- A Seguranca revisa o dinheiro, as permissões e o abuso antes de a Etapa A ser fechada.
- Termos de cobrança, desconto e validade de moeda: vale uma revisão jurídica antes do lançamento.
