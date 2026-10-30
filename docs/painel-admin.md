# Painel administrativo (web)

> Projeto Flutter Web em `admin/` (D13: painel admin é web responsivo; não existe app Ops).
> Roda com **dados de exemplo** (`ApiFake`) ou com a API admin real (`ApiAdminHttp`), escolhida por `--dart-define`
> (seção "Ligação com a API real"). O contrato do backend está em `docs/api-admin.md`.

## Como rodar

```bash
cd admin
flutter pub get
flutter run -d chrome
flutter test
flutter analyze
```

No exemplo, o papel vem do começo do e-mail (`financeiro@teste.local` entra como `financeiro`) e a senha só precisa ter
8 caracteres ou mais. Não há senha real em lugar nenhum. Para usar a API real, veja "Ligação com a API real".

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

## Ligação com a API real

O contrato que o backend cumpre hoje está em `docs/api-admin.md`. O painel foi alinhado a ele (o lado do painel
mudou; `backend/` não). Implementação: `admin/lib/dados/api_http.dart` (`ApiAdminHttp`).

### Como escolher a API

Por `--dart-define` (nada vai para o git; `admin/.env.example` só lista os nomes):

```bash
flutter run -d chrome --dart-define=ADMIN_MODO=api --dart-define=ADMIN_API_URL=https://api... --dart-define=ADMIN_SUPABASE_URL=https://xxxx.supabase.co --dart-define=ADMIN_SUPABASE_ANON_KEY=<chave pública>
```

Sem `ADMIN_MODO=api`, ou com algum valor faltando, o painel usa os dados de exemplo (`ApiFake`). Só a chave
**pública** (anon) entra no painel; a chave de serviço nunca. O token da sessão fica só em memória (não vai para
disco, URL nem log) e some ao sair.

### Mapa tela -> rota

| Tela | Rotas usadas | Observações do alinhamento |
|---|---|---|
| Login | Supabase `POST /auth/v1/token?grant_type=password` e `GET /v1/admin/eu` | O backend não tem sessão própria; a rota `/eu` agora existe (ver `docs/painel-integracao.md`). |
| Verificação | `GET /verificacoes`, `POST /verificacoes/{id}/documentos/{doc}/url`, `POST /verificacoes/{id}/decisao` | Corpo da decisão é `{aprovar, motivo}`. A URL assinada abre em outra aba e nunca é mostrada. Sem cidade/categoria na API: o painel mostra o nível pedido. |
| Disputas | `GET /disputas` + `GET /disputas/{pedido_id}`, `POST .../decisao`, `POST .../aprovacao` | O id da disputa é o `pedido_id`. **Sem e-mail da segunda pessoa:** acima da alçada a disputa fica "Aguardando segunda pessoa" e outra conta (líder/administrador) aprova no próprio login. Parcial envia `valor_cliente_centavos`. |
| Pagamentos | `GET /pagamentos`, `GET /pagamentos/resumo` | Só `GET`. Cartões: confirmado, reembolsado, em andamento (`retido_centavos`), divergências. |
| Busca | `GET /usuarios`, `POST /usuarios/{id}/dados-pessoais`, `GET /pedidos` | A lista não traz e-mail nem CPF mascarados; o botão "Revelar" mostra CPF, telefone e nascimento (sem e-mail). |
| Configurações | `GET /config/definicoes`, `/config/versoes` + `/{id}`, `POST /config/versoes` + `/enviar`, `/aprovar` + `/publicar`, `/reverter` | Propor = criar rascunho (a partir da vigente) e enviar. Aprovar = aprovar e publicar; se a publicação falhar (vigência agendada), a versão fica "Aprovada, falta publicar" com botão **Publicar**. `criada_por` é id, não e-mail. As faixas da taxa (`faixas`) ainda não têm tela. |
| Auditoria | `GET /auditoria`, `POST /auditoria/verificar-cadeia` | O filtro "Quem" usa `ator_id`. A lista não traz o hash da linha (some da tela); a verificação devolve íntegra ou o primeiro registro quebrado. |

Erros: 401 mostra "sessão acabou", 403 mostra a mensagem do backend (papel), 422 mostra o `detail`.

### O que falta no backend (não alterei `backend/`)

1. `GET /v1/admin/eu` -> `{id, nome, email, papel, alcada_centavos}`, lido da linha ativa em `equipe`. Sem ele o painel
   não sabe o papel e **o modo api não consegue entrar**. É a única rota que impede o uso.
2. Categorias: `GET /v1/admin/categorias` e `PUT /v1/admin/categorias/{id}` com `{ativa, motivo}` (papéis moderador e
   administrador). Hoje a aba mostra "Esta função ainda não existe no servidor."
3. Chamados de suporte: `GET /v1/admin/suporte/chamados` (atendente_n1/n2, lider_suporte, administrador). Idem.
4. Opcionais para melhorar a tela: `categoria`/`cidade` na verificação; `cpf_mascarado` e e-mail mascarado nas listas de
   usuários; nome (e-mail) de quem criou/aprovou a versão de configuração; `hash` na lista da auditoria.

## Pendências

1. Rota `/eu` e demais itens acima; depois testar o modo api contra o backend de verdade.
2. MFA da equipe antes de produção (decisão do João); paginação nas telas (hoje pedem 100 itens).
3. Deploy do painel (Flutter Web build) e CORS: pedem o OK do João.
4. Se o tema do app mudar, copiar de novo para `admin/lib/tema/` (ou extrair um pacote compartilhado).
