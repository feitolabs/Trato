# Tokens de design — Trato

Extraídos de `Trato — Telas do app.pdf` (27 telas). O PDF é imagem com OCR; as cores foram
medidas nos pixels (cor dominante de cada área, e pixel mais escuro para texto fino).
Código: `app/lib/tema/`. **Nenhuma cor, fonte ou espaçamento fora do tema.**

Escala: a tela do protótipo tem 292,5 pt de largura e corresponde a 390 dp (iPhone padrão).
1 pt do PDF ≈ 1,333 dp.

## Cores

| Token | Hex | Onde aparece |
|---|---|---|
| `petroleo` (primária) | `#0E3A43` | Splash, botões primários, títulos, texto principal, cartão "Descreva o problema", resumo da calculadora |
| `creme` (fundo) | `#F4EEE2` | Fundo de todas as telas; texto sobre petróleo |
| `superficie` | `#FBF8F1` | Cartões, campos, botões secundários, barra inferior |
| `borda` | `#D8CFBE` | Contorno de cartões e divisores |
| `bordaControle` | `#A3ABA3` | Contorno de campos e botões secundários (1,5 dp) |
| `azulClaro` | `#8FC1C8` | Ilustrações e espaços de foto |
| `azulSuave` | `#DCEBEE` | Fundo de chip informativo ("Em execução · pagamento retido"), aba ativa da barra, opção selecionada |
| `azulTexto` | `#0B6067` | Texto de chip informativo, links ("Pular", "Já tenho conta", "Adicionar item"), garantia ativa |
| `laranja` (destaque) | `#FF8A4C` | Ponto do logo, chip "3 orçamentos novos" |
| `ambarSuave` / `ambarTexto` | `#F8EBCB` / `#7C5100` | Aditivo aguardando, "Disputa aberta · valor congelado" |
| `verdeSuave` / `verdeTexto` | `#E3EFE5` / `#22683C` | Chip "Finalizado", sucesso |
| `vermelhoSuave` / `vermelhoTexto` | `#F8E0DC` / `#9C221B` | Botão SOS, erros |
| `textoSecundario` | `#485D5A` | Subtítulos, rótulos ("Olá, Mariana", "1 DE 3", "Buscar"), descrições |
| `textoDica` | `#6B6A68` | Placeholder dos campos |
| `logoAzul` / `logoAzulClaro` | `#60B3C3` / `#A8D3DA` | Só no logo Feito Labs |

## Tipografia

| Estilo | Fonte | Tamanho / peso | Exemplo |
|---|---|---|---|
| `marca` | Archivo | 72 / 900 | "Trato" na splash |
| `lema` | Figtree | 18 / 400 | "Serviço feito, dinheiro liberado." |
| `tituloGrande` | Archivo | 28 / 800, altura 1,15 | "Descreva o problema, receba orçamentos", "Seus pedidos" |
| `titulo` | Archivo | 22 / 800 | "Categorias", "Linha do tempo", "Material" |
| `tituloCartao` | Figtree | 16 / 700 | "Troca de tomadas e chuveiro" |
| `corpo` | Figtree | 16 / 400, altura 1,5 | Textos e campos |
| `corpoForte` | Figtree | 16 / 700 | Botões, rótulos de campo |
| `corpoPequeno` | Figtree | 14 / 400 | Descrições de cartão, chips |
| `legenda` | Figtree | 14 / 400 | Dicas abaixo dos campos |
| `sobretitulo` | Figtree | 13 / 700, espaçamento 1,5, maiúsculas | "1 DE 3", "FEITO LABS APRESENTA" |

> **A confirmar com o João (P12):** as fontes foram identificadas pelo desenho das letras
> (o PDF não traz o nome). Se o protótipo usou outras fontes, é só trocar os arquivos em
> `app/assets/fontes/` e os nomes em `tipografia.dart`.

## Espaços, raios e tamanhos (dp)

