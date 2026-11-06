# Tema do painel (design system próprio)

O painel segue o **"Trato · Design system do painel admin" (v2, 02/11/2026)** e o documento
**"Design System e Requisitos do Painel Admin (v2)"**. Por isso estes arquivos **não são mais cópia**
de `app/lib/tema/`: o app e o painel têm tokens diferentes (o app foi medido no protótipo do
cliente; o painel, nas 24 capturas do painel).

- `cores.dart` — tokens `color.*` do PDF (seção 3.1) e as cores de status (sucesso, aviso, perigo,
  info, neutro). Os nomes antigos (`petroleo`, `creme`, `azulSuave`…) continuam, apontando para os tokens.
- `tipografia.dart` — níveis `--trato-type-*`: Bricolage Grotesque 800 (títulos e números) e
  Hanken Grotesk (interface). Nada abaixo de 12 px; valores em R$ com numerais tabulares.
- `espacos.dart` — escala de 4 px, raios (12 campos/botões/cards, 24 modal), 44 px de toque.
- `responsivo.dart` — três faixas (RNF-01): ≥1024 menu fixo, 768–1023 menu só com ícones, <768 barra inferior.
- `tema.dart` — `ThemeData` montado só com os tokens (botões 44 px, anel de foco de 2 px).
- Fontes: `admin/assets/fontes/` (Bricolage e Hanken, licença OFL junto dos arquivos).
- Cor só aqui. Fora de `lib/tema/`, `harness/verificar.py` recusa `Color(0x...)` e `Colors.*`.
- Tema escuro: os tokens `--trato-*` do PDF trazem o escuro, mas os valores não vieram nas telas
  de referência. Fica em `harness/PENDENCIAS.md`.
