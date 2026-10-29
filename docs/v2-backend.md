# Backend após a D13 (Auditoria e Escopo V2)

Só `backend/`. Nada foi aplicado no banco; nenhum SQL novo. Valores continuam em centavos.

## O que mudou

1. **"Pago" só pelo parceiro.** Novo estado `aguardando_confirmacao` (nome: "Aguardando
   confirmação do pagamento"). O cliente só **informa** o pagamento
   (`POST /v1/pedidos/{id}/acoes/informar_pagamento`). O pedido vira `pago_e_retido` e a
   cobrança entra no ledger **apenas** no webhook assinado `payment_intent.succeeded`
   (`api/webhook_pagamento.py`). `PedidoOut.pagamento_confirmado` diz ao app se já pode
   mostrar "pago".
   - Reenvio do mesmo evento: descartado pela idempotência da rota. Outro evento do mesmo
     pagamento: sem efeito (pedido já tem referência; chave do ledger = `cobranca:<pedido>:<ref>`).
   - Fora de ordem: confirmação antes do aviso do cliente vale; antes do aceite do orçamento
     responde 409 e o provedor reenvia. `payment_failed` depois de pago não desfaz; em
     `aguardando_confirmacao` volta a `orcamento_aceito`.
   - Assinatura inválida/ausente/velha: 400, nada muda. Valor diferente do contrato: nada vira pago.
   - Pedido em `aguardando_confirmacao` não expira nem cancela (dinheiro em trânsito).
2. **Textos e garantia.** `ConfigGarantia.garantia_financiada_habilitada = False` por padrão
   (vem da tabela de configuração, nunca fixo no fluxo). Desligada, a reatribuição de retrabalho
   custeada pelo Trato é recusada e o caso segue por "suporte e análise de problemas". Testes
   garantem que OpenAPI e módulos não trazem "garantia total", "escrow", "reembolso automático" etc.
3. **Congelar repasse ≠ prazo legal.** `disputas.abrir` não recusa mais a reclamação fora da
   janela (isso renunciaria um direito); só marca `abertura_dentro_da_janela_de_congelamento`.
   Prazos legais ficam em `ConfigDisputa.prazos_legais` + `disputas/prazos_legais.py`:
   apenas informativos. Em `rotinas/`, `janela_reclamacao` virou `janela_congelamento_repasse`
   (e `liberacao_espera_janela` → `liberacao_espera_congelamento`).

## Pontos que dependem de decisão

- **P1** (48 h x 7 dias): valores de `prazo_liberacao`, `janela_congelamento_repasse` e
  `prazo_congelar_repasse_horas` seguem só em configuração.
- **P4** (30% adiantado): não implementado; sem retenção/adiantamento de reserva (fora do MVP).
- **P7** (Stripe Connect/Pix, custódia): o ledger ainda usa a conta `custodia`; não criar saldo
  próprio sem confirmação do parceiro. Nomes do evento Stripe (`payment_intent.*`, `metadata.pedido_id`)
  precisam ser confirmados na integração real.
- **P8** (fundo de garantia): `garantia_financiada_habilitada` fica desligada até lá.
- Números dos prazos legais: advogado (`docs/advogado-e-contador.md`).
- O texto de tela "Pago e retido" só aparece após confirmação; a copy final é da frente de telas.
