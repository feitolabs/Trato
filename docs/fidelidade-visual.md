# Fidelidade visual — app × protótipo

Comparação de cada tela do app com a página do `Trato — Telas do app.pdf` (27 páginas, 390 dp de largura).
Pares lado a lado (esquerda = PDF, direita = app) em [`docs/fidelidade/`](fidelidade/).
Como foi feito: páginas do PDF renderizadas a 390 dp; telas do app capturadas pelos testes de golden em 390 dp,
com altura suficiente para a tela inteira; tamanhos de fonte do PDF estimados pela largura do texto (camada de OCR)
contra a fonte Figtree. Barra de status do aparelho e dados de exemplo do PDF (nome preenchido etc.) não contam como diferença.

## Correções globais (valem para várias telas)

| Diferença medida | Antes | Depois (PDF) | Onde |
|---|---|---|---|
| Margem lateral das telas do app | 20 | **16** (24 no onboarding, escolha de perfil e telas de login/cadastro) | `Responsivo.margemLateral`, `ConteudoResponsivo(margem:)` |
| Padding interno de cartão | 20 | **16** | `CartaoTrato`, resumo do orçamento |
| Contorno de campos e botões secundários | `#D8CFBE`, 1 dp | **`#A3ABA3`, 1,5 dp** (cartões seguem `#D8CFBE`) | `CoresTrato.bordaControle`, `TemaTrato` |
| Altura de campo de texto | 56 | **52** | `inputDecorationTheme` |
| Texto corrido em 17 dp (`corpoGrande`) | 17 | **16** (17 só no onboarding) | 10 telas |
| Título de cartão | 17 | **16 / 700** | `tituloCartao` |
| Legenda (dica sob o campo) | 13 | **14** | `legenda` |
| Chip de status | 14 | **13 / 700** | `ChipStatus` |
| Linha de lista no perfil | 57 | **52** (padding lateral 16) | Perfil do cliente |

Os tokens em `docs/design-tokens.md` foram corrigidos (margem 16, contorno de controle, padding de cartão).

## Tabela por página

Legenda: ✅ corrigido · ➖ não corrigido (motivo).

