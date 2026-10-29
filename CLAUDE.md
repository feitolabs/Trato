# CLAUDE.md — Trato (Feito Labs)

Leia `contexto.md` inteiro antes de qualquer tarefa. Depois leia `harness/PROGRESSO.md`
e pegue a próxima tarefa em `harness/TAREFAS.md`.

## Ordem de prioridade dos documentos

`regras.txt` > `observações extras` > `Trato — Telas do app.pdf` (design) > `Escopo` (PDF).
O escopo fala "WorkNet" e "5%": está velho. O nome é **Trato**; a taxa é **progressiva, base 7,5%, mínima configurável**.

## Regras obrigatórias

1. Backend: **Python** (`backend/`).
2. Frontend: **Flutter** (`app/`). Android e iOS, responsivo e intuitivo.
3. Configuração em arquivos **.env** (só `.env.example` vai para o git, sem valores).
4. **Nunca** senha, chave ou token no código nem no chat.
5. Banco: **Supabase**, projeto "Trato".
6. Repositório: **GitHub**, repositório "Trato".
7. **Respeitar o design e o protótipo.** Nada de cor/fonte solta: usar `app/lib/tema/`.
8. ~~Expo~~ — removida. Não usar.

## Regras de dinheiro (do escopo)

- Nenhuma regra de dinheiro roda no app. O app só pede e mostra; o backend decide.
- Valores em **centavos inteiros**. Taxa, prazos e limites em **tabela de configuração**.
- Ledger imutável (partidas dobradas). Correção só por estorno.
- Toda operação financeira com chave de idempotência; webhooks assinados.

## Ações que precisam do OK do João

- Escrever no banco (INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE, criar ou aplicar migrations).
- Apagar arquivos ou sobrescrever fora do projeto.
- API externa com efeito real (Stripe real, SMS, WhatsApp, e-mail).
- `git push`, deploy, mudar serviços, permissões ou configurações do sistema.
- Qualquer coisa que não dá para desfazer.

Formato do pedido: `PRECISO DO SEU OK` / O que / Por que / Risco / Como desfazer / Posso continuar?

## Gitflow

- `main` = versões liberadas (tag `vX.Y.Z`). `develop` = integração.
- Toda tarefa em `feature/<fase>-<nome>` a partir de `develop`; merge com `--no-ff`.
- Commits em português, estilo `tipo: descrição` (feat, fix, chore, docs, test, refactor).
- Nunca commitar `.env`. Push só com OK.

## Ciclo de cada tarefa

Ler → Planejar (3–6 linhas) → Fazer só a tarefa → `harness/verificar` → Registrar em `PROGRESSO.md` → Mostrar.
Falhou 3 vezes seguidas: pare e explique.

## Estilo

Português do Brasil, frases curtas, direto e técnico, depois uma explicação simples.
