# Roteiro de testes em ambiente real

O que só dá para provar com Supabase, Stripe e aparelho de verdade. Cada passo diz o comando, o resultado esperado
e o que você precisa ter configurado. Os scripts ficam em `harness/` e usam só as suas chaves, lidas do ambiente.

**Regras dos scripts:** não criam conta, não escrevem dado. Só leitura, ou uma transação que termina em `ROLLBACK`
(`teste_real_banco.py`), ou um evento de teste sem efeito (`teste_real_webhook.py`, em memória por padrão). Todos
exigem `TRATO_TESTE_REAL=sim` e imprimem uma linha `OK`, `FALHOU` ou `PULADO` por verificação (saída 1 se algo falhar).
Já foram executados aqui contra a API em memória (webhook) e contra Postgres local (checagens de privilégio);
**contra o Supabase e o Stripe reais ainda não**.

## 0. O que você precisa ter

- Projeto Supabase "Trato" com as migrations aplicadas (inclua as que aguardam OK: `20261030000000_fix_acesso…`,
  `20261030140000_b2_grants_por_coluna.sql`, se quiser provar A8/M6/M7/B2).
- **Duas contas de teste já existentes** (A e B) e o `access_token` de cada uma (login pelo app e leitura da sessão, ou
  `POST {SUPABASE_URL}/auth/v1/token?grant_type=password`). Tokens duram ~1 h. Não coloque no `.env` versionado.
- Um pedido da conta A, com orçamento/contrato, de preferência com uma mídia, uma mensagem no chat e um arquivo no Storage.
- Conta Stripe em **modo teste**, `STRIPE_WEBHOOK_SECRET` (`whsec_…` do endpoint de teste) e Stripe CLI instalada.
- Python do backend: `backend/.venv` (Windows: `backend\.venv\Scripts\python.exe`).

Exemplo de ambiente (PowerShell; valores só no seu terminal, nunca no git):

```powershell
$env:TRATO_TESTE_REAL = "sim"
$env:SUPABASE_URL = "<url do projeto>"
$env:SUPABASE_ANON_KEY = "<chave anon/publishable>"
$env:TRATO_JWT_A = "<access_token da conta A>"
$env:TRATO_JWT_B = "<access_token da conta B>"
$env:TRATO_PEDIDO_A = "<id do pedido da conta A>"
```

## 1. Isolamento entre dois usuários (RLS + Storage)

Opcionais para ampliar: `TRATO_MIDIA_A` (id de `midias`), `TRATO_MENSAGEM_A` (id de `mensagens`), `TRATO_STORAGE_PATH_A`
(`bucket/caminho` de um arquivo de A, por exemplo `pedidos/<pedido>/foto.jpg`).

```bash
backend/.venv/Scripts/python harness/teste_real_rls.py
```

Esperado (resumo):

| Verificação | Resultado esperado |
|---|---|
| A lê o próprio pedido (controle) | `OK`, 1 linha |
| B lê pedido, endereço, histórico, contrato, conversa e mídias de A | `OK`: lista vazia (a RLS filtra) ou 401/403 |
| B lê o ledger (`lancamentos`) sem ser parte | `OK`: vazio |
| anon (só chave anon) lê o pedido de A | `OK`: vazio ou negado |
| A lê colunas internas (`lancamentos.criado_por`, `repasses.provedor_transferencia_id`, `eventos_webhook.payload`) | `OK` só **depois** de aplicar a migration B2 (antes disso `FALHOU` é o esperado) |
| A lê `verificacao_documentos` direto | `OK` só depois da migration do fix-acesso (A8) |
| B baixa o arquivo de A no Storage | `OK`: 400/403/404; e A baixa o próprio (controle) |

Se o controle de A falhar, o token expirou ou o id está errado: nada do resto prova algo.
Para M7 (quem perdeu o orçamento): use como B uma conta com orçamento `recusado` num pedido cujo contrato é de outra conta e
rode a consulta `pedido_historico?pedido_id=eq.<id>&select=id`: esperado vazio depois da migration do fix-acesso.
Para conta bloqueada (M6): bloqueie a conta de teste B no painel, use o token antigo dela e repita; esperado vazio/negado.

