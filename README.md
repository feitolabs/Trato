# Trato

> Serviço feito, dinheiro liberado. — um app **Feito Labs**

Marketplace de serviços (pedreiro, eletricista, diarista…). O cliente descreve o problema,
recebe até 5 orçamentos e paga. O dinheiro fica **retido** até o serviço acabar.

## Stack

| Parte | Tecnologia |
|---|---|
| App (Android e iOS) | Flutter — pasta `app/` |
| Backend (regras de dinheiro) | Python (FastAPI) — pasta `backend/` |
| Banco, auth, storage | Supabase — projeto "Trato" |
| Pagamentos | Stripe |

## Documentos

- `contexto.md` — ordem de serviço do projeto (ler primeiro).
- `regras.txt` — regras obrigatórias.
- `observações extras que discutimos d.txt` — decisões que valem mais que o escopo.
- `Trato— Escopo Completo do Produto.pdf` — escopo (88 páginas).
- `Trato — Telas do app.pdf` — protótipo e design (27 telas).
- `harness/` — tarefas, progresso, decisões e pendências.

## Fluxo de branches (Gitflow)

- `main` — só versões liberadas (tags `vX.Y.Z`).
- `develop` — integração.
- `feature/<nome>` — sai de `develop`, volta para `develop` com `--no-ff`.
- `release/<versão>` — sai de `develop`, volta para `main` e `develop`.
- `hotfix/<versão>` — sai de `main`, volta para `main` e `develop`.
