# trato_web

Site web do Trato (cliente e profissional), em Flutter Web.

## Configuração

Entra na compilação por `--dart-define`. Só valores **públicos**: tudo vai para o JavaScript.

| Nome | O que é |
|---|---|
| `TRATO_API_URL` | Endereço do backend (`https`) |
| `SUPABASE_URL` | URL do projeto Supabase |
| `SUPABASE_ANON_KEY` | Chave pública (anon/publishable). Nunca a `service_role` |

Copie `dart-defines.example.json` para `dart-defines.json` (ignorado pelo git) e preencha.
Não use o `.env` da raiz: ele tem segredos.

Sem esses valores o site abre só a tela "Site sem configuração".

## Rodar

```
flutter run -d chrome --dart-define-from-file=dart-defines.json
```

## Compilar para publicar

```
python tool/build_web.py
```

Lê as variáveis de ambiente ou o `dart-defines.json` (aceita outro arquivo como argumento),
falha se faltar valor e grava `build/web/trato-config.sha256`.

A Vercel não compila: publica o `build/web` da máquina. O `buildCommand` do `vercel.json`
confere o selo e **derruba o deploy** se o build não veio desse script. Rode o deploy de
dentro de `web/`, sem `--prebuilt`.

O backend precisa liberar a origem do site no CORS (`TRATO_SEG_CORS_ORIGENS`, fora de `web/`).
