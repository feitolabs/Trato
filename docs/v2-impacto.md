# Análise de impacto da V2

> Fonte: "Trato Feito — Auditoria e Escopo V2" (29/10/2026). Vale sobre o escopo antigo e as observações (D13).
> Este documento **não altera SQL, código nem banco**. Compara o que a V2 pede com o que já existe
> e recomenda. Quem decide é o João. Nada aqui é parecer jurídico.

Legenda de recomendação: **manter** · **desligar por configuração** (existe, mas fica inativo no piloto) · **adiar** (não construir agora) · **remover** (tirar do plano; só depois de decisão do João).
Risco: o que dá errado se a recomendação não for seguida.

## 1. Resumo

- A V2 corta o escopo para uma fatia vertical: **uma cidade, 2–3 categorias de baixo risco, pagamento por parceiro**.
- O banco das migrations F3.3–F3.8 (ainda **não aplicadas**) foi desenhado para o escopo grande. Boa parte pode ficar como está e ser **desligada por configuração**.
- Um ponto é conflito de verdade: **ledger, repasses e saques** (F3.5) × "não criar saldo ou custódia própria". Ver seção 3.
- Como nada da F3.3–F3.8 foi aplicado no Supabase, **corrigir agora é barato**. Depois de aplicado, o ledger é imutável e só se corrige por estorno.

## 2. Tabela de impacto

