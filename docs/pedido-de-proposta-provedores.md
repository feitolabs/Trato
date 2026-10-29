# Pedido de proposta a provedores de pagamento

> **RASCUNHO. NÃO ENVIAR sem o João revisar.** Nenhum e-mail ou contato foi feito.
> Não é parecer jurídico. O enquadramento regulatório deve ser revisado por advogado de meios de pagamento.
> Atende P16 (proposta escrita de 2 provedores) e a seção 7 da Auditoria V2 (fluxo financeiro).
> Comparação prévia: `docs/provedores-pagamento.md`.

## 1. Como usar

1. João escolhe 2 provedores (sugestão a partir da pesquisa: Stripe Connect + um brasileiro com split, como Asaas ou Pagar.me).
2. Troca os campos `[ ]` do e-mail.
3. Envia por conta própria. Pede resposta **por escrito** e anexa o questionário.
4. As respostas alimentam `docs/simulacao-margem.md` (trocar as estimativas) e as decisões P2, P3 e P7.

Dados do Trato para o pedido: Feito Labs, marketplace de serviços presenciais, piloto em uma cidade `[A DEFINIR: P6/P15 — cidade]`, 2 ou 3 categorias de baixo risco `[A DEFINIR: P15]`, Pix e cartão `[A DEFINIR: P2/P3 — métodos do piloto]`.

## 2. Estimativas de volume (para o provedor precificar)

| Item | Valor |
|---|---|
| Ticket médio esperado | `[A DEFINIR: João]` |
| Faixa de ticket | de R$ `[ ]` a R$ `[ ]` |
| Serviços por mês no piloto | `[A DEFINIR: João]` |
| Profissionais recebendo | `[A DEFINIR: João]` |
| Participação de Pix × cartão | `[A DEFINIR: João]` |

## 3. Questionário objetivo

Peça resposta em campo próprio, com cláusula ou página do contrato que sustenta. Sem resposta clara = **"não confirmado"**.

### A. Papel e enquadramento regulatório
1. Em que papel o Trato atua com o seu produto: marketplace, subcredenciador, facilitador ou outro? Qual o enquadramento perante o Banco Central?
2. O Trato precisa de autorização própria para dividir pagamentos? Em que condições?
3. Quem é o titular das contas e do dinheiro em cada etapa (cliente, profissional, Trato, provedor)?
4. O produto usa liquidação centralizada pelo provedor? Há documento que descreve isso?

### B. Fluxo e liquidação
5. Quando o dinheiro chega ao profissional? Qual o prazo para Pix e para cartão (à vista e parcelado)?
6. É possível **reter** o valor até a conclusão do serviço? Para Pix? Para cartão? Por quanto tempo no máximo? Isso é garantido por contrato?
7. É possível pagar uma parte (30%) agora e o resto depois, em cobranças separadas?
8. Quem decide a liberação: o Trato por API, ou o provedor por regra fixa?
9. O provedor liquida o repasse ao profissional ou o Trato precisa movimentar dinheiro? (O Trato **não** quer guardar saldo nem fazer saque.)
10. Há eventos assinados (webhook) para: pagamento confirmado, repasse liquidado, reembolso, chargeback? Como é a assinatura e a idempotência?

### C. Split
11. Como se define a divisão (valor fixo, %)? A taxa do provedor sai de quem?
12. O split pode ser alterado depois do pagamento (aditivo, desconto, reembolso parcial)?
13. Qual o limite de recebedores por cobrança e de valor por cobrança?

### D. Fundos insuficientes, saldo negativo e reembolso
14. Se o profissional já recebeu e o cliente pede reembolso, quem cobre? O que acontece se não houver saldo?
15. O saldo da conta do profissional (ou do Trato) pode ficar negativo? Quem responde e como se cobra?
16. Reembolso parcial e total: prazo, custo, e o que acontece com as tarifas já cobradas?
17. O reembolso devolve ao meio original? Quanto tempo leva no Pix e no cartão?

### E. Chargeback e contestação
18. Quem arca com o chargeback quando o split já foi liquidado? Dá para escolher quem responde por cobrança?
19. Valor da tarifa por contestação. Prazo para responder. Quem envia a defesa?
20. Como funciona a devolução especial do Pix (MED)? O provedor pode debitar a conta mesmo depois do repasse?
21. Há reserva (retenção de parte do recebível) para cobrir chargeback? Qual percentual e prazo?