| Token | Valor | Uso |
|---|---|---|
| `margemTela` | 16 | Margem lateral das telas do app (24 no onboarding, escolha de perfil e login/cadastro; medido no PDF) |
| `espaco` | 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48 | Escala de espaçamento |
| `raioPequeno` | 8 | Chips |
| `raio` | 12 | Botões, campos, cartões de categoria |
| `raioGrande` | 16 | Cartões, ilustração do onboarding |
| `raioPilula` | 999 | Botão SOS, indicador da aba ativa |
| `alturaBotao` | 52 | Botões primário e secundário |
| `alturaCampo` | 52 | Campos de texto |
| `bordaFina` | 1 | Contornos |

## Componentes observados (para a F2.3)

- **Botão primário:** fundo petróleo, texto creme, Figtree 16/700, raio 12, altura 52, largura total.
- **Botão secundário:** fundo superfície, borda `borda`, texto petróleo.
- **Link:** `azulTexto`, sublinhado, Figtree 16/700.
- **Campo:** fundo superfície, borda `borda`, raio 12, rótulo acima (Figtree 16/700).
- **Cartão:** fundo superfície, borda `borda`, raio 16, padding 16.
- **Chip de status:** fundo suave + texto forte da mesma família (azul, âmbar, verde, vermelho, laranja), raio 8, Figtree 14/700.
- **Linha do tempo:** círculo petróleo com ✓ (feito), círculo azul suave com borda (atual), círculo vazio (futuro), linha cinza ligando.
- **Barra inferior:** 5 abas, ícone e rótulo; ativa com pílula `azulSuave` atrás do ícone e rótulo em negrito.

## Responsividade (F2.4)

Código: `app/lib/tema/responsivo.dart`.

| Faixa | Largura | Margem lateral | Exemplo |
|---|---|---|---|
| `pequeno` | < 360 dp | 16 | iPhone SE 1ª geração, Androids compactos |
| `celular` | 360–599 dp | 20 | Protótipo (390), maioria dos celulares |
| `tablet` | ≥ 600 dp | 32 | Tablets, dobráveis abertos |

- **Tablet:** o conteúdo fica centralizado com no máximo **560 dp** de largura (`ConteudoResponsivo`), para manter a leitura no tamanho do protótipo.
- **Fonte do sistema:** respeitada de **0,9 a 1,3** (`EscalaFonteLimitada`). Acima disso o layout quebra; o limite é aplicado no `MaterialApp.builder`.
- **Barra de abas:** fica em escala 1,0 (como as barras nativas) e o rótulo encolhe se faltar espaço.
- **Botões e rótulos de campo:** sempre em uma linha; encolhem em vez de quebrar a palavra.
- **Testes:** `test/responsivo_test.dart` abre a splash e a galeria em 320, 390, 430, 768 e 1280 de largura, com fonte 1,0 e 1,3; qualquer estouro de layout falha. Goldens em `test/golden/`.

## Splash, onboarding e escolha de perfil (F2.5)

- **Logo Feito Labs** (`LogoFeitoLabs`): grade 3x3 de peças de 113 com vão de 18 (proporção medida na splash), desenhada em código. Cores: creme, `logoAzul`, `logoAzulClaro` e círculo `laranja`.
- **Splash:** logo (72 dp) + "FEITO LABS APRESENTA" (sobretítulo creme) no topo; "Trato" 72 + lema no centro; 3 pontos (ativo creme, inativos `pontoSobrePetroleo` `#2A5A64`) e "Toque para começar" (`azulClaro`) embaixo.
- **Onboarding:** marca "Trato" 24/800 e link "Pular" no topo; ilustração `azulClaro` com raio 16 e 260 de altura; "1 DE 3"; título 28/800; texto 17 (`corpoGrande`); indicador em pílula (28x10 ativo, 10x10 inativo); botão "Próximo" e link "Já tenho conta".
- **Escolha de perfil:** duas opções em cartão com ícone em quadrado 64 `azulClaro`; selecionada = fundo `azulSuave` e borda petróleo 1,5; o botão de baixo muda ("Criar conta de cliente" / "de profissional").

> Revisão de fidelidade (30/10/2026): margem, padding de cartão, contorno de controles e tamanhos de texto foram remedidos; ver `docs/fidelidade-visual.md`.
