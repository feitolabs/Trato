# Painel admin × API admin: prova de integração

Em português simples: até aqui o painel só tinha conversado com um servidor **de mentira escrito no próprio
teste Dart**. Agora ele conversou com o **backend de verdade** (em memória, sem banco real, sem chave real) e
o resultado está aqui. Nada foi escrito em banco real; nenhuma chave real foi usada.

## Como reproduzir

```bash
# 1) backend de teste (memória, dados de exemplo, login Supabase de mentira, CORS só local)
python harness/subir-backend-teste.py --porta 8765

# 2) contrato das rotas, em Python (não precisa de servidor, usa o mesmo ambiente por dentro)
python -m pytest backend/tests/integracao_painel

# 3) o cliente HTTP REAL do painel (ApiAdminHttp) contra o servidor do passo 1
cd admin
TRATO_BACKEND_TESTE=http://127.0.0.1:8765 flutter test test/integracao   # reinicie o servidor entre rodadas

# 4) o painel no navegador (flutter build web + qualquer servidor estático em :8080 ou :8081)
flutter build web --release --dart-define=ADMIN_MODO=api --dart-define=ADMIN_API_URL=http://127.0.0.1:8765 \
  --dart-define=ADMIN_SUPABASE_URL=http://127.0.0.1:8765 --dart-define=ADMIN_SUPABASE_ANON_KEY=anon-de-teste
```

Contas: `<papel>@teste.trato.local`, senha de teste `senha-de-teste-local` (vale só nesse servidor). O
servidor tem: uma conta por papel (+ `administrador2`), 2 verificações pendentes, 2 disputas abertas
(`ped-1` R$ 1.000, dentro da alçada do mediador; `ped-2` R$ 3.000, acima), 3 cobranças (uma sem pedido =
divergente), configuração vigente + um rascunho, e a auditoria que o próprio uso gera.

## Resultado

| Item | Resultado |
|---|---|
| Rotas que o painel usa (contrato, 401/403/404/409/422, formato) | `backend/tests/integracao_painel/`: 30 testes passam |
| `ApiAdminHttp` do painel × backend, HTTP real | `admin/test/integracao/`: 8 testes passam (login por papel, verificação, disputa com alçada e segunda pessoa, pagamentos, busca, config com aprovação dupla, auditoria) |
| Painel compilado (`flutter build web`) no navegador | login `cadastro` ok → fila de verificação → "Revelar" → `POST …/documentos/…/url` 200 → abre a URL assinada |
| Bundle sem chave | ver "O que o painel nunca mostra" |

### Divergência encontrada e corrigida

| # | O que | Onde | Correção |
|---|---|---|---|
| 1 | O login do painel chama `GET /v1/admin/eu` (papel e alçada) e **a rota não existia** no backend: o login real sempre falharia. `docs/painel-admin.md` já avisava ("falta a rota `/eu`"). | backend | `GET /v1/admin/eu` → `{id, papel, nome, alcada_centavos}`. O papel vem da tabela `equipe`, nunca do token; qualquer membro vigente da equipe pode chamar (não exige permissão de negócio). Testes: `test_login_supabase_e_eu`, `test_eu_*`. |

Notas (não são erro, mas o painel e a API se comportam assim):

- `GET /v1/admin/config/versoes` devolve uma **lista simples**, não `{itens, total…}` como as outras
  listagens. O painel aceita as duas formas (`_itens`), então funciona; `docs/api-admin.md` diz só "histórico".
- A fila de disputas do painel traz só o que **não** está `decidida`: depois de decidir (ou aprovar), a
  disputa some da tela. É a regra da API (`estado` padrão), e o histórico não aparece no painel hoje.
- A tela do painel abre a URL assinada **em outra aba**. O navegador embutido bloqueou o popup (comportamento
  normal de popup sem clique direto do usuário); a chamada de assinatura em si respondeu 200.
- O servidor de teste liga CORS só para `127.0.0.1`/`localhost` nas portas 8080/8081. Em produção a
  origem do painel entra em `TRATO_SEG_CORS_ORIGENS` (`backend/src/trato/seguranca/config.py`).

## O que o painel nunca deve mostrar

| Regra | Como foi conferido | Resultado |
|---|---|---|
| Documento/selfie só por URL assinada curta, com motivo e auditoria | teste Python: resposta de `verificacoes` não traz caminho de storage; `/url` devolve `expira_em_segundos <= 60`; só `cadastro` abre (seguranca e administrador levam 403); teste Dart: URL `https://…`, sem o nome do bucket | ok |
| CPF mascarado | `cpf_mascarado` = `***.***.***-09` na lista; teste confirma que a busca de usuários não traz `cpf` nem `telefone`; CPF cheio só em `dados-pessoais` (papel + motivo + auditoria) | ok |
| Telefone | idem: nenhuma listagem traz telefone; só a rota de dados pessoais, com motivo | ok |
| Códigos de check-in/out e endereço | teste varre disputa, pedido e usuário e não acha `codigo_inicio`, `codigo_conclusao`, nem os valores | ok |
| Nenhuma chave no bundle | `grep` em `admin/build/web` (build release com os defines acima): 0 ocorrências de `sk_live/sk_test`, JWT (`eyJ…`), `whsec_` com valor, `bucket-privado`, a senha de teste, `storage.exemplo.test`. Aparecem **só nomes** de variáveis proibidas (`SUPABASE_SERVICE_ROLE_KEY`, `ADMIN_SERVICE_ROLE_KEY`) dentro da lista de bloqueio de `defines_publicos.dart` — nome, nunca valor. A única coisa embutida é a chave **pública** `anon-de-teste` que o próprio define pede. | ok |

## O que NÃO consegui rodar / limites

- **Postgres local (pgserver) com o painel:** não rodei. O servidor de teste é 100% memória; o caminho
  Postgres da API admin já tem testes próprios (`backend/tests/integracao/test_admin_postgres.py`), mas o
  painel não foi apontado para ele. Disputas, ledger e webhooks são memória até as tabelas F3.5/F3.6.
- **Supabase Auth real:** o login usou um `/auth/v1/token` de mentira no mesmo servidor. Não foi verificado o
  JWT real do Supabase (assinatura, `iss`) nem o e-mail/senha reais da equipe.
- **Fluxos pela tela:** no navegador percorri só login (`cadastro`) → verificação → "Revelar". Decidir
  verificação, disputa com segunda pessoa, config com aprovação dupla e cadeia de auditoria foram provados
  pelo **cliente HTTP real do painel** (`ApiAdminHttp`) e pelos testes de contrato, não clicando em cada tela.
  Entrar como outros papéis pela tela também não foi repetido; no cliente HTTP, 7 papéis entram.
- **URL assinada real do Storage:** o assinador é de mentira (`AssinadorFalso`); sem `service_role` do
  Supabase a rota real responde 503 (já documentado em `docs/api-admin.md`).
- `flutter test` sem servidor pula os testes de `admin/test/integracao` (variável `TRATO_BACKEND_TESTE`
  ausente), então o `harness/verificar` continua sem depender de servidor.
