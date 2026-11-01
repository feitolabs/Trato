# Sobras da revisão de segurança (30/10/2026)

Lista exata do que as sessões `fix-dinheiro`, `fix-acesso` e `fix-app` deixaram de fora, mais os baixos
(B1 a B8) e o que a revisão não pôde verificar. Fontes: `docs/revisao-seguranca.md`, `docs/fix-dinheiro.md`,
`docs/fix-acesso.md`, `docs/fix-app.md` e `backend/tests/api/test_revisao_seguranca_xfail.py`.

Legenda: **Corrigido** = código/config + teste que falhava antes. **Em arquivo** = migration nova, NÃO aplicada
(precisa do seu OK). **Roteiro** = depende de ambiente real; ver `docs/roteiro-testes-reais.md`.
**Aberto** = motivo e próximo passo na linha.

Em português simples: todo `xfail` da revisão já foi convertido em teste normal (o arquivo não tem mais nenhum).
Nesta rodada fechei os baixos que eram código, deixei a mudança de banco pronta em arquivo e escrevi o que só dá
para provar com Supabase, Stripe e aparelho reais.

## 1. `xfail` restantes

Nenhum. `test_revisao_seguranca_xfail.py` só tem testes normais (C1, A1–A8 já passam). Conferido com `grep xfail`.

## 2. Baixos (B1–B8)

| Item | Estado | O que foi feito / o que falta |
|---|---|---|
| **B1** `iss` do JWT | Corrigido (fix-acesso) | `iss` conferido quando `SUPABASE_URL` está no `.env`; `tests/api/test_fix_acesso_jwt.py`. |
| **B2** colunas internas em `grant select` | **Em arquivo** | `supabase/migrations/20261030140000_b2_grants_por_coluna.sql` (+ rollback `b2_grants_por_coluna_rollback.sql`). Tira do app `aditivos.decidido_por`, `lancamentos.criado_por/descricao`, `repasses.provedor_transferencia_id/congelado_por_disputa_id`, `retrabalhos.custo_centavos`, `eventos_webhook.payload/erro`. Testado em Postgres local descartável (`supabase/testes/testar_banco.py`: aplica, nega, `service_role` segue lendo, rollback deixa o banco igual). Falta o seu OK para aplicar (pedido no fim). Prova no Supabase real: `harness/teste_real_rls.py` e `harness/teste_real_banco.py`. |
| **B3** mensagem do gatilho com uuid | Corrigido | `persistencia/erros.py:texto_seguro` troca por texto fixo quando a mensagem tem uuid e registra o detalhe no log; usado também em `api/admin/postgres.py`. Teste: `tests/test_sobras_erros_banco.py`. |
| **B4** dedupe só em memória / tolerância de 300 s | Corrigido (fix-dinheiro, C1) | Dedupe é `unique(provedor, evento_id)` + `pg_advisory_xact_lock`. Os 300 s são o padrão do próprio Stripe. Prova real: `harness/teste_real_webhook.py`. |
| **B5** tabela criada por outro papel nasce aberta | Corrigido | `testar_banco.py` já confere "toda tabela de `public` tem RLS" e "anon sem nenhum privilégio" (rodou: 608 verificações). O gatilho de evento da migration do fix-acesso cobre tabela nova. Em produção: `harness/teste_real_banco.py` repete a checagem no Supabase real. |
| **B6** papel único por conta | Aberto: decisão de produto | Quem é profissional não abre pedido como cliente com a mesma conta. Próximo passo: o João decide (duas carteiras na mesma conta ou duas contas). Não mexi. |
| **B7** cartão sem `capture_method`/3DS explícitos | Corrigido | `stripe_teste.py` envia `capture_method=automatic` e `request_three_d_secure=automatic`. Teste: `tests/test_sobras_erros_banco.py::test_b7_*`. Pix/parcelamento seguem como estavam. |
| **B8** CI e dependências | Parcial | Feito: Dependabot (fix-acesso) e job `auditoria` (`pip-audit==2.9.0`, `--strict`) em `.github/workflows/verificar.yml`. Aberto: lock com hash do backend (precisa gerar com `pip-compile --generate-hashes` no Linux/py3.11 e trocar o `pip install` do CI; não gerei porque o lock de Windows não serve ao CI) e `flutter pub outdated` informativo no CI (sem ferramenta de vulnerabilidade no Dart). |