| PDF | Tela do app | Diferenças encontradas | Situação |
|---|---|---|---|
| 1 Splash | `splash_tela` | Lema "Serviço feito, dinheiro liberado." × app "Serviço combinado, tudo no app." (D13); logo e pontos iguais | ➖ texto fica neutro (D13) |
| 2 Onboarding 1/3 | `onboarding_tela` | Margem 24 ✅; ícone da ilustração (Material × Lucide); páginas 2 e 3 não existem no PDF | ✅ margem; ➖ ícone (P13), textos (P14) |
| 3 Escolha de perfil | `escolha_perfil_tela` | Margem 24 ✅; texto "pague com o valor retido até a conclusão" × "acompanhe o pagamento pelo app" (D13); ícones | ✅; ➖ texto (D13), ícones (P13) |
| 4 Login | `login_tela` | Margem 24 ✅; borda dos campos ✅; botão "Entrar com Apple" só aparece em iOS com o provedor ligado (decisão D14); ícone de biometria | ✅; ➖ Apple (intencional) |
| 5 Criar conta | `criar_conta_tela` | Margem 24, campo 52, borda ✅; legenda 14 ✅; caixa de seleção sem rótulo para leitor de tela (ver acessibilidade) | ✅ |
| 6 Confirmar celular | `confirmar_celular_tela` | Corpo 16 ✅; margem ✅ | ✅ |
| 7 Recuperar senha | `recuperar_senha_tela` | Corpo 16 ✅; margem ✅ | ✅ |
| 8 Início do cliente | `cliente/inicio_tela` | Margem 16, padding de cartão, corpo 16, chip 13 ✅; texto do cartão "pagamento fica retido até a conclusão" × "processado por parceiro" (D13); ícones | ✅; ➖ texto (D13), ícones (P13) |
| 9 Buscar (resultados) | `comuns/busca` | Margem e cartões ✅; "resp. em 1 h" quebra linha em coluna estreita (igual ao PDF) | ✅ |
| 10 Perfil do profissional | `cliente/perfil_profissional_tela` | Corpo 16, margem ✅; ícone de verificação (Material × Lucide) | ✅; ➖ ícone (P13) |
| 11 Novo pedido (passo 2) | `pedido_novo/novo_pedido_tela` | Margem, campos, corpo 16 ✅; chips quebram em 3 linhas no app (PDF: 2) por largura dos chips | ✅ parcial; ➖ quebra de chips é conteúdo/largura |
| 12 Orçamentos recebidos | `orcamentos_recebidos_tela` | Margem, padding, corpo ✅ | ✅ |
| 13 Detalhe do orçamento | `detalhe_orcamento_tela` | Padding ✅; texto 16 ✅ | ✅ |
| 14 Pagamento | `pagamento_tela` | "Seu dinheiro fica protegido / retido" × "Como funciona o pagamento" (D13); corpo 16 ✅ | ✅; ➖ texto (D13) |
| 15 Seus pedidos | `pedidos/seus_pedidos_tela` | Chips 13 ✅; "pagamento retido" × "pagamento acompanhado"; "valor congelado" × "em análise" (D13) | ✅; ➖ textos (D13) |
| 16 Serviço em execução | `pedido_execucao_tela` | SOS ausente de propósito (SOS fora do MVP, D13); "Pagamento retido" × "acompanhado" (D13) | ✅; ➖ SOS e textos (D13) |
| 17 Chat | `chat_pedido_tela` | Margens/balões ✅ | ✅ |
| 18 Conclusão | `conclusao_tela` | "Total retido" × "Total do serviço"; "Liberação automática" × "Confirmação automática" (D13) | ✅; ➖ textos (D13) |
| 19 Avaliação | `avaliacao_tela` | "Pagamento liberado" × "Aguardando confirmação do pagamento" (D13: nunca "pago" antes do provedor) | ➖ texto (D13) |
| 20 Relatar problema | `relatar_problema_tela` | "Valor congelado até a decisão" neutralizado (D13) | ➖ texto (D13) |
| 21 Garantia | `garantia_tela` | Texto de garantia reduzido a "suporte e análise de problemas" (D13) | ➖ texto (D13) |
| 22 Perfil do cliente | `perfil_cliente_tela` | Linha 52 dp, padding 16 ✅; logo "um app Feito Labs" maior no app; ícones | ✅; ➖ logo (pequeno), ícones (P13) |
| 23 Início do profissional | `inicio_profissional_tela` | Margem, cartões ✅; "Retido" × "Em andamento" (D13) | ✅; ➖ texto (D13) |
| 24 Detalhe do pedido (prof.) | `detalhe_pedido_tela` | Corpo 16, margem ✅; mapa/ícones | ✅ |
| 25 Calculadora | `calculadora_orcamento_tela` | Campos 52, borda ✅; "Taxa Trato (5%)" × texto neutro (P5/D13) | ✅; ➖ texto (D13/P5) |
| 26 Check-in | `check_in_tela` | Margens ✅ | ✅ |
| 27 Carteira | `carteira_tela` | "Retido/A liberar/Liberado" × "Em andamento/A confirmar/Confirmado" (D13/D15) | ✅; ➖ textos (D13/D15) |

## Tamanhos, fonte grande e acessibilidade

Conferido nos testes de golden existentes (celular pequeno 320, protótipo 390, tablet 768) e em uma execução
extra com fonte do sistema a 1,3 (limite do app): sem estouro de layout. Verificações automáticas do Flutter:
área de toque de 48 dp, rótulo semântico em elementos tocáveis e contraste mínimo. Resultado e correções na seção abaixo.

Resultado (3 tamanhos × todas as telas dos goldens, fonte 1,3):

- **Overflow:** nenhum. **Área de toque de 48 dp:** nenhuma falha.
- **Rótulo semântico:** corrigido nas 3 caixas de seleção (cadastro, aceite do orçamento, sinal do material) e nos cartões tocáveis (`CartaoTrato` agora junta o texto como rótulo do botão).
- **Contraste:** o verificador aponta rótulos da barra de abas, o "ou" do login, um chip de mensagem rápida e o chip de status. Em todos o retângulo medido inclui a pílula azul, o divisor ou a borda, e não só o texto; as cores de texto (petróleo, `textoSecundario`) têm contraste alto sobre o creme. Tratado como falso positivo, mas **não validado em aparelho**.
- Botões e campos principais já usam widgets do Material, que expõem `Semantics`.

## Depende do João (recomendação)

| Item | Situação | Recomendação |
|---|---|---|
| P12 Fontes | Archivo (títulos) e Figtree (corpo), deduzidas pelo desenho; os tamanhos medidos batem com as fontes | Confirmar com quem fez o protótipo; manter Archivo + Figtree (gratuitas, licença OFL) |
| P13 Ícones | App usa Material Outlined; protótipo usa traço fino tipo Lucide (diferença visível em categorias, abas, verificação) | Trocar por Lucide (pacote `lucide_icons`) numa tarefa própria; é a maior diferença visual que sobra |
| P14 Textos do onboarding 2 e 3 | PDF só mostra a página 1; as outras foram escritas por nós sem promessas proibidas | Aprovar o texto atual ou mandar o final; manter neutro (D13) |
