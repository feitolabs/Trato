# Pendências e dúvidas

Itens que precisam de resposta do João (ou de advogado/contador) antes de virar código.
Não inventar regra: enquanto estiver aqui, não implementar.

## Para o João decidir

| # | Dúvida | Onde aparece | Impacto |
|---|---|---|---|
| P1 | **Prazo de liberação automática:** o protótipo (tela Conclusão) diz "48 horas"; as observações dizem "7 dias". Qual vale? 7 dias para tudo, ou 48 h para confirmar + 7 dias de janela de reclamação? | Tela Conclusão, Carteira ("Automático em até 48 h"), escopo 3.2 | Textos de tela e rotina de liberação |
| P2 | **Taxa no piloto (reescrita pela V2):** a V2 manda **uma regra transparente** no piloto, sem lançar a tabela de 3 faixas (7,5 / 5 / 3,5) antes de dados. Qual taxa única testar, e qual a taxa mínima em R$ (se houver)? Resposta depende da simulação de margem (V2.3) com a tarifa real de Pix, cartão à vista e parcelado, taxa fixa, chargeback e reembolso do parceiro. A margem pode ser negativa em ticket baixo. A tabela progressiva (D2) fica **em espera**. Mostrar ao profissional bruto, taxa, custo por método e líquido antes de aceitar. | Auditoria V2 seções 2 e 4; observações item 1 | Cálculo da taxa; F4.2 |
| P3 | **Quem paga a taxa e o custo do meio de pagamento (reescrita pela V2):** a V2 diz para **evitar taxa do cliente "surpresa" no checkout**. Mostrar ao cliente preço total, parcelas e acréscimos antes de pagar. Opções: só o profissional paga (A); cliente paga custo do parcelamento, mostrado com transparência (C); subsídio temporário com orçamento limitado. Qual escolher, e há pedido mínimo? | Escopo seção 2; Auditoria V2 seção 4 | Checkout e calculadora |
| P4 | **30% adiantado:** vai direto ao profissional para começar ou fica retido e liberado só com check-in/nota de material? | Observações | Fluxo de dinheiro |
| P5 | **Telas com "5%"**: a calculadora do protótipo mostra "Taxa Trato (5%)". Trocar o texto para a taxa real calculada? (proposta: sim, mostrar % e valor vindos do backend) | Tela Calculadora, Carteira | Fidelidade ao design |
| P6 | **Cidade do piloto:** o protótipo usa Belo Horizonte (Savassi). Confirmar BH. (Ampliada em P15.) | Escopo 9.3, 12.4 | Categorias e recrutamento |
| P7 | **Parceiro de pagamento e custódia (reescrita pela V2):** a V2 proíbe saldo ou custódia própria e o termo "escrow". Split não é custódia. Perguntas: (1) o parceiro (Stripe Connect, Mercado Pago ou outro) confirma **por contrato e na técnica** retenção/split com Pix no Brasil? (2) Quem é titular das contas, quem liquida, quem cobre fundos insuficientes, chargeback e reembolso? (3) **Caminho A (ledger espelho, recomendado) ou B (manter)?** Ver `docs/v2-impacto.md` seção 3. Até responder, F3.5 não é aplicada e nenhum dinheiro real é movido. | Auditoria V2 seções 3, 4 e 7; escopo 8 | Integração de pagamento; F3.5; F4.4; Carteira |
| P8 | ~~**Fundo de garantia:** de onde vem o dinheiro?~~ **Respondida pela V2 (D13):** não há garantia financiada pelo Trato, nem fundo ou seguro, no MVP. Usar "suporte e análise de problemas" com limites descritos. Só volta quando cobertura, custo, exclusões, prazo e responsável estiverem definidos. O app continua sem prometer cobertura de danos. | Escopo 3.6; Auditoria V2 seções 3 e 4 | Textos e regras |
| P9 | **Painel administrativo:** a V2 definiu **web responsivo** (sem app Ops). Falta só a stack: Flutter Web ou outra? | Escopo 7, 23 | Fase 7 |
| P10 | **Verificação de identidade (documento + selfie):** qual fornecedor? A V2 pede verificação **proporcional ao risco da categoria**, fornecedor que minimize cópias e só o resultado mínimo guardado. | Escopo 3.1 | Fase 6 |
| P11 | **SMS/WhatsApp:** qual provedor (Twilio, Zenvia…)? | Tela Confirmar celular | Fase 5 |
| P12 | **Fontes do protótipo:** identifiquei como Archivo (títulos) e Figtree (corpo) pelo desenho das letras. Confirmar ou mandar os nomes certos. | Todas as telas | Tipografia |
| P13 | **Ícones:** o protótipo usa ícones de traço fino (estilo Lucide). Hoje uso os Material Outlined, que são parecidos. Trocar pelo pacote Lucide na F2.5? | Todas as telas | Fidelidade ao design |
| P14 | **Textos do onboarding (páginas 2 e 3):** o PDF só mostra a página 1 de 3. Escrevi as outras duas com frases das telas de pagamento e disputa ("Seu dinheiro fica protegido", "Se algo der errado, você tem garantia"). Confirmar ou mandar o texto final. | Onboarding | Textos de tela |
| P15 | **Cidade e categorias do piloto:** a V2 pede **uma cidade** e **2 ou 3 categorias de baixo risco** (escopo observável; sem obra estrutural, gás ou atividade regulada). Confirmar BH (substitui P6) e escolher as categorias. Também: quantos profissionais verificados antes de abrir a demanda? | Auditoria V2 seções 3 e 9 | Carga de `cidades` e `categorias`; recrutamento |
| P16 | **Proposta escrita de 2 provedores de pagamento:** obter tarifa (Pix, cartão à vista, parcelado), taxa fixa, prazo de recebimento, chargeback, reembolso, split e saldo negativo. Quem pede é o João. Sem isso não há simulação de margem nem decisão A/B. | Auditoria V2 seção 5 | P2, P3, P7; V2.3 e V2.4 |
| P17 | **Política única de cancelamento, disputa e liberação, com o jurídico:** aceite, prazo para pagar, falta, remarcação, cancelamento, confirmação automática, disputa que congela repasse e retrabalho. Separar a **janela que congela repasse** do **prazo legal** de reclamar. Nunca automatizar renúncia de direito. Absorve P1 (48 h × 7 dias). | Auditoria V2 seções 2 e 7 | Prazos em configuração; F4.7; F4.9; textos |
| P18 | **Decreto 13.135/2026 (SAC):** entrada em vigor indicada para 2/11/2026; fala de atendimento humano e dados dos modelos de atendimento à Senacon. O Trato se enquadra? Quais obrigações e prazos antes do lançamento? Perguntar ao advogado do consumidor. Não reconferi o texto. | Auditoria V2 seção 7 | Central de ajuda; operação |
| P19 | **Responsáveis e datas dos bloqueios de lançamento:** a V2 (seção 7) pede dono e data para fluxo financeiro, preço e margem, regra única de serviço, responsabilidade e promessa, dados e verificação, atendimento e escopo geográfico, antes do primeiro pagamento real. | Auditoria V2 seção 7 | Go/no-go do piloto |

