# Painel administrativo (web)

> Projeto Flutter Web em `admin/` (D13: painel admin é web responsivo; não existe app Ops).
> Hoje roda com **dados de exemplo** (`ApiFake`). A API admin do backend ainda não existe: a lista de
> endpoints abaixo é o contrato que o backend precisa cumprir para ligar o painel.

## Como rodar

```bash
cd admin
flutter pub get
flutter run -d chrome
flutter test
flutter analyze
```

No exemplo, o papel vem do começo do e-mail (`financeiro@teste.local` entra como `financeiro`) e a senha só precisa ter
8 caracteres ou mais. Não há senha real em lugar nenhum. A URL da API ficará em `TRATO_API_URL` (`admin/.env.example`,
sem valor); trocar `ApiFake` por uma implementação HTTP de `ApiAdmin` (`admin/lib/dados/api_admin.dart`) é a única mudança
necessária nas telas.

## Regras que o painel segue

- **Nenhuma regra de dinheiro no painel.** Ele pede e mostra; o backend decide. Valores são centavos inteiros.
  A tela só dá dicas (ex.: "este valor passa da sua alçada"); a conferência de verdade é do backend.
- **Papel manda no menu e nas ações** (`admin/lib/nucleo/papeis.dart`). Isso é só vitrine: o backend devolve **403** se o
  papel não tiver a permissão, e a RLS do banco continua valendo.
- **Ação sensível pede motivo** (mínimo de 10 caracteres na tela) e mostra "Será registrado na auditoria."
- **Dado pessoal e documento vêm mascarados** e só abrem com motivo (cada abertura vira linha de auditoria).
- **Sem saldo e sem saque (D15).** A tela de pagamentos é somente leitura e espelha o que o provedor confirmou.
  O painel nunca escreve "pago" antes da confirmação do provedor (D13).
- **Textos sem as promessas proibidas pela D13.** `harness/verificar.py` varre `admin/lib/` também.
- **Visual do app.** `admin/lib/tema/` é cópia de `app/lib/tema/` (aviso de origem em cada arquivo e em
  `admin/lib/tema/LEIA-ME.md`). Cor só no tema; `verificar.py` recusa `Color(0x...)` e `Colors.*` fora dele.

## Responsivo

| Largura | Layout |
|---|---|
| 960 dp ou mais (desktop) | menu lateral fixo; lista e detalhe lado a lado |
| menos de 960 dp (tablet) | menu em gaveta; abaixo de 760 dp o detalhe abre em outra tela |

Estados de toda lista: carregando, vazio, erro com "Tentar de novo".

## Telas

| Tela | Tarefa | O que faz |
|---|---|---|
| Login | — | E-mail e senha pela interface `ApiAdmin.entrar`. Conta sem papel de equipe não entra. |
| Verificação | F7.1 | Fila de profissionais; detalhe com CPF, documentos e selfie **escondidos**; "Revelar" pede motivo; aprovar/recusar exige motivo. |
| Disputas | F7.2 | Fila; detalhe com relato, evidências (nota interna só da equipe) e linha do tempo; decidir: liberar tudo, reembolso total, parcial (valor) ou nova visita; justificativa obrigatória; valor acima da alçada pede a **segunda pessoa** (e-mail) e a disputa fica "Aguardando segunda pessoa". |
| Pagamentos | F7.3 | **Somente leitura.** Resumo (confirmado, aguardando confirmação, divergências) e extrato espelho do provedor. Nenhum botão de ação. |
| Busca e suporte | F7.4 | Abas: usuários (dados mascarados, "Revelar" com motivo), pedidos, chamados de suporte, categorias (ativar/desativar com motivo). |
| Configurações | F7.5 | Mostra a versão vigente; propõe mudança com validação de faixa vinda da definição; **aprovação dupla** (quem propôs não aprova); histórico com diferença para a vigente; reverter cria nova versão para aprovação. |
| Auditoria | F7.6 | Lista com filtro por ação e por pessoa; botão "Verificar cadeia de hash" mostra íntegra ou o primeiro registro quebrado. |

## Papéis e o que cada um vê

Papéis = `equipe.papel` (`docs/modelo-de-dados.md` 3.3). ✔ = permissão no painel.