## 3. Médios que ficaram parciais

| Item | Estado | O que falta |
|---|---|---|
| **M6** banir a sessão no Auth ao bloquear conta | Aberto: efeito real | Chama a API de admin do Supabase Auth. Hoje o backend já recusa o JWT de conta bloqueada e a policy restritiva cobre o PostgREST/Storage até o token expirar. Próximo passo: o João liberar o uso de `SUPABASE_SERVICE_ROLE_KEY` para `auth.admin.sign_out`; testar com `harness/teste_real_rls.py` (token de conta bloqueada). |
| **M7** perdedor do orçamento / M6 tabela futura | Em arquivo (fix-acesso, aguarda OK) | Prova real: `teste_real_rls.py` (B lê pedido de A → vazio). |
| **M8** EXIF no servidor | Corrigido | O backend já limpa JPEG/PNG/WebP (`uploads/imagem.py`, `api/rotas_upload.py`); app também recodifica. HEIC/PDF seguem recusados pelo tipo. |
| **M11** CPF e aceite dos termos no cadastro | Parcial | CPF: feito (`POST /v1/cadastro/cpf` antes do `signUp` e `POST /v1/me/dados-pessoais` no primeiro login; validação de dígitos e unique fecham a corrida). Falta `aceite_termos_*`: depende do texto jurídico e da decisão de guardar em claro ou só o hash (o schema hoje guarda texto). |
| **M12** contadores em memória (A1 e limite de taxa) | Aberto: infra | Valem por processo. Com 2 instâncias o limite dobra. Próximo passo: `Contadores` em Redis ou tabela Postgres (mesma interface). Só é problema com mais de uma instância; subir com 1 até lá. |
| **M13** Keystore/migração de sessão em aparelho | Roteiro | `docs/roteiro-testes-reais.md` seção 6. |
| **M14** `--dart-define` | Corrigido (fix-app) | `harness/verificar_defines.py` na etapa `segredos`. |

## 4. Altos/críticos: o que o fix deixou aberto

| Item | Estado | O que falta |
|---|---|---|
| **C1** `ServicoPagamento` na fábrica Postgres | Aberto: decisão P7 + `api/` em mudança | Cobranças, aditivos e termos continuam em memória no serviço; no modo `postgres`, `POST /v1/contratos/{id}/cobranca` responde 503. Próximo passo: escolher o provedor por configuração (Stripe sandbox) e aplicar `20261030120000_ordens_estorno.sql` (precisa do OK) e criar tabelas de cobrança/aditivo/termos. Mexe em `api/fabrica.py`, que a sessão `backend-divergencias` está alterando; fazer depois do merge dela. |
| **A1** aviso ao cliente/suporte no bloqueio do código | Aberto | Hoje o bloqueio vai para a auditoria (`checkin.codigo_bloqueado`). Falta notificar: ligar `ServicoNotificacoes.notificar` em `seguranca/tentativas_codigo.py` (categoria nova de segurança). Mexe em `api/`; fazer junto da C1. Código de 6 dígitos é decisão de produto e muda o app. |
| **A2** rota `/v1/pedidos/{id}/disputa/decisao` duplicada | Aberto | Remover quando a decisão passar toda por `/v1/admin/disputas` (testes de ponta a ponta ainda usam). |
| **A8** retenção de documentos (`excluir_em`) | Aberto: jurídico | Decisão do advogado/DPO (N10). |
| fix-dinheiro 2: `mediador` ativo exigido pelo banco | Aberto (regra do banco) | Decisão pela API admin com outro papel leva 409. É a regra; manter. |
| fix-dinheiro 4–5: quem pede a transferência ao parceiro; seed de `contas_ledger` | Aberto: P7 | Depende do modelo de contas do parceiro. O seed existe em arquivo (`seed_contas_ledger_rollback.sql`); aplicar só com OK. |

