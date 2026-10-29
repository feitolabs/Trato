# Como rodar o Trato

Só o que existe e funciona hoje. Os comandos foram conferidos nos arquivos do repositório
(`backend/README.md`, `app/README.md`, `backend/pyproject.toml`, `harness/verificar.py`).
Tudo abaixo roda na máquina local. **Nada aqui escreve no Supabase nem chama Stripe real.**

## Pré-requisitos (Windows)

| Ferramenta | Versão / local |
|---|---|
| Python | 3.11 (`py -3.11`) |
| Flutter | instalado em `C:\flutter` (fora do PATH; o `verificar` acha sozinho) |
| Android Studio + SDK | emulador `Medium_Phone_API_37.0` |
| Git | Gitflow (seção final) |

iOS: build e simulador só em macOS com Xcode. Ainda não definido (ver `harness/PENDENCIAS.md`).

Para usar o Flutter no terminal, adicione `C:\flutter\bin` ao PATH do usuário, ou chame `C:\flutter\bin\flutter.bat`.

## 1. Variáveis de ambiente

Copie o modelo e preencha. **Nunca** versione o `.env` (o `.gitignore` já ignora).

```bash
cp .env.example .env
```

O `.env.example` só tem nomes. Chaves reais do Supabase e do Stripe (modo teste) são colocadas pelo João. Para rodar os testes de hoje não é preciso preencher nada.

## 2. Backend (Python 3.11 + FastAPI)

```bash
cd backend
py -3.11 -m venv .venv
.venv/Scripts/python -m pip install -e ".[dev]"
```

Subir a API e abrir http://127.0.0.1:8000/saude:

```bash
.venv/Scripts/python -m uvicorn trato.main:app --reload
```

Testes, lint e formatação (as mesmas etapas que o verificador roda):

```bash
.venv/Scripts/python -m pytest -q
```

```bash
.venv/Scripts/python -m ruff check .
```

```bash
.venv/Scripts/python -m ruff format --check .
```

Em macOS/Linux troque `.venv/Scripts/python` por `.venv/bin/python`.

## 3. App (Flutter)

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

Se o `flutter` não estiver no PATH, use `C:\flutter\bin\flutter.bat` no lugar.

Rodar no emulador Android:

```bash
flutter emulators --launch Medium_Phone_API_37.0
```

```bash
flutter run
```

Abrir a **galeria de componentes** no lugar da splash:

```bash
flutter run --dart-define=GALERIA=true
```

O primeiro build baixa NDK e Platform do Android sozinho (~10 min). Falta aceitar as licenças do SDK uma vez (`flutter doctor --android-licenses`) e instalar o "Android SDK Command-line Tools".

Goldens (imagens de referência de tela): se mudar o visual de propósito, regenere e confira o `git diff` das imagens.

```bash
flutter test --update-goldens
```

Regras do app: nenhuma cor, fonte ou espaçamento solto (tudo vem de `app/lib/tema/`) e nenhuma regra de dinheiro no app.

## 4. Verificador (tudo de uma vez)

```bash
python harness/verificar.py
```

Roda, em ordem: busca de segredos, `.env` ignorado, cores fora do tema, ruff (lint e formatação) e pytest do backend, e `flutter pub get`, `analyze` e `test` do app. Termina com `TUDO OK` ou `VERIFICAÇÃO FALHOU`.

Atalhos: `.\harness\verificar.ps1` (Windows) e `./harness/verificar.sh` (macOS/Linux/Git Bash). Eles usam o python de `backend/.venv` quando existe.

Observações:
- O backend usa o `backend/.venv`. Em uma **worktree nova** o `.venv` não existe (ele não vai para o git); crie um (seção 2) ou rode o verificador com o python de outro `.venv`.
- Se o Flutter não for encontrado (PATH, `FLUTTER_ROOT` ou `C:\flutter`), as etapas do app são puladas com um aviso.
- Linha com `# verificar: ignorar` é ignorada pela busca de segredos (uso só para valores falsos de teste).

## 5. Gitflow do projeto

- `main`: versões liberadas, com tag `vX.Y.Z`. `develop`: integração.
- Cada tarefa em `feature/<fase>-<nome>`, criada a partir de `develop`; merge com `--no-ff`.
- Também existem `release/*` e `hotfix/*`.
- Commits em português, no estilo `tipo: descrição` (`feat`, `fix`, `chore`, `docs`, `test`, `refactor`).
- Ao fechar cada tarefa, rodar `python harness/verificar.py`; só marcar a tarefa pronta se passar.
- **Push, deploy e qualquer escrita no banco só com o OK do João.** O repositório "Trato" do GitHub ainda não está ligado como `origin`.

## 6. O que ainda não está aqui

Banco real (Supabase), Stripe, painel administrativo, build de loja e iOS ficam para as fases seguintes. Quando existirem, entram neste arquivo (e em `docs/ENTREGA.md`, F9.5).