| Papel | Verificação | Disputas | Pagamentos | Busca / suporte | Configurações | Auditoria |
|---|---|---|---|---|---|---|
| `cadastro` | ✔ ver, decidir, abrir documento | — | — | usuários, revelar dados | — | — |
| `atendente_n1` | — | — | — | usuários, pedidos, suporte | — | — |
| `atendente_n2` | — | ver | — | usuários, pedidos, suporte | — | — |
| `lider_suporte` | — | ver, decidir, 2ª pessoa | — | usuários, pedidos, suporte | — | — |
| `mediador` | — | ver, decidir | — | pedidos | — | — |
| `moderador` | — | — | — | usuários, pedidos, **categorias** | — | — |
| `financeiro` | — | — | ✔ ver | pedidos | ver, **propor** | — |
| `seguranca` | ver | — | — | usuários, revelar dados | — | ver, verificar cadeia |
| `juridico` | — | — | — | — | ver | ver, verificar cadeia |
| `dpo` | — | — | — | usuários, revelar dados | — | ver, verificar cadeia |
| `administrador` | ver | ver, decidir, 2ª pessoa | ✔ ver | tudo, categorias | ver, propor, **aprovar** | ver, verificar cadeia |

Notas: só o administrador aprova configuração (e nunca a própria proposta). A "segunda pessoa" da disputa é líder de
suporte ou administrador (`docs/modelo-de-dados.md` 8.1). A tabela de permissões é do painel; o backend deve ter a sua
(mesma regra) e não confiar no que o painel mostra.

## Endpoints que o backend precisa expor

Prefixo `/v1/admin`. Todos exigem `Authorization: Bearer <token da sessão da equipe>` e devolvem:
`401` (sem sessão), `403` (papel sem permissão), `422` (validação, com `detalhe` em português para mostrar na tela).
Todo `POST`/`PUT` aceita `Idempotency-Key`. Toda ação sensível grava `auditoria` via `registrar_auditoria()` (com `motivo`,
ator, IP e `request_id`). Valores de dinheiro: **centavos inteiros**.

### Sessão

| Método e caminho | Corpo | Resposta | Papel |
|---|---|---|---|
| `POST /v1/admin/sessao` | `{email, senha}` | `{token, usuario:{id, nome, email, papel, alcada_centavos}}` | qualquer papel ativo em `equipe` (senão 403) |
| `DELETE /v1/admin/sessao` | — | `204` | autenticado |

### F7.1 Verificação

| Método e caminho | Corpo | Resposta | Papel |
|---|---|---|---|
| `GET /v1/admin/verificacoes?status=` | — | `[{id, profissional, categoria, cidade, enviada_em, cpf_mascarado, documentos:[rotulo], status, motivo_decisao}]` | `cadastro`, `seguranca`, `administrador` |
| `POST /v1/admin/verificacoes/{id}/documentos/{rotulo}/revelar` | `{motivo}` | `{url_assinada, expira_em}` (curta, ex.: 60 s) | `cadastro` |
| `POST /v1/admin/verificacoes/{id}/decisao` | `{decisao: "aprovar"\|"recusar", motivo}` | `{status}` | `cadastro` |

### F7.2 Disputas

| Método e caminho | Corpo | Resposta | Papel |
|---|---|---|---|
| `GET /v1/admin/disputas?status=` | — | `[{id, pedido, cliente, profissional, motivo, descricao, valor_em_analise_centavos, decisao_ate, status, evidencias:[{autor, tipo, texto, nota_interna}], linha_do_tempo:[{quando, autor, texto}], decisao, valor_reembolso_centavos}]` | `atendente_n2`, `lider_suporte`, `mediador`, `administrador` |
| `POST /v1/admin/disputas/{id}/decisao` | `{decisao: "liberar_tudo"\|"reembolso_total"\|"reembolso_parcial"\|"nova_visita", valor_reembolso_centavos?, justificativa, segunda_pessoa_email?}` | `{status: "decidida"\|"aguardando_segunda_pessoa", mensagem}` | `mediador`, `lider_suporte`, `administrador` |
| `POST /v1/admin/disputas/{id}/aprovacao` | `{aprovar: bool, motivo}` | `{status}` | `lider_suporte`, `administrador`; **não** pode ser quem decidiu |

O backend confere a alçada (`equipe.alcada_centavos`, vinda da configuração), o teto do valor em análise e a regra
"acima da alçada exige segunda pessoa" (`docs/modelo-de-dados.md` 8.1). A tela ainda não tem botão para a segunda pessoa
aprovar (`/aprovacao`): é um passo a adicionar quando o endpoint existir.

### F7.3 Pagamentos (somente leitura)

