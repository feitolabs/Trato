# Roteiro de aceitação — o que prova que funciona

Regra: "corrigido" só vale com **teste automático verde** ou **teste no ambiente real com resultado anotado**.
Estado em 04/11/2026: backend 1.299 testes passando; app `flutter analyze` limpo, goldens regenerados.

| Fluxo | Prova automática (backend) | Falta provar no ambiente real |
|---|---|---|
| Conta, CPF único, `/me` | `test_cpf_cadastro`, `test_api_app` (`test_me_*`) | cadastro + e-mail de confirmação no celular |
| Alternar Cliente/Profissional | `test_dois_papeis` | troca de tela no app, os dois papéis |
| Verificação do profissional | `test_divergencias_envio`, `test_admin_fluxos` | envio de fotos pela câmera + aprovação no painel |
| Pedido (criar, listar, cancelar) | `test_api_pedidos` | criar pedido no app real |
| Orçamento (enviar, limites, 1 por pedido) | `test_api_app` (`test_*orcamento*`) | enviar do app do profissional |
| Aceitar orçamento, contrato | `test_aceitar_orcamento_cria_contrato`, `test_taxa_congelada_*` | aceite no app |
| Pagamento, idempotência, taxa e líquido | `test_fluxo_pagamento_e2e`, `test_fix_dinheiro`, `test_pagamentos_*` | cobrança Stripe **modo teste** ponta a ponta |
| Check-in, check-out, conclusão, liberação | `test_fluxo_check_in_check_out_e_conclusao`, `test_rotinas` | com GPS e câmera reais |
| Disputa, reembolso, retrabalho, garantia | `test_disputa_*`, `test_api_disputa_retrabalho` | decisão pelo painel admin |
| Avaliação (só depois de concluir) | `test_avaliacao_*` | no app |
| Mensagens (mascara contato antes do contrato) | `test_mensagens_*` | no app |
| Notificações | `test_notificacoes_*` | push no aparelho |
| Painel admin (papéis, categorias, cidades, usuários, config) | `test_admin_*`, `integracao/test_admin_postgres` | login e cliques no painel |
| Segurança (RLS, acesso a pedido alheio) | `test_estranho_nao_ve_o_pedido`, `harness/teste_real_rls.py` | rodar `teste_real_rls.py` com as chaves |

## Decisão registrada nesta rodada

O papel `administrador` tem alçada total (commit "autonomia total"). Quatro testes antigos
cobravam o contrário e foram atualizados: administrador agora abre documento (ainda exige motivo e grava
auditoria); `/repasses` (relatório, GET) e `/travar-saque` (só bloqueia) são rotas permitidas.
Os outros papéis (segurança, financeiro, mediador, atendente, moderador) continuam recebendo 403.

## Sem dado de exemplo

- O app abre sempre na API real. O modo demo só liga em **debug** (`kReleaseMode` bloqueia em produção).
- Os arquivos `*_fake.dart` e `dados_exemplo.dart` ficam só como apoio de teste; nenhum build de produção os usa.
- **Banco (Supabase "Trato")**: limpeza feita em 04/11/2026 com o OK do João (22 pedidos e dependentes, categoria e
  config nº 1 de teste, 2 contas de teste, 15 arquivos do Storage). Restam 2 contas `@example.test` (administrador e
  financeiro), autoras da config vigente nº 2; apagá-las exige reatribuir a autoria (decisão pendente).
- **Não use `docs/teste-real-banco-limpeza.sql`**: ele apaga todos os usuários, a equipe e os pedidos, sem filtro.

## Rodada de testes de 04/11/2026 (o que foi executado de verdade)

| Item | Resultado |
|---|---|
| Stripe modo teste (API real): cobrança, idempotência, cartão 4242, valor, consulta, estorno parcial, webhook assinado válido/alterado/errado/antigo | 11 de 11 OK |
| App no emulador Android (APK debug, API real): splash, onboarding, login (validação de campos vazios), escolha contratar/trabalhar, sem dado de exemplo | OK; **login e cadastro reais não testados** (exigem conta real) |
| Painel admin no navegador (backend local, login de teste local): login por papel, recusar sem motivo/motivo curto/ok, aprovar, fila, auditoria | OK; trilha de auditoria conferida na API |
| Categorias, cidades e status de usuário | **sem nenhum teste antes**; 8 testes novos em `backend/tests/integracao/test_admin_catalogo_postgres.py` (Postgres local descartável) |
| Achado 1 | Excluir categoria dava **500** no banco real: `service_role` sem `DELETE` em `categorias`/`categoria_perguntas`. Migration `20261104120000_admin_catalogo_delete.sql` criada, **não aplicada** (aguarda OK) |
| Achado 2 | Bloquear usuário exigia só `usuarios_buscar`: qualquer atendente com busca bloqueava contas. Agora exige `usuarios_status` (só administrador); botão some no painel dos outros papéis |

**Não executado:** RLS/Storage no Supabase real (`teste_real_rls.py`, precisa de 2 contas de teste), push/SMS/e-mail
(sem provedor), iPhone (sem Mac), build release do app, cadastro/login/pedido/pagamento pelo app com conta real.

## Rodada 2 (04/11/2026): app no emulador, como cliente e como profissional

Pilha **local** (`harness/subir-pilha-local.py`): Postgres descartável com todas as migrations, o backend de produção
(`criar_app_da_config`), pagamento "fake" e um login compatível com o Supabase. Nada disso toca o Supabase nem o Stripe reais.

