# Hospedagem do backend no Fly.io (região gru, São Paulo)

Decisão: backend no **Fly.io em São Paulo (`gru`)**, banco no **Supabase** (já em `sa-east-1`).
Motivo: no Render (Virgínia) cada consulta ao banco custava ~120 ms (ver `harness/PROGRESSO.md`, 06/11).
Levantamento de preços e riscos: `docs/hospedagem-levantamento.pdf`.

Arquivos: `backend/Dockerfile`, `backend/.dockerignore`, `backend/fly.toml`. Nenhum segredo neles.

## O que mudou em relação ao Render

| Item | Render (`render.yaml`) | Fly.io |
|---|---|---|
| Comando de partida | `trato.api.fabrica:criar_app_da_config --factory` | `trato.main:app` |
| Segurança (limite de taxa, HSTS, rotas LGPD) | **não incluída** nesse comando | incluída |
| `/saude` | não existe nesse comando | existe (usada no healthcheck) |
| IP do cliente | sem `TRATO_SEG_CONFIAR_X_FORWARDED_FOR` | `true` (obrigatório atrás do proxy) |

**Atenção:** `trato.main:app` é o ponto de entrada documentado (`backend/README.md`) e o único que liga
`registrar_rotas` (segurança, Fase 8) e `/saude`. O `render.yaml` usa a fábrica direto, então **a produção
no Render provavelmente roda sem essa camada**. Conferir antes de migrar: no Fly o app passa a ter limite de taxa
(300 req/min por IP, entre outros). Se o app do celular fizer muitas chamadas seguidas, ajustar
`TRATO_SEG_LIMITES` em vez de desligar a segurança.

## Variáveis

Não secretas, já no `fly.toml`: `TRATO_AMBIENTE`, `TRATO_PERSISTENCIA`, `TRATO_SEG_CONFIAR_X_FORWARDED_FOR`.

Secretas (mesmos nomes do `render.yaml`), só com `fly secrets set`, **nunca** no chat nem no git:
`DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_JWT_SECRET` (ou `SUPABASE_JWKS_URL`), `TRATO_CODIGO_SEGREDO`,
`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`.

Conferir no painel do Render se há outras variáveis que o `render.yaml` não lista (por exemplo
`TRATO_SEG_PIMENTA_IDENTIFICADORES`, `TRATO_PROVEDOR_PAGAMENTO`, `TRATO_SEG_SMS_HOOK_SEGREDO`, `TRATO_SEG_CORS_ORIGENS`)
e levar as mesmas para o Fly. Mudar o valor de `TRATO_SEG_PIMENTA_IDENTIFICADORES` quebra a detecção de conta duplicada.

## Passo a passo (cada passo é do João; precisa do OK)

1. Instalar o `flyctl` e entrar: `fly auth login`.
2. Cadastrar cartão no painel do Fly (o teste dura ~2 h de máquina ou 7 dias) e criar alerta de gastos.
3. Dentro de `backend/`: `fly apps create trato-backend` (ou o nome que escolher; ajuste o `fly.toml`).
4. Segredos (digite os valores no seu terminal, não aqui):
   `fly secrets set DATABASE_URL=... SUPABASE_URL=... SUPABASE_JWT_SECRET=... TRATO_CODIGO_SEGREDO=... STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=...`
5. `fly deploy` (primeiro deploy cria 1 máquina `shared-cpu-1x` com 512 MB em `gru`).
6. Conferir `https://<app>.fly.dev/saude` e `fly logs`.
7. Medir a latência contra o Render (celular em rede móvel, não só o computador).
8. Trocar o endereço da API no app e no painel (`TRATO_API_URL`) e o webhook do Stripe para a URL nova.
9. Só depois de tudo certo, desligar o serviço no Render.

Quando houver cliente pagando: `fly scale count 2` (duas máquinas) e Supabase Pro.

## Admin (painel)

É Flutter web (`admin/web`), site estático: **não vai no Fly**. Hospedagem estática grátis (Cloudflare Pages ou
Netlify). Vercel Hobby não vale para uso comercial. Depois de publicar, colocar o endereço do painel em
`TRATO_SEG_CORS_ORIGENS` (JSON, sem barra no fim) e refazer o deploy / `fly secrets set`.

## Fora do escopo desta tarefa

- **Agendador** (`python -m trato.agendador`): lembretes, liberação por prazo e reenvio de notificações rodam em outro
  processo. O `render.yaml` também não o sobe. Quando for ligar, vira um segundo processo no `fly.toml`
  (`[processes]`) ou um cron; custa mais uma máquina. Ver `docs/backend-notificacoes.md`.
- Nada foi implantado nem criado no Fly. Nenhuma conta, cartão ou segredo foi tocado.
