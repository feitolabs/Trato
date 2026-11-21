# Pendências e dúvidas

Itens que precisam de resposta do João (ou de advogado/contador) antes de virar código.
Não inventar regra: enquanto estiver aqui, não implementar.

## Estado em 20/11/2026 (atualização D2)

Fonte: `harness/PROGRESSO.md`, `git log`, arquivos no disco e `flyctl releases`. Legenda: ✅ resolvida, 🔶 parcial, ⏳ aberta.
Tudo abaixo desta seção até "Para o João decidir" é novo; as seções antigas continuam como histórico, com marcas ✅/⏳ de 20/11 onde houve mudança.

### ✅ Resolvidas (com evidência)

- ✅ **Taxa do Trato (P2, P3, P5 e a "tabela de taxas" do painel v2):** decisão do João em 18/11: o app é 100% gratuito e a taxa saiu do código. Evidência: PROGRESSO "2026-11-18 — App 100% gratuito" e "Taxa removida de vez". As respostas do Emanuel sobre faixas de taxa (03/11) ficaram sem efeito. O custo do Stripe no Pix e no cartão à vista é do Trato; o custo de parcelamento continua com o cliente.
- ✅ **P1, prazo de liberação:** 48 h para o cliente confirmar + 7 dias de janela (D16); registro em `8b2abab` ("decisão de prazo 48h").
- ✅ **Etapa B, exclusividade de 48 h:** commits `7e88d2b` (backend, rotina de expiração e avisos) e `5839a4e` (telas); migrations `20261121100000_exclusividade_schema.sql` e `20261121200000_exclusividade_funcoes.sql` aplicadas no Supabase em 20/11 (cabeçalho da segunda: "APLICADA em 2026-11-20"; a primeira foi informada pelo Mestre); backend no ar na release v31 do Fly. Decisões em `docs/decisoes-moedas-e-exclusividade.md`.
- ✅ **CPF opcional no cadastro:** `bed0c35` (migration), `e6bf09c` (backend), `e0886b1` (app); migration `20261121300000_cpf_opcional_cadastro.sql` aplicada em 20/11 (cabeçalho); no ar na release v32.
- ✅ **Fuso do mês no bônus das moedas:** B13 `c5f0b41` (bônus no fuso de São Paulo, reservas só do mês corrente, `limite_por_usuario` do cupom).
- ✅ **Publicar backend e painel (antes "publicar no Render/Vercel"):** backend no Fly (app `trato`, gru), release **v37** `complete` (`flyctl releases -a trato`, 20/11); painel na Vercel (projeto `trato-admin`, https://trato-admin-delta.vercel.app), publicado em 20/11 com o commit `5dbc8c1` (define nova senha + "Esqueci a senha"). O código já não referencia o Render (PROGRESSO 10/11, linha "App aponta para a API no Fly.io").
- ✅ **Extrato em PDF no app do profissional:** F18 `4cad35b` ("Compartilhar no extrato em PDF"), B7 `19c0ce7` e B9 `0b23fa1` (resumo de ganhos, "Sem taxa", CPF e serviços do período).
- ✅ **Perfil público sem login e sem comentário de avaliação:** B8 `1569e10` (`GET /v1/publico/profissionais/{id}`) e B10 `d2b2de9` (comentários somem até haver moderação).
- ✅ **Moedas/Tratinhos:** moeda própria, desconto, orçamento de desconto (R$ 300/mês, R$ 10/dia, R$ 5 por cliente/mês), reservas por cobrança, Pix com validade e bônus em 7 dias; migrations `20261118150000_moedas_gamificacao`, `20261119120000_moedas_desconto`, `20261120100000_moedas_orcamento` e `20261120200000_moedas_reservas` aplicadas (PROGRESSO 18 a 20/11). Ranking: `20261119140000_ranking_config` aplicada.
- ✅ **Bugs das rodadas QA3 a QA5:** todos corrigidos nos commits B12 `0beda5e`, B13 `c5f0b41`, B14 `27a5351`, F21 `6269a7b` a F24 `cdc7e28` e A4 `6163cbb` (PROGRESSO "2026-11-20/21 — Rodada QA3 a QA5"). **Estão só locais** (ver abaixo).
- ✅ **Ambiente:** `origin` ligado (`https://github.com/feitolabs/Trato.git`); GitHub CLI `gh` 2.103.3 instalado; `flutter` resolve em `C:lutterin` no PowerShell desta máquina (conferi em 20/11).

### ⏳ Abertas (decisão ou ação necessária)

- ⏳ **Código local sem push nem deploy:** `origin/develop` está em `3977e3d`; `develop` local tem 10 commits à frente (B12, B13, B14, F21 a F24, A4, correção da dica "Digite um número" e testes QA3/QA4). Backend no ar (v37) = B11, sem B12 a B14. Precisa de OK do João para push, deploy do backend no Fly e do painel na Vercel (e novo build do app, se for entregar F21 a F24).
- ⏳ **Agendador desligado no Fly (`TRATO_AGENDADOR_EMBUTIDO="false"`, `backend/fly.toml` linha 17):** sem ele as reservas de Tratinhos não expiram, os bônus de avaliação não são liberados, e também não rodam confirmação automática por prazo, expiração de pedido e de pagamento, lembretes, reenvio de notificações e exclusão LGPD. Hoje a decisão do João é manter desligado (informado pelo Mestre em 20/11). Como ligar: ver "Auditoria do app (15/11/2026)" abaixo.
- ⏳ **Contabilidade do desconto (cupom e Tratinhos):** como lançar no ledger/fechamento o desconto pago pela empresa (próxima rodada, PROGRESSO 20/11).
- ⏳ **Bônus em pedido estornado:** o que fazer com o bônus de avaliação quando o pedido é estornado (PROGRESSO 20/11).
- ⏳ **`UPDATE` da validade de 90 dias** dos Tratinhos (PROGRESSO 20/11): ajuste de dados pendente.
- ⏳ **Permissão própria do admin para a configuração de moedas** (hoje reaproveita outra permissão; PROGRESSO 20/11).
- ⏳ **Fallback do bônus com `Exception` genérica** (PROGRESSO 20/11): trocar por tratamento específico.
- ⏳ **Teste de concorrência em Postgres real:** o ramo `SELECT ... FOR UPDATE` do cupom nunca foi executado; as travas `RLock` valem só por processo, então vários workers precisam de trava no banco (PROGRESSO 20/11/21, limite 1). Também: 2 testes de concorrência de `test_qa3_backend.py` falharam uma vez na suíte completa sob carga e passam isolados (em verificação).
- ⏳ **Auditoria formal no webhook:** quando o limite por usuário do cupom estoura, só há `log.warning` (PROGRESSO 20/11/21, limite 2).
- ⏳ **R3 sem revisão da Seguranca:** Pix com validade e webhook tardio não foram revisados (decisão do João de seguir; PROGRESSO 20/11). A rodada da Seguranca sobre B12/B13 foi "aprovado com ressalvas" (SEG-1, SEG-2 e SEG-4 corrigidos na B14); a revalidação dos 4 testes após a B14 estava em andamento.
- ⏳ **Migration `20261118150000_remove_faixas_taxa.sql`:** preparada e **não aplicada** (destrutiva, apaga `config_faixas_taxa`; ordem segura: só depois de o backend novo estar no ar, o que já é verdade para a v37). Também falta zerar `taxa_bps` e `taxa_minima_centavos` na configuração (nova versão, dupla aprovação) e decidir se as colunas legadas de taxa saem do banco (PROGRESSO 18/11).
- ⏳ **Domínio `tratofeitolabs.com.br` (Registro.br):** sem DNS e sem versão web do app. Plano enviado ao Mestre em 20/11 (host recomendado: Cloudflare Pages). Depende do João: host, trocar os servidores de nome no Registro.br, rota pública nova no backend para o perfil, OK para CORS (`TRATO_SEG_CORS_ORIGENS`), URLs do Supabase Auth (Site e Redirect), `assetlinks.json` (SHA-256 do Android) e `apple-app-site-association` (conta Apple Developer).
- ⏳ **Licença do painel na Vercel:** `docs/hospedagem-fly-io.md` diz que o plano Hobby não vale para uso comercial; decidir entre Vercel Pro, Cloudflare Pages ou Netlify antes de operar com dinheiro real.
- ⏳ **Evento do Stripe e testes reais:** não há registro de que os eventos `charge.dispute.*`, `transfer.reversed` e `payout.failed` foram assinados no Stripe, nem de que `harness/teste_real_*.py` rodaram contra o ambiente real depois de 15/11. Conferir antes do piloto.
- ⏳ **Consultas novas do B9 sem tráfego autenticado:** as consultas do B9 (CPF próprio, portfólio, número do pedido) só foram testadas em memória; foi vigiado o log do Fly por ~3 min na v36 e na v37, sem erro, mas sem tráfego autenticado.

### Dúvidas desta atualização (sem evidência suficiente; deixei como estava)

- Estado real, no Supabase, das migrations antigas `20261029040000_notificacoes_dispositivos_agendador`, `20261030000000_fix_acesso_storage_pedido_historico`, `20261030120000_ordens_estorno` e `20261030140000_b2_grants_por_coluna`: os cabeçalhos dizem "NÃO APLICADA", mas o PROGRESSO de 31/10 diz que `ordens_estorno` "já foi aplicada". Só o banco responde.
- Respostas do João para P10 (fornecedor de verificação) e P16 a P19: nenhuma registrada nos arquivos que li.
- Se continua valendo "sem os 30% adiantados" (D16) no app atual; o RESUMO foi alinhado a D16, não conferi o código do pagamento.
- Contas duplicadas "João Vitor Cardoso" na equipe e dados de teste no banco (painel v2, 03/11): sem registro de limpeza.
- Google e Apple no Supabase (desligados em 15/11), push (Firebase), chamado de suporte no app, ausência do cliente, preferências de notificação e remarcar visita: sem registro de mudança depois de 15/11.
- Se a Vercel tinha outro deploy do painel às 18:00 de 20/11 (feito por outra pessoa ou agente, versão antiga); o deploy vigente é o das ~18:03 com `5dbc8c1`.

## Respondidas (decisão D16, 30/10/2026, em `DECISOES.md`)

Atualizado em 04/11/2026. A tabela abaixo mantém o histórico das dúvidas; estas já têm resposta:

- **P1:** 48 h para o cliente confirmar + 7 dias de janela de reclamação, como prazos separados.
- **P3, P4, P5, P8, P9:** como na V2 (sem taxa surpresa ao cliente; sem os 30% adiantados; taxa real nas telas; sem garantia financiada; painel web).
- **P6 e P15 (cidade):** Belo Horizonte/MG; categorias Limpeza residencial, Montagem de móveis e Pintura de interiores.
- **P7:** Stripe, caminho A (ledger espelho).
- **P11:** sem SMS no piloto (login por e-mail, Google e Apple).
- **P12 a P14:** seguem as recomendações de `docs/fidelidade-visual.md`.
- **P2:** regra única e transparente no piloto; **o valor ainda estava a fechar** (aberto até o João informar o número). ✅ Superada em 18/11/2026: o app ficou gratuito (sem taxa).
- **Ainda abertas:** P10 (fornecedor de verificação), P16 a P19 (sem resposta registrada nos arquivos; conferido de novo em 20/11/2026).

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

> 20/11/2026: o estado de aplicação destas migrations no Supabase **não está confirmado** nos arquivos (cabeçalhos dizem NÃO APLICADA; o PROGRESSO de 31/10 diz que `ordens_estorno` já foi aplicada). Conferir no banco antes de agir. A revisão da Seguranca de 20/11 (B12/B13) está resumida em "Estado em 20/11/2026".

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

- ✅ (20/11) `flutter` já resolve em `C:\flutter\bin` no PowerShell desta máquina. Texto original: Flutter 3.47.8 instalado em `C:\flutter`, mas **fora do PATH** (o `verificar` acha sozinho).
  Para usar no terminal: adicionar `C:\flutter\bin` ao PATH do usuário.
- Android Studio e SDK instalados; emulador `Medium_Phone_API_37.0` ok. **Falta:** "Android SDK Command-line Tools" e `flutter doctor --android-licenses` (o João aceita). O primeiro build baixou NDK 28.2 e Platform 36 sozinho (~10 min).
- **iOS:** build e simulador só em macOS com Xcode. Definir um Mac (ou CI na nuvem, ex.: Codemagic) antes da Fase 9.
- GitHub CLI (`gh` 2.103.3) está instalado (20/11). Supabase CLI não foi encontrado no PATH do Git Bash (opcional).
- ✅ Repositório GitHub ligado: `origin` = `https://github.com/feitolabs/Trato.git` (PROGRESSO 29/10; `git remote -v` em 20/11).

## Painel admin v2 (03/11/2026)

> 20/11/2026: a decisão 1 (tabela de taxas) e as respostas do Emanuel sobre faixas de taxa ficaram **sem efeito** (app gratuito desde 18/11). O "quem paga o cupom" segue como o Trato (desconto pago pela empresa); falta só a contabilidade (ver Estado em 20/11/2026).

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
- ✅ RESOLVIDO em 20/11 (backend no Fly, release v37; painel na Vercel). Texto original: **Publicar o backend e o painel da Operação** (filas paginadas, assumir, atualização automática). A migration
  `disputas_responsavel` já está no Supabase (08/11). Precisa de OK ou de o João publicar no Render.
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
- ⏳ Segue aberto em 20/11 (nenhuma ocorrência de `raio_atendimento` no backend nem nas migrations). Raio de atendimento ("Até onde você vai"): a tela coleta, mas o app não envia e o backend não guarda (`CadastroIn` não tem o campo). Decidir: gravar o raio (coluna + filtro de pedidos por distância, RN-01) ou tirar a pergunta da tela.

## Financeiro do painel (08/11/2026)
- Migration `20261108120000_financeiro_contestacoes_fechamento.sql` **aplicada no Supabase em 08/11/2026** (OK do João).
  ✅ (20/11: o backend foi publicado no Fly, não mais no Render.) Texto original: Falta publicar o backend novo no Render (passo a passo enviado ao João). Antes da aplicação valia:
  Sem ela, em produção: contestações não são gravadas (o webhook de contestação falha e o Stripe reenvia),
  "Fechamento do mês" responde erro e a trava do mês não existe. Rollback em `supabase/rollback/`.
  **Ordem obrigatória: aplicar a migration ANTES de publicar este backend.** O aviso de liquidação
  (`payout.paid`) passou a consultar `contestacoes`; sem a tabela, ele falha e o repasse não é espelhado.
- Assinar no Stripe os eventos novos do webhook: `charge.dispute.created`, `charge.dispute.updated`,
  `charge.dispute.closed`, `transfer.reversed`, `payout.failed`. Sem isso eles nunca chegam.
- Conciliação do dia testada só com extrato simulado; falta rodar contra o Stripe de teste e agendar a conferência
  diária (hoje é sob demanda, na aba).
- Fechamento sem o custo de cupom: o pedido não guarda o desconto (quem paga já foi decidido: o Trato).
- ✅ RESOLVIDO: F18 `4cad35b` ("Compartilhar no extrato em PDF" no app). Texto original: Extrato em PDF só pelo painel; o app do profissional ainda não tem o botão.
- Prazo do alerta de pagamento parado: 30 min até alguém propor e aprovar `alerta_pagamento_parado_minutos`.

## Auditoria do app (15/11/2026)

Detalhe em `harness/AUDITORIA-APP.md`.

- ⏳ Em 20/11 segue desligado (`backend/fly.toml` linha 17; ver "Estado em 20/11/2026"). **Ligar o agendador (decisão do João: ainda não).** Código pronto e testado. Para ligar: trocar
  `TRATO_AGENDADOR_EMBUTIDO` para `"true"` em `backend/fly.toml` (ou `fly secrets set TRATO_AGENDADOR_EMBUTIDO=true`),
  fazer o deploy e conferir que `select count(*) from agendador_execucoes` cresce a cada minuto; vigiar a memória
  (512 MB). **Enquanto estiver desligado não acontecem:** confirmação automática por prazo, expiração de pedido e de
  pagamento, lembretes, reenvio de notificações e processamento de exclusão LGPD. Não dá para piloto com dinheiro real
  sem isso. Alternativa se a memória apertar: segundo processo `python -m trato.agendador`.
- Cadastrar `STRIPE_PUBLISHABLE_KEY` (e, se usar Google, `GOOGLE_WEB_CLIENT_ID` e `GOOGLE_IOS_CLIENT_ID`) em Settings > Variables do GitHub. Sem a Stripe, o cartão não abre nos builds do CI.
- Push: precisa de projeto Firebase, arquivos de configuração, chave do FCM/APNs no servidor e OK.
- Chamado de suporte dentro do app: precisa de tabela nova (migration, com OK). Hoje: `TRATO_SUPORTE_EMAIL` (vazio, então o botão não aparece).
- Ausência do cliente: a máquina de estados só tem ausência do profissional (feita pelo sistema). Definir a regra.
- Google e Apple: ligar no Supabase (hoje desligados) e passar os client ids.
- Preferências de notificação (o backend tem a rota; o app não tem a tela). Remarcar visita (o servidor responde 501).
- Dados fixos no app: faixas de preço e prazos do Novo pedido; quadrinhos "Trabalho 1/2/3" do perfil sem portfólio. 🔶 20/11: B9 `0b23fa1` trouxe o portfólio ao perfil público, mas ainda há 2 ocorrências de "Trabalho N" em `app/lib`; confirmar.

