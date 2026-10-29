# Pendências e dúvidas

Itens que precisam de resposta do João (ou de advogado/contador) antes de virar código.
Não inventar regra: enquanto estiver aqui, não implementar.

## Para o João decidir

| # | Dúvida | Onde aparece | Impacto |
|---|---|---|---|
| P1 | **Prazo de liberação automática:** o protótipo (tela Conclusão) diz "48 horas"; as observações dizem "7 dias". Qual vale? 7 dias para tudo, ou 48 h para confirmar + 7 dias de janela de reclamação? | Tela Conclusão, Carteira ("Automático em até 48 h"), escopo 3.2 | Textos de tela e rotina de liberação |
| P2 | **Faixas da tabela progressiva:** quais faixas e percentuais? (ex.: até R$ 500 = 7,5%; acima = ?). A base 7,5% é a maior ou a menor faixa? Qual a taxa mínima inicial em R$? | Observações item 1 | Cálculo da taxa |
| P3 | **Quem paga a taxa e o custo do Stripe:** só o profissional (opção A) ou cliente paga acréscimo no cartão (opção C)? | Escopo seção 2 | Checkout e calculadora |
| P4 | **30% adiantado:** vai direto ao profissional para começar ou fica retido e liberado só com check-in/nota de material? | Observações | Fluxo de dinheiro |
| P5 | **Telas com "5%"**: a calculadora do protótipo mostra "Taxa Trato (5%)". Trocar o texto para a taxa real calculada? (proposta: sim, mostrar % e valor vindos do backend) | Tela Calculadora, Carteira | Fidelidade ao design |
| P6 | **Cidade do piloto:** o protótipo usa Belo Horizonte (Savassi). Confirmar BH. | Escopo 9.3, 12.4 | Categorias e recrutamento |
| P7 | **Stripe no Brasil:** Stripe Connect com Pix e retenção até a conclusão atende o modelo? Conta já existe? | Escopo 8 | Integração de pagamento |
| P8 | **Fundo de garantia:** de onde vem o dinheiro? Enquanto não definir, o app **não promete cobertura de danos**. | Escopo 3.6 | Textos e regras |
| P9 | **Painel administrativo:** web separado em Flutter Web ou outra stack? | Escopo 7, 23 | Fase 7 |
| P10 | **Verificação de identidade (documento + selfie):** qual fornecedor? | Escopo 3.1 | Fase 6 |
| P11 | **SMS/WhatsApp:** qual provedor (Twilio, Zenvia…)? | Tela Confirmar celular | Fase 5 |
| P12 | **Fontes do protótipo:** identifiquei como Archivo (títulos) e Figtree (corpo) pelo desenho das letras. Confirmar ou mandar os nomes certos. | Todas as telas | Tipografia |

## Para advogado e contador (o agente não decide)

- Custódia do valor retido: exige instituição de pagamento autorizada? (Stripe cobre?)
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
