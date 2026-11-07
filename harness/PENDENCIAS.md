# Pendências e dúvidas

Itens que precisam de resposta do João (ou de advogado/contador) antes de virar código.
Não inventar regra: enquanto estiver aqui, não implementar.

## Respondidas (decisão D16, 30/10/2026, em `DECISOES.md`)

Atualizado em 04/11/2026. A tabela abaixo mantém o histórico das dúvidas; estas já têm resposta:

- **P1:** 48 h para o cliente confirmar + 7 dias de janela de reclamação, como prazos separados.
- **P3, P4, P5, P8, P9:** como na V2 (sem taxa surpresa ao cliente; sem os 30% adiantados; taxa real nas telas; sem garantia financiada; painel web).
- **P6 e P15 (cidade):** Belo Horizonte/MG; categorias Limpeza residencial, Montagem de móveis e Pintura de interiores.
- **P7:** Stripe, caminho A (ledger espelho).
- **P11:** sem SMS no piloto (login por e-mail, Google e Apple).
- **P12 a P14:** seguem as recomendações de `docs/fidelidade-visual.md`.
- **P2:** regra única e transparente no piloto; **o valor ainda estava a fechar** (aberto até o João informar o número).
- **Ainda abertas:** P10 (fornecedor de verificação), P16 a P19 (sem resposta registrada nos arquivos).

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

## Sobras da revisão de segurança (30/10/2026)

Detalhe item a item em `docs/sobras-seguranca.md`; testes em ambiente real em `docs/roteiro-testes-reais.md`.

- **PRECISO DO SEU OK (migration, só em arquivo):** `20261030140000_b2_grants_por_coluna.sql` (B2). Seguem aguardando OK
  `20261030000000_fix_acesso_…` e `20261030120000_ordens_estorno.sql`.
- **Decisão sua:** B6 (um papel por conta), código de 6 dígitos (A1), CPF em claro ou só hash (M11), retenção de
  documentos (A8, advogado).
- **Depende de ambiente real:** rodar `harness/teste_real_rls.py`, `teste_real_webhook.py` e `teste_real_banco.py` com as suas chaves.
- **Técnico aberto:** ligar `ServicoPagamento` na fábrica Postgres (depende de P7 e da sessão `backend-divergencias`);
  aviso ao cliente no bloqueio do código; lock com hash do backend; contadores em Redis se houver mais de uma instância.

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

## Painel admin v2 (03/11/2026)

**Decisões suas (travam requisitos obrigatórios do documento, seção 10):**
1. **Tabela de taxas:** hoje há só a taxa única de 7,50% (`taxa_progressiva_ativa = 0`). Faixas e como aparecem em Configurações.
2. **Quem custeia o cupom** (Trato ou profissional): muda a Receita Trato e o extrato fiscal. O painel não calcula desconto concedido.
3. **Tetos de alçada por papel.** Valores **provisórios** na tabela `papeis_alcada` (Administrador R$ 5.000, Financeiro e Líder R$ 2.000,
   Mediador e Atendente N2 R$ 500, Atendente N1 R$ 300, demais R$ 0). A alçada efetiva de cada pessoa agora é limitada a esse teto:
   **os administradores existentes (gravados com R$ 100.000.000,00) passaram a valer R$ 5.000,00** e decisões de disputa acima disso
   esperam uma segunda pessoa. Para mudar: `update papeis_alcada set teto_centavos = … where papel = '…'`.
4. **Níveis de verificação:** o painel mostra o nível pedido e as categorias separados, mas quais níveis existem e o que liberam não está definido.
5–9. Visibilidade por cidade/raio (RN-01), ajuda das categorias, mobile como app separado, papel Analista de risco, arquivo de design (Figma).

**Respostas do Emanuel (03/11/2026), ainda não aplicadas no sistema:**
- **Taxa (1):** faixas por valor do serviço: R$ 30 a 40 = taxa mínima; 40 a 500 = 7,5%; 501 a 1.000 = 10%; 1.000 a 50.000 = 15%.
  Conta do ponto de corte: mínimo R$ 3,00 ÷ 7,5% = **R$ 40,00** (abaixo disso vale o mínimo, a partir daí os 7,5%). A faixa vale
  sobre o valor inteiro (como o código já faz). Pontas a confirmar: faixa 500–501 sem valor definido, e R$ 1.000 aparece em duas faixas.
  Aplicar = propor nova versão de configuração (dupla aprovação), ligando `taxa_progressiva_ativa`.
- **Cupom (2):** quem paga é o Trato (sai da margem do Trato, o profissional recebe o valor cheio).
- **Nível verificado (5):** só o nível "Verificado". Benefícios: perfil com selo, mais visibilidade e acesso a mais de 5 orçamentos
  (o limite de quem não é verificado fica abaixo de 5; falta o número).
- **Limite de serviço em andamento:** o profissional pega um serviço por vez até encerrar (número exato a confirmar).
- **Filtro por cidade (6):** pedido deve aparecer só por categoria **e cidade**; mapa interativo fica para a v2.
- **Conflito:** a faixa de 15% vai até R$ 50.000, mas o teto de valor do pedido proposto acima é R$ 1.000. O teto precisa subir (ou a faixa não será usada).

**Aguardando o fluxo normal (não fiz por regra de dupla aprovação):**
- Propor em Configurações o **teto de valor do pedido** (documento: R$ 1.000,00) e o **limite de valor atípico** (R$ 800,00). Sem
  isso o backend não barra pedido caro e o Risco não gera alerta de valor atípico.
- Existem duas contas "João Vitor Cardoso" na equipe (`cardosojoaovitor47@` e `cardosojoavitor47@`; a segunda nunca entrou). Revogar
  a que não é sua pelo painel.
- Dados de teste ainda no banco (`teste_admin`, `teste_financeiro`, `teste_Pintura`, versão 1 de configuração com motivo "teste_…", pedidos
  de teste). Versões de configuração aprovadas são imutáveis e a auditoria é imutável: limpar exige decisão sua (RNF-07).

**Não feito (precisa de OK ou de dependência externa):**
- Convite por e-mail e 2FA obrigatório no primeiro acesso (RF-EQP-01, RNF-03): precisa da API de admin do Supabase e envio de e-mail
  (efeito real). Hoje a pessoa precisa já ter conta no Trato.
- Fila de suporte (RF-BUS-05): não existe tabela nem rota de chamados; a aba mostra o estado vazio com orientação. Atribuir, responder e
  encerrar dependem disso. Idem "desativar categoria" com contagem de pedidos em andamento.
- Geração de relatório em segundo plano com aviso (RF-REL-02): hoje gera na hora e baixa; o código de download fica na memória do processo
  (serve com 1 instância; com várias, trocar por tabela).
- Preferência de marketing no app: o painel respeita `preferencias.marketing.push = false`, mas o app ainda não grava essa preferência.
- Tema escuro do design system (valores não vieram nas capturas); Analista de risco; detalhe de cupom com pedidos e total de desconto
  (RF-CUP-04); agendamento de push; revisão de acessos a cada 90 dias; regras combinadas de risco; filtros do painel por cidade e categoria.
- Cobertura de testes de integração contra o Supabase real para as consultas novas (validei as principais com `SELECT` no banco real).

## App do profissional (07/11/2026)
- Raio de atendimento ("Até onde você vai"): a tela coleta, mas o app não envia e o backend não guarda (`CadastroIn` não tem o campo). Decidir: gravar o raio (coluna + filtro de pedidos por distância, RN-01) ou tirar a pergunta da tela.