| Método e caminho | Corpo | Resposta | Papel |
|---|---|---|---|
| `GET /v1/admin/pagamentos/conciliacao` | — | `{confirmado_centavos, aguardando_centavos, divergencias, atualizado_em}` | `financeiro`, `administrador` |
| `GET /v1/admin/pagamentos/extrato?de=&ate=&status=&pagina=` | — | `[{id, data, descricao, valor_centavos, status: "aguardando_confirmacao"\|"confirmado"\|"falhou"\|"reembolsado", pedido, ref_provedor, divergente}]` | `financeiro`, `administrador` |

Sem `POST`, sem saque, sem saldo (D15). Os dados vêm do espelho do ledger, não de chamada ao provedor.

### F7.4 Busca, suporte e categorias

| Método e caminho | Corpo | Resposta | Papel |
|---|---|---|---|
| `GET /v1/admin/usuarios?q=` | — | `[{id, nome, tipo, status, email_mascarado, cpf_mascarado}]` | `atendente_n1/n2`, `lider_suporte`, `cadastro`, `moderador`, `seguranca`, `dpo`, `administrador` |
| `POST /v1/admin/usuarios/{id}/dados-pessoais/revelar` | `{motivo}` | `{email, cpf, telefone}` (audita `dado_pessoal.revelado`) | `cadastro`, `seguranca`, `dpo` |
| `GET /v1/admin/pedidos?q=` | — | `[{id, titulo, cliente, status, valor_centavos}]` | `atendente_n1/n2`, `lider_suporte`, `mediador`, `moderador`, `financeiro`, `administrador` |
| `GET /v1/admin/suporte/chamados?status=` | — | `[{id, assunto, solicitante, status, aberto_em}]` | `atendente_n1/n2`, `lider_suporte`, `administrador` |
| `GET /v1/admin/categorias` | — | `[{id, nome, ativa, profissionais}]` | `moderador`, `administrador` |
| `PUT /v1/admin/categorias/{id}` | `{ativa: bool, motivo}` | `{id, ativa}` | `moderador`, `administrador` |

### F7.5 Configurações

| Método e caminho | Corpo | Resposta | Papel |
|---|---|---|---|
| `GET /v1/admin/config` | — | `{definicoes:[{chave, descricao, unidade, minimo, maximo, exige_dupla_aprovacao}], versoes:[{id, numero, status, motivo, criada_por, criada_em, aprovada_por, valores:{chave: inteiro}}]}` | `financeiro`, `juridico`, `administrador` |
| `POST /v1/admin/config/versoes` | `{valores:{chave: inteiro}, motivo}` | `{id, numero, status: "aguardando_aprovacao"}` | `financeiro`, `administrador` |
| `POST /v1/admin/config/versoes/{id}/aprovacao` | `{motivo}` | `{status: "vigente"}` | `administrador`; `422` se for quem criou |
| `POST /v1/admin/config/versoes/{id}/reversao` | `{motivo}` | `{id, numero}` (nova versão copiando a antiga, aguardando aprovação) | `financeiro`, `administrador` |

O backend valida `minimo`/`maximo` de cada chave, a aprovação por outra pessoa (`criada_por <> aprovada_por`), a vigência
agendada e que a versão aprovada é imutável. O painel mostra os limites que a API manda e não guarda valor nenhum.

### F7.6 Auditoria

| Método e caminho | Corpo | Resposta | Papel |
|---|---|---|---|
| `GET /v1/admin/auditoria?acao=&ator=&de=&ate=&pagina=` | — | `[{id, ocorrida_em, ator, acao, entidade, motivo, hash}]` | `seguranca`, `juridico`, `dpo`, `administrador` |
| `POST /v1/admin/auditoria/verificar-cadeia` | — | `{ok, verificadas, primeira_quebra_id}` (grava `auditoria.cadeia_verificada`) | `seguranca`, `juridico`, `dpo`, `administrador` |

Depende da cadeia de hash da auditoria (N16 em `docs/modelo-de-dados.md`), hoje uma proposta.

## Pendências para ligar de verdade

1. Backend: implementar os endpoints acima e a autenticação da equipe (Supabase Auth + papel em `equipe`), com MFA para
   a equipe antes de produção (decisão do João).
2. Painel: implementação HTTP de `ApiAdmin`, paginação, e o botão de aprovação da segunda pessoa na disputa.
3. Deploy do painel (Flutter Web build) e CORS: pedem o OK do João.
4. Se o tema do app mudar, copiar de novo para `admin/lib/tema/` (ou extrair um pacote compartilhado).
