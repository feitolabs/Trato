# Tema do painel (cópia)

Estes arquivos são **cópia** de `app/lib/tema/` (cores, espaços, tipografia, responsivo e tema).
O painel é um projeto Flutter separado e, por enquanto, não depende do pacote do app.

- Fonte da verdade: `app/lib/tema/`. Mudou lá, copie para cá (o cabeçalho de cada arquivo avisa a origem).
- Fontes Archivo e Figtree: `admin/assets/fontes/` (cópia de `app/assets/fontes/`, licença OFL junto).
- Cor só aqui. Fora de `lib/tema/`, `harness/verificar.py` recusa `Color(0x...)` e `Colors.*`.
- Se o app e o painel passarem a divergir, o passo seguinte é extrair um pacote `trato_tema`.