## 2. Webhook do Stripe: assinatura válida, inválida e reenvio

**2a. Verificação de assinatura.** Contra o seu backend de teste (com `STRIPE_WEBHOOK_SECRET` igual ao do endpoint de teste):

```powershell
$env:STRIPE_WEBHOOK_SECRET = "<whsec_ do modo teste>"
$env:TRATO_API_URL = "http://127.0.0.1:8000"         # ou a URL do backend de teste
$env:TRATO_PERSISTENCIA = "postgres"                  # igual ao do backend que você está testando
$env:TRATO_PERMITE_EVENTO_NO_BANCO = "sim"            # aceita deixar 1 linha evt_teste_* (eventos_webhook é imutável)
backend/.venv/Scripts/python harness/teste_real_webhook.py
```

Esperado: 6 `OK` — sem cabeçalho, segredo errado, corpo alterado e assinatura de 1 h atrás dão 400; assinatura válida dá 200
`duplicado=false`; reenvio dá 200 `duplicado=true`. Sem `TRATO_PERMITE_EVENTO_NO_BANCO=sim` e com `TRATO_PERSISTENCIA=postgres`,
as duas últimas saem `PULADO` e nada é gravado. A mesma lógica roda sem rede em
`backend/tests/api/test_sobras_script_webhook.py` (API em memória), a cada `verificar`.

**2b. Fluxo real com o Stripe CLI (modo teste).**

```bash
stripe listen --forward-to http://127.0.0.1:8000/v1/webhooks/stripe     # mostra o whsec_ da sessão
stripe trigger payment_intent.succeeded                                  # evento assinado de verdade
stripe events resend <evt_id> --webhook-endpoint=<we_id>                 # reenvio do MESMO evento
```

Esperado: 1ª entrega 200 com efeito (pedido vai a `pago_retido` e o ledger recebe os lançamentos); reenvio 200 com
`duplicado=true` e **nenhum lançamento novo** (confira com `select count(*) from lancamentos where evento_webhook_id = …`
= o mesmo número). Evento com valor diferente do da cobrança: 200, nada confirmado, linha em `eventos_webhook.erro`
(M1/M2). `stripe trigger charge.refunded` sem ordem nossa: alerta e lançamento de estorno (M3).
**Atenção:** com backend em modo `postgres`, `eventos_webhook` é imutável; cada evento de teste deixa uma linha. Use um projeto
Supabase de teste, não o de produção.

## 3. Corrida de dois pagamentos simultâneos

Localmente já existe teste com threads (`backend/tests/integracao/test_dinheiro_postgres.py`: duas transições, dois
estornos e o mesmo lançamento chegando junto). No ambiente real:

1. Crie (pelo app/API) um pedido aceito e peça a cobrança. Anote `pedido_id` e `pi_…`.
2. Dispare **dois** envios do mesmo `payment_intent.succeeded` ao mesmo tempo (mesmo `evt_id`) e depois dois com `evt_id`
   diferentes para o mesmo `pi_`:

```bash
stripe events resend <evt_id> --webhook-endpoint=<we_id> & stripe events resend <evt_id> --webhook-endpoint=<we_id> & wait
```

3. Confira (somente leitura) no SQL Editor:

```sql
select count(*) from lancamentos l join contratos c on c.id = l.contrato_id
 where c.pedido_id = '<pedido>' and l.tipo = 'cobranca';          -- esperado: 1
select status from pedidos where id = '<pedido>';                  -- esperado: pago_retido (uma vez)
select count(*) from eventos_webhook where evento_id = '<evt_id>'; -- esperado: 1
```

Esperado: um único lançamento de cobrança, um único registro do evento, nenhum erro 500 nos logs (o perdedor da corrida
recebe 200 `duplicado=true` ou 409 e é reenviado pelo Stripe).

## 4. `EXCLUDE` das faixas de taxa e superfície do banco

O Postgres embutido dos testes não traz `btree_gist`, então só o Supabase real prova o `EXCLUDE`.

```bash
$env:DATABASE_URL = "<conexão do projeto Trato>"      # só no seu terminal
backend/.venv/Scripts/python harness/teste_real_banco.py
```

