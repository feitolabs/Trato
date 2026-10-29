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
| D13 | **"Trato Feito — Auditoria e Escopo V2" (29/10/2026) vale** sobre as observações e o escopo antigo, exceto onde o João decidir diferente. Fora do MVP: SOS próprio, garantia financiada pelo Trato, fundo/seguro, adiantamento de materiais, retenção de reserva, score, ranking, mapa, app Ops. O app **nunca mostra "pago"** antes da confirmação do provedor. **Textos proibidos:** "escrow", "garantia total", "profissional seguro", "reembolso automático", "menor taxa do mercado", "atendimento 24/7"; usar "suporte e análise de problemas". Painel admin = web responsivo. Taxa: uma regra transparente no piloto; a tabela progressiva (D2) fica **em espera** até simulação de margem (P2). Custódia/saldo próprio: **não criar** sem confirmação contratual do parceiro (conflita com carteira/ledger; ver P7). | D2 (em espera), 3.6 garantia, SOS, textos de proteção | Auditoria V2 + OK do João (29/10/2026) |
| D14 | **Login:** e-mail com senha, Google e Apple (sem custo). **SMS só na confirmação do celular no cadastro**, uma vez por pessoa, com limite de tentativas e reenvios, código de 5 min e CAPTCHA antes do envio. Provedor de SMS: Supabase Auth + Send SMS Hook com provedor brasileiro barato (P11 em aberto: Zenvia/Comtele). WhatsApp fica para a V1. | Login por telefone como principal (tela Login) | Pedido do João (29/10/2026) |
| D15 | **Custódia: caminho A.** O ledger só **espelha** o que o parceiro de pagamento liquida. O Trato **não guarda saldo próprio e não faz saque**; a tela Carteira vira extrato. A F3.5 como está (saldos, repasses e saques do Trato) **não será aplicada**; será refeita para o caminho A antes de aplicar. A F3.6 espera a F3.5 refeita. | F3.5 original, tela Carteira, saque Pix | Escolha do João (29/10/2026), recomendada pela análise de impacto V2 |
