# Progresso

Diário do projeto. Uma entrada por sessão, mais recente no fim.

## 28/10/2026 — Fase 0 e início da Fase 1

**Feito**
- Gitflow montado: `main` (commit inicial com documentos), `develop`, features por fase.
- Fase 0: `CLAUDE.md`, `harness/RESUMO.md`, `DECISOES.md`, `PENDENCIAS.md`, `TAREFAS.md`, `verificar.py` (+ `.ps1`/`.sh`).
- Fase 1 (parte que não precisa de OK): pastas, `.env.example`, `.gitattributes`, backend FastAPI com `/saude` e teste, esqueleto do app Flutter (`pubspec.yaml`, `lib/main.dart`, teste).

**Falhou / bloqueado**
- Flutter SDK não instalado: não deu para gerar `android/` e `ios/` nem rodar `flutter analyze`/`test`.

**Pendente**
- João aprovar `TAREFAS.md` (F0.6).
- Responder `PENDENCIAS.md` P1–P4 antes da Fase 4 (dinheiro).
- 🔒 Conectar Supabase (leitura) e GitHub (push).

**Próxima tarefa:** F1.5 (instalar Flutter e gerar plataformas) ou F2.1 (tokens de design).

## 28/10/2026 — F1.5 plataformas Flutter

**Feito**
- João aprovou o `TAREFAS.md` e instalou o Flutter (3.47.8, `C:\flutter`).
- `flutter create` gerou `android/` e `ios/` (org `br.com.feitolabs`). Nome no Android ajustado para "Trato".
- `verificar.py` acha o Flutter fora do PATH. Verificação completa: TUDO OK (backend 3 testes, `flutter analyze` sem problemas, `flutter test` 1 teste).

**Pendente**
- Android SDK (emulador) e Mac para iOS — ver PENDENCIAS.

**Próxima tarefa:** F2.1 (tokens de design do protótipo).

## 28/10/2026 — F2.1 e F2.2 tema do protótipo

**Feito**
- Cores medidas nos pixels do PDF de telas (o PDF é imagem + OCR) → `docs/design-tokens.md`.
- Tema Flutter em `app/lib/tema/` (cores, tipografia, espaços, ThemeData). Fontes Archivo e Figtree (OFL) embutidas em `app/assets/fontes/`.
- Splash provisória com o tema; golden tests em 3 tamanhos (320, 390, 768 de largura).
- `verificar` agora falha se houver cor solta fora de `lib/tema/`. Verificação: TUDO OK (8 testes no app, 3 no backend).

**Riscos**
- Goldens gerados no Windows: podem dar diferença de pixel em macOS/Linux. Gerar no CI quando existir.
- Fontes a confirmar (P12).

**Próxima tarefa:** F2.3 (componentes: botão, campo, cartão, chip, linha do tempo, barra de abas).

## 28/10/2026 — Android rodando

**Feito**
- João instalou o Android Studio. SDK em `%LOCALAPPDATA%\Android\Sdk`, emulador `Medium_Phone_API_37.0`.
- `flutter build apk --debug` ok (primeiro build ~10 min: Gradle 9.3.1, NDK 28.2 e Platform 36 baixados automaticamente).
- APK instalado e aberto no emulador: splash igual ao protótipo e ao golden.

**Pendente**
- Command-line Tools + licenças (João). iOS precisa de Mac.

**Próxima tarefa:** F2.3 (componentes).