## 5. Do app e do painel (fix-app, "Pendente")

| # | Estado | Próximo passo |
|---|---|---|
| 1 revalidar imagem no servidor | Corrigido (ver M8) | — |
| 2 CSP e `X-Frame-Options` no host do painel | Roteiro/infra | Cabeçalhos são do host (Firebase Hosting/Nginx). Receita em `docs/roteiro-testes-reais.md` seção 7. |
| 3 iOS: `Info.plist`, Keychain `first_unlock_this_device`, nonce do Google | Roteiro | Precisa de Mac/Xcode. Roteiro seção 6. |
| 4 ofuscação e R8 | Aberto | `flutter build apk --obfuscate --split-debug-info=...` e `minifyEnabled`; exige guardar os símbolos. Fazer no build de lançamento (`docs/BUILD.md`). |
| 5 API http no emulador | Aberto (pequeno) | Criar `android/app/src/debug/AndroidManifest.xml` com `usesCleartextTraffic=true` só em debug. Não fiz: exige rodar o build Android. |
| 6 migração de sessão em aparelho | Roteiro | seção 6. |
| 7 rascunho persistido | Aberto: produto | — |

## 6. "O que NÃO foi possível verificar" (revisão, seção final)

| # | Estado |
|---|---|
| 1 painel `admin/` | Revisado depois (fix-app); sem token em disco, defines com lista permitida. CSP: item 5.2. |
| 2 Supabase real: policies exercitadas, Realtime, GraphQL, PostgREST | **Roteiro**: `harness/teste_real_rls.py`, `harness/teste_real_banco.py`; Realtime/GraphQL: seção 5 do roteiro (conferir no painel do Supabase). |
| 3 suítes SQL e de integração | Reexecutadas: `testar_banco.py` (608 OK) e `tests/integracao` (venv descartável com pgserver). |
| 4 concorrência (A6) | Teste local com threads existe (`test_dinheiro_postgres.py`). **Roteiro** para o real: seção 3 do roteiro. |
| 5 Stripe real | **Roteiro**: `harness/teste_real_webhook.py` + Stripe CLI (seção 2). |
| 6 app em aparelho, nonce Google/Apple, ofuscação | **Roteiro** seção 6. |
| 7 logs com dado pessoal no uvicorn/proxy/Supabase | **Roteiro** seção 7 (conferir `--no-access-log` ou filtro de query/IP). |
| 8 retenção LGPD | Aberto: advogado/DPO. |
| 9 infra (HTTPS, firewall, rotação de chaves, backups) | **Roteiro** seção 7. |
| `EXCLUDE` das faixas de taxa | O Postgres embutido não traz `btree_gist`; **Roteiro** com `harness/teste_real_banco.py` (insere duas faixas sobrepostas em transação que termina em ROLLBACK). |

---

PRECISO DO SEU OK

**O que:** aplicar no Supabase a migration `supabase/migrations/20261030140000_b2_grants_por_coluna.sql`.

**Por quê:** fecha o B2: o app (usuário logado) deixa de poder ler colunas internas do dinheiro
(`lancamentos.criado_por/descricao`, `repasses.provedor_transferencia_id`, `eventos_webhook.payload`…).

**Risco:** baixo. Só troca privilégio de tabela por privilégio de coluna; nenhum dado é lido nem escrito. Se alguma tela
do app ler essas colunas direto pelo PostgREST ela passa a falhar (o app usa a API do backend, que usa `service_role`).

**Como desfazer:** `supabase/rollback/b2_grants_por_coluna_rollback.sql`.

**Posso continuar?** Sem o seu "sim" a migration fica só como arquivo. (As migrations `20261030000000_fix_acesso…` e
`20261030120000_ordens_estorno.sql` seguem aguardando o OK dos respectivos documentos.)
