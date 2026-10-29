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
