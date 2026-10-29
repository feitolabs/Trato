# Decisões

Registro das decisões que valem para o projeto. Mais recentes no fim.
Fonte: `observações extras que discutimos d.txt` (vale mais que o escopo em PDF).

| # | Decisão | Substitui no escopo | Fonte |
|---|---|---|---|
| D1 | O app se chama **Trato** (não WorkNet). Empresa: Feito Labs. | "WorkNet" em todo o PDF | Observações |
| D2 | Taxa do Trato: **tabela progressiva**, **base 7,5%**, **taxa mínima configurável** (tabela no banco). | "5%" fixo (seções 2, 4, 8, 22.2) | Observações |
| D3 | Chargeback: o **cliente tem até 7 dias** para reclamar (ou ir à Justiça). O Trato não cobre sozinho. | "WorkNet absorve o primeiro risco" (8.2) | Observações |
| D4 | Calcular o **custo do Stripe** (Pix e cartão) e mostrar quanto sobra para o Trato em cada serviço. | Estimativa genérica (seção 2) | Observações |
| D5 | Orçamento é **grátis**. Após o aceite, o cliente paga **30% adiantado**; ao encerrar, paga o restante. | Pagamento integral no aceite (3.2, 8.1) | Observações |
| D6 | O dinheiro **só é liberado ao encerrar**. Após **7 dias** sem problema, libera o saldo. Opção de pagar **por etapas**. | Liberação automática em 48/72 h (3.2) — ver P1 | Observações |
| D7 | Problema = **disputa**. Valor congelado até a decisão. | — (confirma 3.5) | Observações |
| D8 | O profissional **envia a nota dos materiais** ao cliente, com custo de cada item. | Nota só para sinal de material (3.2) | Observações |
| D9 | **Aditivo com preço** para imprevistos. Só vale com aprovação do cliente no app. | — (confirma 3.4) | Observações |
| D10 | Stack: Python (backend), Flutter (app), Supabase (projeto "Trato"), GitHub (repo "Trato"), Stripe. Expo **não** é usado. | Sugestão Node/Go (seção 11) | regras.txt |
| D11 | Gitflow: `main`, `develop`, `feature/*`, `release/*`, `hotfix/*`. | — | Pedido do João (28/10/2026) |
| D12 | Backend em **FastAPI** + Python 3.11 (3.15 ainda é pré-lançamento). | — | Escolha técnica (a confirmar) |