| # | Item da V2 | O que a V2 diz | O que já existe | Recomendação | Risco |
|---|---|---|---|---|---|
| 1 | Custódia e saldo próprio | "Não criar saldo ou custódia própria." Retenção/split só se o parceiro confirmar em contrato e na técnica. Não chamar de escrow. | `contas_ledger`, `lancamentos`, `partidas` (F3.5); backend `financeiro/ledger.py`; telas Pagamento e Carteira; textos "dinheiro protegido" (P14). | **Decisão A/B** (seção 3). Enquanto isso, **manter** o SQL sem aplicar e **trocar os textos** para "pagamento processado por parceiro". | Alto. Pode configurar atividade regulada se o Trato "segurar" dinheiro. |
| 2 | Ledger e carteira | Sem saldo próprio. Só reconciliação com o parceiro. | `lancamentos`/`partidas` imutáveis; saldos derivados; 4.6 pronto e testado; tela Carteira com dados de exemplo (F6.6). | Caminho A: **manter como registro espelho**. Tela Carteira vira "extrato de pagamentos", sem saldo "retido/a liberar" que o Trato controle. | Médio. Saldo exibido pode ser lido como custódia. |
| 3 | Saques | Liquidação é do parceiro; o profissional recebe do parceiro. | `chaves_pix`, `saques` (F3.5); tela de saque Pix na Carteira (F6.6). | **Desligar por configuração** / **adiar**: não aplicar saque como função do Trato; o repasse é evento do provedor. Se o parceiro exigir conta do profissional, o cadastro vai para o onboarding do parceiro. | Alto se o Trato mover dinheiro por conta própria (Pix de saída). |
| 4 | Repasses | "Liquidação pelo parceiro" no fluxo canônico. | `repasses` (F3.5); backend `rotinas` (liberação por prazo). | **Manter** como registro do que o provedor liquidou (status vindo do webhook). Remover a ideia de o Trato "liberar" o dinheiro. | Médio. |
| 5 | Pagamento e "pago" | O app **nunca** mostra "pago" antes da confirmação do provedor. | `pagamentos.status` com `pendente → confirmado`; webhook assinado e idempotente (F4.5); tela de Pagamento ligada ao aceite. | **Manter.** Revisar a tela para só exibir "pago" após o evento confirmado. Garantir que o aceite do orçamento não vire "pago". | Alto (chargeback, disputa de fato). |
| 6 | Pagamento 30% adiantado e por etapas | Checkout simples; "adiantamento de materiais" fora do MVP. | `pagamentos.tipo` (`adiantamento`, `saldo`, `etapa`, `aditivo`); `etapas`; D5/D6. | **Desligar por configuração** `etapa` e adiantamento de material. Manter `adiantamento` 30% só se o parceiro permitir retenção parcial. Ver P4. | Médio. |
| 7 | Garantia e retrabalho | Fora do MVP: garantia financiada pelo Trato, fundo/seguro. Usar "suporte e análise de problemas". | `garantias`, `retrabalhos` (`custo_centavos`) (F3.6); backend `garantias/`; telas Garantia e Relatar problema. | **Manter** tabelas (a garantia do profissional pelo próprio serviço é legal e comercial dele). **Remover** qualquer promessa de cobertura paga pelo Trato; textos trocados. `retrabalhos.custo_centavos` não pode ser pago pelo Trato. | Médio. Texto de "garantia" vira promessa de seguro. |
| 8 | Disputa | Caso com evidência; congelar só conforme fluxo aprovado pelo parceiro; analista humano com justificativa. Política única de cancelamento/disputa. | `disputas`, `disputa_evidencias` (F3.6); backend `disputas/` (48 h, 5 dias úteis); tela Relatar problema. | **Manter**, mas o "congelamento" vira **pedido ao parceiro**, não ação do Trato no ledger. Prazos (48 h, 5 dias, 7 dias) ficam em configuração até a política única (nova P17). | Alto se prazos ferirem direito legal (CDC). |
| 9 | SOS | Fora do MVP: SOS próprio, central 24h, localização ao vivo. | Botão/atalho SOS e "compartilhar atendimento" previstos na F5.13; referência em `pedido_execucao_tela.dart`, `check_in_tela.dart`. Nenhuma tabela própria. | **Adiar.** Tirar o SOS da F5.13. Manter só link de ajuda e denúncia. | Baixo para o banco. Médio de imagem se prometer socorro sem central. |
| 10 | Taxa progressiva | Uma regra transparente no piloto; sem tabela de 3 faixas antes de dados. Simular margem. | `config_faixas_taxa` (F3.2, aplicada, vazia); `contratos.taxa_bps_aplicada`; F4.2 bloqueada (P2); `pagamentos/custo.py` (4.3 pronto). | **Manter** a tabela (vazia) e **usar uma faixa só** no piloto. F4.2 vira "taxa única configurável". Simulador de margem antes de fixar o número (nova tarefa V2.3). | Alto: margem pode ficar negativa em ticket baixo e Pix/parcelado. |
| 11 | Prazo de liberação | Uma política única, versionada, aprovada por jurídico e parceiro. Separar "janela que congela" de "prazo legal". | Chaves `janela_chargeback_dias`, `prazo_liberacao_dias`, `prazo_congelar_disputa_horas` na configuração; `pagamentos.janela_chargeback_ate`; rotina 4.9; P1 (48 h × 7 dias). | **Manter em configuração.** P1 deixa de ser dúvida de texto e vira parte da política única (P17). Liberação passa a ser **evento do parceiro**. | Alto (CDC art. 49 e 26). |
| 12 | Verificação proporcional ao risco | Fornecedor especializado; guardar resultado mínimo; não copiar documentos; sem antecedentes para toda categoria. | `verificacoes`, `verificacao_documentos` (`excluir_em`), `perfis_profissional.nivel_verificacao` (`basico`, `verificado`, `verificado_plus`), bucket privado (F3.2 e F3.8c); F6.1 (documento + selfie). | **Manter** o nível por categoria (`nivel_verificacao` já existe). **Desligar** `verificado_plus` (antecedentes) e reverificação periódica. Guardar só o resultado do fornecedor; o bucket de documentos fica sem uso até P10. | Alto (LGPD, dado sensível). |
| 13 | Score e ranking | Sem score do cliente, sem ranking automático, sem penalidade por recusa. Só avaliação ligada a serviço concluído, contagem e indicadores transparentes. | `avaliacoes`, `avaliacao_criterios` (F3.6). Nenhuma tabela de score (N15). | **Manter** avaliações. **Adiar** score e ranking (já estavam sem tabela). Não criar nota punitiva do cliente. | Baixo. Risco trabalhista se vier ranking por obediência. |
| 14 | App Ops | Fora do MVP. Painel web responsivo e fila manual. | Nada de app Ops. Painel admin: F7.x e P9 em aberto. | **Adiar** app Ops. P9 respondida em parte: **painel web responsivo** (Flutter Web ou outra stack ainda a escolher). | Baixo. |
| 15 | Escopo geográfico e categorias | 1 cidade, 2–3 categorias de baixo risco. Sem obra estrutural, gás ou atividade regulada. | `cidades`, `categorias`, `categoria_perguntas` (F3.2, vazias). Protótipo usa BH/Savassi (P6). | **Manter.** Carregar só a cidade e as categorias do piloto. Nova pendência P15. | Médio (liquidez). |
| 16 | Endereço, contato e mensagens | Endereço exato só após contratar; contato com consentimento; chat vinculado ao pedido. | `pedidos_endereco` (F3.3), RLS "endereço só após contratação" (F3.8), `conversas`, `mensagens` (F3.7). | **Manter.** Já alinhado. | Baixo. |
| 17 | Auditoria e admin | Auditoria e conciliação são indispensáveis. | `auditoria` imutável (F3.7), `eventos_webhook` (F3.5). | **Manter.** Conciliação com o parceiro entra como tarefa nova (V2.5). | Baixo. |
| 18 | Textos de tela | Textos proibidos: "escrow", "garantia total", "profissional seguro", "reembolso automático", "menor taxa do mercado", "atendimento 24/7". | P5 ("Taxa Trato (5%)"), P14 ("Seu dinheiro fica protegido"), telas Onboarding, Pagamento, Carteira, Garantia, Conclusão. | **Trocar** textos (tarefa V2.1). Verificar com busca no `verificar`. | Médio (propaganda enganosa). |
| 19 | SAC / atendimento | Decreto 13.135/2026 (entrada em vigor indicada em 2/11/2026): atendimento humano e dados à Senacon. | Nada no banco. Central de ajuda é tela. | Nova P18 e tarefa para o advogado. Não implementar sem enquadramento. | Médio (multa). |