Esperado: `btree_gist` instalada; `EXCLUDE` existe em `config_faixas_taxa`; toda tabela de `public` com RLS; `anon` sem
grant; colunas internas fechadas (B2, depois da migration); faixas `[900000000, 900001000)` e `[900000500, 900002000)`
na mesma versão em rascunho → o 2º insert é recusado com `23P01`; a vizinha `[900001000, 900002000)` é aceita.
Tudo isso dentro de uma transação que **sempre** termina em `ROLLBACK` (nada fica gravado). Precisa existir uma versão de
configuração em **rascunho** (crie uma no painel; se não houver, o passo sai `PULADO`).

## 5. Realtime, GraphQL e PostgREST

No painel do Supabase (somente leitura):

- **Database → Replication:** nenhuma tabela de `public` na publicação `supabase_realtime`, exceto as que o app de fato assina
  (mensagens, se ligar o chat em tempo real). Esperado: RLS vale também para Realtime; confira com o token de B assinando o
  canal de `mensagens` de A: não deve receber evento.
- **GraphQL:** `pg_graphql` desligada (`select * from pg_extension where extname='pg_graphql'` vazio) ou sem grant a `anon`.
- **Advisors (Security):** `get_advisors` / aba Advisors sem alerta de RLS desligada nem de função `SECURITY DEFINER` exposta.

## 6. Aparelho real (Android e iOS)

Precisa de um celular Android com depuração USB e, para iOS, de um Mac com Xcode (ou o CI de `ios.yml`).

1. **Sessão no Keystore/Keychain (M13):** instale a versão antiga (sessão em `SharedPreferences`), faça login, atualize para a
   nova e abra. Esperado: continua logado e o arquivo antigo foi apagado
   (`adb shell run-as <pacote> ls shared_prefs` não deve mais listar `FlutterSharedPreferences` com `sb-…auth-token`).
2. **Backup desligado:** `adb backup -noapk <pacote>` não deve gerar dados do app (arquivo vazio).
3. **Tráfego em texto puro:** com API em `http://` o app deve recusar (`usesCleartextTraffic=false`); em dev use o manifesto de
   debug (ver `sobras-seguranca.md`, seção 5, item 5).
4. **Câmera e GPS:** conceda "em uso"; tire uma foto de check-in e baixe a imagem enviada: `exiftool` não deve mostrar GPS/EXIF.
5. **iOS:** conferir no `Info.plist` as chaves `NSCameraUsageDescription`/`NSLocationWhenInUseUsageDescription`, ATS sem
   exceção, Keychain com `first_unlock_this_device`; login Google/Apple com `nonce` (verificar no payload do `id_token`).
6. **Defines:** `python harness/verificar.py --etapa segredos` deve passar antes de qualquer build.

## 7. Infra, logs e cabeçalhos (fora do repositório)

- **Logs:** no servidor do backend suba o uvicorn com `--no-access-log` (ou filtre a query string) e confirme que o proxy não
  grava corpo nem `Authorization`. No Supabase, revise **Logs Explorer**: nenhum CPF/telefone em texto.
- **HTTPS e HSTS:** `curl -sI https://<api>/saude` deve mostrar `strict-transport-security`.
- **CSP do painel (Flutter Web):** no host (Firebase Hosting `firebase.json` → `headers`, ou Nginx) defina
  `Content-Security-Policy: default-src 'self'; connect-src 'self' <API> <SUPABASE_URL>; img-src 'self' data: blob:; frame-ancestors 'none'`
  e `X-Frame-Options: DENY`. O Flutter Web precisa de `'wasm-unsafe-eval'` em `script-src` com CanvasKit; teste no navegador.
  Conferir: `curl -sI https://<painel>/ | findstr /i "content-security x-frame"`.
- **Rotação de chaves:** gire `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY` e `STRIPE_WEBHOOK_SECRET`; confirme que o
  backend só lê do ambiente e que a chave antiga passa a dar 401.
- **Backups:** Supabase → Database → Backups com PITR ligado e um restore de teste num projeto à parte.
- **Limite de taxa:** no gateway/CDN na frente do backend (o limite do app é por processo; ver `sobras-seguranca.md`, M12).