### F. Preço
22. Tarifa de Pix, cartão à vista e parcelado (2–6x, 7–12x), por bandeira. Taxa fixa por transação.
23. Tarifa de conta ativa, de repasse e de roteamento de fundos, se houver.
24. Antecipação: custo e prazo.
25. Tarifa mínima, mensalidade, taxa de ativação, desconto por volume, vigência da proposta e reajuste.
26. Quem paga o parcelamento: o profissional, o Trato ou o cliente (com o acréscimo claro no checkout)?

### G. Cadastro (KYC) do profissional
27. O provedor faz KYC do profissional (CPF e MEI/CNPJ)? Quais documentos e dados? Quanto tempo leva? O que acontece com reprovados?
28. O cadastro roda numa tela do provedor ou na nossa? O Trato recebe só o resultado ou também os documentos?
29. Como fica a LGPD: quem é controlador e operador de cada dado? Onde os dados ficam?

### H. Suporte e conciliação
30. Canal de suporte técnico e de disputa, horário e prazo de resposta contratual. (Sem promessa de plantão contínuo.)
31. Relatório de conciliação: formato, frequência, campos (id do pagamento, split, tarifas, repasse). Há API ou arquivo diário?
32. Ambiente de testes (sandbox) com Pix e split? Dá para simular chargeback e reembolso?
33. Cobertura da API para backend em Python e SDK ou componente para Flutter (Android e iOS)?

### I. Termos de uso do provedor
34. Quais categorias de serviço são proibidas ou restritas? (Serviços residenciais presenciais estão ok?)
35. O provedor pode reter valores, bloquear conta ou encerrar o contrato? Com que aviso?
36. Quais cláusulas de responsabilidade e indenização o Trato assume?

## 4. E-mail-modelo (rascunho — NÃO ENVIAR)

**Assunto:** Pedido de proposta — pagamentos para marketplace de serviços presenciais (Trato / Feito Labs)

Olá, `[nome]`,

Sou `[nome e cargo]`, da Feito Labs. Estamos desenvolvendo o Trato, um marketplace que conecta clientes a profissionais autônomos para serviços presenciais, com piloto em `[cidade]` e `[categorias]`.

Estamos comparando provedores de pagamento e pedimos uma **proposta comercial por escrito** para o modelo abaixo.

**Como funciona o fluxo**
- O cliente paga pelo app (Pix e cartão `[confirmar]`).
- O pagamento é processado pelo parceiro. O Trato não pretende guardar saldo nem fazer saque.
- O valor é dividido entre o profissional e o Trato (taxa da plataforma).
- Em caso de problema, o cliente abre um caso e o Trato analisa. Precisamos saber como pausar ou devolver o valor pelo seu produto.

**Volume estimado do piloto**
- Ticket médio: R$ `[ ]`. Faixa: R$ `[ ]` a R$ `[ ]`. Serviços por mês: `[ ]`.

**O que pedimos**
1. Responder o questionário anexo (36 perguntas) por escrito, citando a cláusula do contrato que sustenta cada resposta.
2. Tabela de tarifas para Pix, cartão à vista e parcelado, e demais taxas.
3. Minuta do contrato e dos termos de uso aplicáveis a marketplaces.
4. Documentação técnica e acesso ao ambiente de testes.
5. Uma reunião de 30 minutos para tirar dúvidas, se possível.

Pedimos especial atenção a: liquidação, divisão do pagamento, fundos insuficientes, reembolso, chargeback, saldo negativo, prazos, suporte, conciliação e o enquadramento regulatório do nosso modelo.

Prazo desejado para a resposta: `[data]`. Esta mensagem é um pedido de informações, sem compromisso de contratação.

Obrigado,
`[nome]` — Feito Labs — `[contato]`

## 5. Quadro para comparar as respostas

| Pergunta | Provedor 1 | Provedor 2 |
|---|---|---|
| Retenção até a conclusão confirmada por contrato (6) | | |
| Quem cobre saldo negativo (14–15) | | |
| Quem arca com chargeback após split (18) | | |
| Pix: tarifa e prazo (5, 22) | | |
| Cartão à vista e parcelado: tarifa (22) | | |
| KYC do profissional (27–28) | | |
| Enquadramento regulatório documentado (1–4) | | |
| Conciliação por API ou arquivo (31) | | |
| Python e Flutter (33) | | |

Regra: pergunta sem resposta escrita fica **"não confirmado"** e o recurso não entra no produto (D13, D15).
