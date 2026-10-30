# Entrega do Trato

Visão de quem recebe o projeto: o que está pronto, como rodar, como provar que funciona, o que falta e o que **só o João** pode fazer. Detalhes de cada tela ficam em `docs/STATUS-MVP.md`; comandos em `docs/COMO-RODAR.md`; build de celular em `docs/BUILD.md`.

## 1. Resumo do que existe

| Parte | Onde | Estado |
|---|---|---|
| Backend Python (FastAPI): regras de pedido, taxa, ledger, disputa, garantia, pagamento em teste | `backend/` | Pronto e testado (~490 testes). Memória por padrão; Postgres com `TRATO_PERSISTENCIA=postgres` |
| App Flutter (Android e iOS), modos `demo` e `api` | `app/` | Telas de cliente e profissional prontas; parte ainda em demo (ver `STATUS-MVP.md`) |
| Banco Supabase "Trato" | `supabase/` | Migrations aplicadas; **faltam seeds** |
| Painel administrativo (web) | em desenvolvimento em outra frente | **Ainda não está neste repositório**; não consta nos comandos abaixo |
| Verificador e CI | `harness/verificar.py`, `.github/workflows/` | Pronto; o CI nunca rodou na nuvem (nunca houve push com ele) |

## 2. Como rodar (resumo)

Tudo em `docs/COMO-RODAR.md`. Em uma máquina nova:

```bash
# 1. Backend: cria backend/.venv e instala (ruff, pytest etc. vêm no extra "dev")
.\harness\preparar-ambiente.ps1        # Windows
./harness/preparar-ambiente.sh         # macOS / Linux / Git Bash

# 2. Provar que está tudo certo
python harness/verificar.py
```

Se faltar `ruff`/`pytest`/dependências, o verificador diz o que falta e qual script rodar. Flutter é procurado no PATH, em `$FLUTTER_ROOT` e em `C:\flutter`; sem ele, as etapas do app são puladas com aviso.

| Quero | Comando |
|---|---|
| API local | `backend/.venv/Scripts/python -m uvicorn trato.main:app --reload` (em `backend/`) e abrir `/saude` |
| App em demo | `flutter run` (em `app/`) |
| App na API local | `flutter run --dart-define=TRATO_MODO=api --dart-define=TRATO_API_URL=http://10.0.2.2:8000` (10.0.2.2 = o PC visto do emulador Android) |
| Só uma etapa do verificador | `python harness/verificar.py --etapa segredos`, `backend` ou `app` |
| Painel admin | Ainda não disponível aqui |

## 3. Variáveis de ambiente

Modelo em `.env.example` (só nomes). O `.env` real fica na raiz, **fora do git**. Nenhuma é necessária para rodar os testes.

| Grupo | Variáveis | Quem usa |
|---|---|---|
| Ambiente | `TRATO_AMBIENTE` | backend |
| Supabase | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, `DATABASE_URL`, `SUPABASE_JWT_SECRET` ou `SUPABASE_JWKS_URL` | backend (a URL e a anon também vão ao app via `--dart-define`) |
| Persistência | `TRATO_PERSISTENCIA` (`memoria` ou `postgres`), `TRATO_BANCO_PAPEL`, `TRATO_CODIGO_SEGREDO` | backend |
| Stripe (teste) | `STRIPE_SECRET_KEY` (`sk_test_`), `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET` | backend |
| Login | `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` | app (`--dart-define`) |
| App | `TRATO_MODO`, `TRATO_API_URL` | app (`--dart-define`; **não** lê `.env`) |
| Servidor | `BACKEND_HOST`, `BACKEND_PORT` | backend |

Regra: segredo nunca vai para o app (qualquer valor de `--dart-define` pode ser extraído do APK).

## 4. Integração contínua (GitHub Actions)

Arquivos: `.github/workflows/verificar.yml` (a cada push/PR) e `.github/workflows/build.yml` (manual).

| Job | O que faz | Roda quando |
|---|---|---|
| `segredos` | Busca de segredos e `.env` ignorado | sempre |
| `backend` | venv + `pip install -e "backend[dev]"`, ruff, pytest | sempre |
| `app` | Flutter 3.47.8, cores fora do tema, textos proibidos (D13), `analyze`, `test` | sempre |
| `integracao` | Testes de integração com Postgres embutido (`pgserver`, migrations reais, banco descartável) | push em `develop`/`main` ou manual |
| `build.yml` / Android | APK debug como artefato | só manual |
| `build.yml` / iOS | Compila sem assinar (prova de compilação, sem IPA) | só manual |