Percorrido de verdade no emulador Android: login do cliente, categorias reais, novo pedido, lista de pedidos, perfil do
cliente, "Sair", login do profissional, alternar para modo profissional, pedidos abertos, orçamento (conta e taxa do backend),
orçamentos recebidos, aceite, pagamento (R$ 170,00 + taxa R$ 12,75 = R$ 182,75), "Aguardando confirmação", webhook assinado,
"Serviço em execução".

| # | Defeito encontrado | Correção |
|---|---|---|
| 1 | Criar pedido falhava ("Algo deu errado"): a chave de idempotência levava o nome do serviço ("Orçamento geral", com ç) num cabeçalho HTTP | chave só ASCII (`repositorios_api.dart`) e `ClienteApi` limpa qualquer chave; teste `pedido_chave_idempotencia_test.dart` |
| 2 | A lista de pedidos não atualizava depois de criar | `Carregador.atualizarQuando` + `RotasTrato.pedidosMudaram` |
| 3 | "Aceitar orçamento" parecia morto: o aviso da caixa "li o escopo" ficava fora da tela | mensagem visível + 2 testes |
| 4 | "Fora do escopo" e "Cancelamento" apareciam em branco | blocos sem texto não aparecem |
| 5 | Sobras de mock: ID de cidade fixo, "Belo Horizonte" fixo e categorias do "protótipo" como reserva | removidos |

**Ainda a corrigir (vistos, não corrigidos):** a tela do profissional não confirma o envio do orçamento e continua oferecendo
"Fazer orçamento"; "Bairro" mostra o nome da cidade; bloco "[Mapa]" é marcador; texto "Recebendo por mais ." truncado;
o cartão do orçamento diz "total R$ 170,00" e o cliente paga R$ 182,75 (taxa somada); o onboarding reaparece a cada abertura
mesmo com login guardado.

**Não percorrido nesta rodada:** agenda, check-in/check-out (câmera e GPS), conclusão e liberação, avaliação, chat,
disputa, cadastro de profissional pelo app, login com CPF/telefone, Google/Apple, push.

## Rodada 3 (04/11/2026): o serviço de ponta a ponta no emulador

Percorrido de verdade, com a pilha local (`harness/subir-pilha-local.py`, agora com Storage local e `adb reverse`):
pedido → orçamento → aceite → pagamento → webhook → **marcar visita → check-in (foto, GPS, código) → check-out (foto final,
código) → cliente confirma → avaliação → "Finalizado" → chat**. Dinheiro conferido ao centavo: cliente pagou R$ 182,75,
taxa R$ 12,75, R$ 170,00 a liberar, R$ 0,00 retido.

| # | Defeito encontrado e corrigido | Prova |
|---|---|---|
| 6 | **Check-in impossível:** o invólucro do aparelho marcava "Feito" mas o envio ia sem foto nem posição; "A 0 m do endereço" era inventado | `check_in_captura_test.dart` |
| 7 | **Check-out inexistente:** a `CheckOutTela` nunca era aberta e o repositório nem tinha o serviço; sem ele o dinheiro não é liberado | item "Concluir serviço (check-out)" + `check_in_captura_test.dart` |
| 8 | `CarregadorTela` quebrava no debug (`setState` devolvia Future): "Tentar de novo" e atualização automática não funcionavam | `agenda_atualiza_test.dart` |
| 9 | Agenda mostrava o estado ("Pago e retido") no lugar do horário, selo sempre "Agendado", não atualizava | `pedido_janela_test.dart`, `agenda_atualiza_test.dart` |
| 10 | Seletores de data e hora em inglês | `MaterialApp` em pt-BR |
| 11 | Menu de ações estourava 14 px e cortava "Atender retrabalho" | menu rolável |

**Ainda a corrigir (vistos, não corrigidos):**
- Tela de conclusão mostra **"[Foto antes] [Foto depois]"** como marcadores: o cliente não vê as fotos do profissional (falta URL assinada de leitura).
- Texto "Como foi o serviço do **O** profissional?" / "O O profissional" e "Profissional" genérico no chat: o pedido não traz o nome do profissional.
- Faixa "Aguardando confirmação do pagamento" logo depois de o cliente confirmar o serviço (texto errado para o momento).
- Aviso do chat diz "Telefones e e-mails são ocultos", mas depois do contrato o backend libera (por regra): texto não bate com o comportamento.
- Tela do cliente "em execução" continua mostrando "Código de início" e a linha do tempo parada após o check-out.
- Botão da Agenda diz "Fazer check-in" com o serviço já em andamento.
- Menu de ações lista tudo (disputa, retrabalho) em qualquer estado, em vez de usar `acoes_permitidas` do backend.
- Foto de chegada aceita "Escolher da galeria" (enfraquece a prova de presença): decisão de produto.
- Sem confirmação visível após o profissional enviar orçamento; "Bairro" mostra a cidade; "[Mapa]" é marcador; onboarding reaparece a cada abertura.
- `dart format` reformatou `app/lib/telas/fluxo/rotas.dart` inteiro (diff de ~300 linhas sem mudança de comportamento).

**Não percorrido:** disputa, retrabalho/garantia, aditivo, nota de materiais, cadastro de profissional pelo app, login por CPF/telefone,
Google/Apple, push, iPhone, e o painel admin contra o Supabase real.