## 3. Conflito central: ledger e saques × "sem custódia própria"

**O conflito.** A V2 diz: "Não criar saldo ou custódia própria. Só usar retenção/split se o parceiro confirmar contratualmente e tecnicamente." E: "split não é sinônimo de custódia".
O modelo atual (F3.5 + F4.6 + telas da Carteira) faz o contrário:

- `contas_ledger` guarda saldos por usuário: "retido", "a liberar", "liberado".
- `repasses` e `saques` são ações que o **Trato** executa (liberar, sacar via Pix).
- A tela Carteira mostra esses saldos como se fossem do Trato.

Se o Trato mantém saldo de terceiros e decide quando pagar, isso se parece com **conta de pagamento / custódia**. Pode exigir autorização do Banco Central. É o item 1 da lista do advogado.

### Caminho A — ledger como registro espelho do que o provedor liquida

- O **parceiro** guarda o dinheiro e liquida. O Trato **não** guarda saldo.
- O ledger continua, mas só **espelha** eventos do provedor (pagamento confirmado, split, repasse liquidado, reembolso, chargeback). Cada lançamento nasce de um webhook assinado; nunca de uma decisão do Trato.
- `saques` e `chaves_pix` deixam de ser funções do Trato. O profissional recebe pelo parceiro.
- A Carteira vira **extrato**: "recebido", "em processamento pelo parceiro". Sem botão "sacar" próprio.
- Conciliação diária: ledger espelho × relatório do parceiro. Diferença vira alerta.
- O SQL pode ser **reaproveitado quase todo**. O que muda é a regra do backend e a configuração: `saques` fica desativado. Eventual ajuste de SQL (ex.: remover ou deixar vazia `saques`) seria nova migration, a ser decidida.

### Caminho B — manter como está até o parceiro confirmar a custódia

- Segue o desenho atual (ledger com saldos próprios, repasses e saques do Trato).
- Parte do princípio de que o parceiro (ex.: Stripe Connect) vai confirmar que o modelo é permitido.
- Menos retrabalho agora. Mais risco: se o parceiro ou o advogado disserem "não", o ledger de saldos, as telas e o backend 4.4/4.6 precisam mudar **depois** das migrations aplicadas.
- Exige travar: nenhum dinheiro real, nenhuma migration F3.5 aplicada, nenhum texto de "protegido".

### Comparação

| | A — espelho | B — manter |
|---|---|---|
| Aderência à V2 | Alta | Baixa até o parceiro confirmar |
| Risco regulatório | Menor | Maior |
| Retrabalho de SQL | Pouco (configuração; talvez 1 migration) | Nenhum agora; possível retrabalho grande depois |
| Retrabalho de backend/tela | Médio (Carteira, saque, rotinas de liberação) | Nenhum agora |
| Depende de proposta do parceiro | Sim, para saber se há split | Sim, e também da autorização |
| Reversível | Sim: dá para evoluir para B depois | Difícil voltar atrás com ledger aplicado |

### Recomendação: **Caminho A**

1. Combina com a V2 e com D13: "não criar custódia sem confirmação contratual".
2. É a opção **reversível**: espelho pode virar custódia depois, com contrato e advogado. O contrário (desfazer custódia) é caro.
3. Reaproveita quase todo o trabalho já feito (ledger, idempotência, webhooks, conciliação).
4. Custa pouco agora: mudar textos, travar saque, escrever o backend "pago após provedor".

Condição para trocar para B: parceiro confirma por escrito o modelo (retenção e split) **e** o advogado de pagamentos confirma o enquadramento (P7 e item 1 de `docs/advogado-e-contador.md`).

**Até a decisão:** F3.5 fica sem aplicar. As outras migrations (F3.3, F3.4, F3.6–F3.8) não dependem da escolha, exceto referências a `pagamentos` na F3.6 e na RLS da F3.8; isso deve ser conferido por quem for aplicar.

## 4. O que não muda

Pedidos, orçamentos comparáveis, contrato com versão congelada, execução (etapas, aditivo, check-in/out), chat, notificações, auditoria, RLS e máquina de estados (F4.1): tudo isso está no MVP da V2 e segue.

## 5. Ordem sugerida

1. João decide A ou B (V2.4). Recomendo A.
2. Trocar textos de tela (V2.1) — não depende de nada.
3. Backend "pago só após provedor" (V2.2).
4. Simulador de margem (V2.3) com a proposta real de 2 provedores (P16).
5. Só então pedir OK para aplicar F3.3–F3.8.