Detalhes:
- Ações fixadas por SHA de commit (tag no comentário). Cache de pip e de pub/Flutter ligados.
- **Nenhum segredo no workflow.** `build.yml` lê pelo nome: `vars.TRATO_API_URL`, `secrets.SUPABASE_URL`, `secrets.SUPABASE_ANON_KEY` (opcionais; sem eles compila em demo). Cadastro: GitHub > Settings > Secrets and variables > Actions.
- A versão do Flutter (`FLUTTER_VERSION: "3.47.8"`) tem de ser a mesma instalada em `C:\flutter`. Ao atualizar o Flutter local, atualize os dois arquivos.
- O job de integração **não usa** `services: postgres`: a suíte já sobe seu próprio Postgres pelo pacote `pgserver`. Não toca no Supabase.
- Validação feita sem a nuvem: `actionlint` limpo nos dois arquivos, e os mesmos comandos de cada job rodados localmente (ver `harness/PROGRESSO.md`). **O primeiro run real só acontece depois do push, com o OK do João.** Pode revelar diferenças de Ubuntu (por exemplo caminho de fonte nos goldens do Flutter); se acontecer, o ajuste é pontual.

## 5. Checklist de entrega

Feito (por arquivos, verificado localmente):
- [x] `python harness/verificar.py` passa (segredos, ruff, pytest, analyze, test).
- [x] Ambiente de uma máquina nova: `harness/preparar-ambiente.ps1` / `.sh`, `backend/requirements*.txt`, extra `dev` no `pyproject.toml`; o verificador acha `backend/.venv` (ou `.venv` da raiz, ou `$TRATO_PYTHON`) e avisa o que falta.
- [x] Workflows revisados (jobs separados, versões fixas, cache).
- [x] `docs/BUILD.md`: Android debug/release, assinatura, iOS na nuvem, `--dart-define`.
- [x] Android/iOS: `br.com.feitolabs.trato`, nome "Trato", `INTERNET` no release, permissões de câmera e localização, assinatura de release lida de `key.properties` (ignorado pelo git).
- [x] `.gitignore` cobre `.env*`, `key.properties`, `*.jks`, `*.keystore`, `*.p12`, `*.mobileprovision`, `dart-defines*.json`.

Falta (técnico, sem depender do João): ver "Próximos passos técnicos" em `docs/STATUS-MVP.md` (token do login na API, rotas que faltam, câmera/GPS, painel admin).

## 6. O que depende do João

Tudo marcado 🔒 precisa do OK dele; nada disso foi feito.

| Item | O que fazer |
|---|---|
| Push e Actions | Autorizar o push das branches e conferir o primeiro run do CI; cadastrar `vars.TRATO_API_URL`, `secrets.SUPABASE_URL`, `secrets.SUPABASE_ANON_KEY` se quiser build com API |
| Keystore Android | Gerar a keystore, criar `app/android/key.properties`, guardar cópia segura (`docs/BUILD.md` seção 2) |
| Conta Google Play | Conta de desenvolvedor, app criado, política de privacidade pública |
| Apple | Conta Apple Developer, Bundle ID, app no App Store Connect, chave da API; escolher Codemagic ou Actions (`docs/BUILD.md` seção 3) |
| Ícone final | Arte 1024×1024 do design (hoje o ícone é o padrão do Flutter) |
| Supabase | Chaves no `.env`; autorizar seeds (cidade, categorias, taxa, contas do ledger) |
| Pagamento | Escolha do parceiro, propostas de 2 provedores, chaves Stripe de teste, segredo do webhook (P2, P3, P7, P16) |
| Login | Credenciais Google e Apple, provedor de SMS (`docs/login-configuracao.md`, P11) |
| Jurídico | Prazos de liberação e disputa, termos, política de privacidade, SAC (P1, P17, P18) |
| Piloto | Cidade e categorias (P15); `v1.0.0`: merge em `main`, tag e push (F9.6) |
| Hospedagem do backend | Onde a API roda em produção (não definido; nada foi contratado) |

Lista completa de perguntas abertas: `harness/PENDENCIAS.md`.