## Para advogado e contador (o agente não decide)

- Custódia do valor retido: exige instituição de pagamento autorizada? (Stripe cobre?) A V2 reforça: split não é custódia; ver enquadramento no BCB.
- Biometria como dado sensível (ANPD), revisão de decisão automatizada e Decreto 13.135/2026 (SAC): ver `docs/advogado-e-contador.md`.
- Nota fiscal da taxa do Trato e enquadramento tributário.
- Responsabilidade solidária (CDC) e direito de regresso contra o profissional.
- Risco de vínculo empregatício.
- Prazo de 7 dias para reclamação vs. direito de arrependimento e garantia legal (CDC).
- Coleta de antecedentes criminais e biometria (LGPD, dados sensíveis).

## Ambiente

- Flutter 3.47.8 instalado em `C:\flutter`, mas **fora do PATH** (o `verificar` acha sozinho).
  Para usar no terminal: adicionar `C:\flutter\bin` ao PATH do usuário.
- Android Studio e SDK instalados; emulador `Medium_Phone_API_37.0` ok. **Falta:** "Android SDK Command-line Tools" e `flutter doctor --android-licenses` (o João aceita). O primeiro build baixou NDK 28.2 e Platform 36 sozinho (~10 min).
- **iOS:** build e simulador só em macOS com Xcode. Definir um Mac (ou CI na nuvem, ex.: Codemagic) antes da Fase 9.
- Supabase CLI e GitHub CLI (`gh`) não estão instalados (opcionais).
- Repositório GitHub "Trato" ainda não está ligado como `origin`.
