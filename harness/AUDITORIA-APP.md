# Auditoria do app Trato — 15/11/2026 (v0.1.26)

Primeira parte: investigação (nada alterado). **Atualização no fim do arquivo: o que foi corrigido na branch `feature/correcoes-auditoria-app`.**

## Como foi feito

- Leitura do código do app (`app/lib`) e das rotas do backend (`backend/src`), tela por tela.
- Cruzamento: toda rota que o app chama × rota que existe no servidor de produção (`trato.fly.dev`).
  Resultado: as 61 rotas chamadas existem (nenhuma dá 404). O problema não é rota faltando; é o que o app **não manda** ou **não chama**.
- Consultas de leitura no Supabase "Trato" (contagens e lista de migrations) e em `/auth/v1/settings`.
- `flutter analyze`: 0 problemas em `lib/` (29 avisos só em testes).
  `flutter test`: 574 testes + 166 goldens passam. Fora: `navegacao_sem_placeholder_test.dart` (derruba a VM nesta máquina, já registrado).
- **Não feito:** teste ponta a ponta com login real (grava no banco de produção e no Stripe), testes do backend e painel admin.

## A. Não funciona hoje (prova no código ou no servidor)

| # | Problema | Prova |
|---|---|---|
| A1 | **O agendador não roda em produção.** Sem ele não há confirmação automática por prazo, expiração de pedido e de pagamento, lembretes, reenvio de notificação nem processamento de exclusão LGPD. | `fly.toml` só sobe o `uvicorn`; `PROGRESSO.md` linha 803 ("continua fora"); `agendador_execucoes` tem **0** linhas. |
| A2 | **Push não existe.** O app não tem `firebase_messaging` e nunca chama `POST /v1/dispositivos`. O backend tem FCM e APNs prontos. | `dispositivos_push` = **0** linhas. Só há atualização por consulta periódica com o app aberto. |
| A3 | **"Entrar com Google" e "Entrar com Apple" falham.** O botão sempre aparece (`provedorHabilitado` devolve `true`), mas o Supabase tem os dois desligados. | `GET /auth/v1/settings` → `google:false`, `apple:false`. Os builds do CI também não passam `GOOGLE_*_CLIENT_ID`. |
| A4 | **Cartão não abre em APK/IPA feito pelo CI.** O `build.yml` não passa `STRIPE_PUBLISHABLE_KEY`; `folha_cartao.dart` recusa sem ela ("Pagamento com cartão indisponível"). O `app/dart-defines.json` também não tem a chave e ainda aponta para o Render (`trato-wald.onrender.com`). | `.github/workflows/build.yml` linhas 54–57 e 92–95. |
| A5 | **Resposta do profissional à disputa se perde.** O app manda `POST …/disputa/resposta` **sem corpo**; o backend também não aceita corpo. Texto, evidências e a solução proposta (reembolso parcial, retrabalho) são coletados na tela e descartados. O mediador decide sem ouvir o profissional. | `servicos_api.dart:820`; `rotas_pedidos.py:556`. |
| A6 | **Fotos do "Relatar problema" e do pedido de retrabalho são descartadas.** O cliente tira as fotos, mas o app envia `fotos: []`. O backend aceita fotos. | `repositorios_api.dart:482–485` e `:622`; `EnvioRelato` nem tem campo de fotos. |
| A7 | **Retrabalho nunca termina pelo app.** O app só chama a etapa `aceitar`. A data/hora e a mensagem que o profissional digita são ignoradas. `iniciar` e `resolver` nunca são chamadas. | `servicos_api.dart:844`. |
| A8 | **Não dá para cancelar pedido ou contrato.** O backend tem a ação `cancelar`; o app não tem botão nem chamada. A FAQ manda "ver as opções" no pedido, mas elas não existem. Remarcar: o backend responde 501 e o app não tem tela. | `grep cancelar` só acha botões de formulário. |
| A9 | **Notificações nunca ficam "lidas".** `marcarLida` e `marcarTodasLidas` não fazem nada. O backend tem `POST /v1/notificacoes/{id}/lida`. O contador não zera. Não há preferências de notificação (backend tem `PUT /v1/notificacoes/preferencias`). | `notificacoes/servico_repositorio.dart:44-48`. |
| A10 | **Central de ajuda: dois botões mortos.** "Falar com o suporte" e "Relatar um problema" recebem `null` nos 3 pontos de entrada, então ficam desabilitados. A FAQ é texto fixo no app. Não há rota do usuário para abrir chamado (o backend só lista chamados no painel). | `rotas.dart:981, 1014`; `recuperar_senha_tela.dart:38`. |
| A11 | **Caixa "avisos pelo WhatsApp" no cadastro não grava nada** e não existe provedor de WhatsApp/SMS (P11). O app promete algo que não entrega. | `criar_conta_tela.dart:44, 277`: `_avisosWhatsapp` nunca é lido. |
| A12 | **Check-in/check-out sem internet falha.** A fila offline (`FilaOffline`) nunca é criada; mesmo criada, seria só em memória. Fase 6.8 do contexto não está ativa. | `grep FilaOffline`: só a interface e a classe. |
| A13 | **"Cliente não encontrado" é só uma mensagem no chat.** Não registra a ausência (a ação existe no backend). Sem efeito de prazo ou reembolso. | `repositorios_api.dart:1797`. |
| A14 | **"Outro motivo" na disputa vira `abandono`.** O motivo `nao_compareceu` existe no backend e não tem opção na tela. | `repositorios_api.dart:47–53` e `:482`. |

## B. Lacunas de produto (decisão sua)

- **B1. O profissional não tem como receber o dinheiro.** Sem Stripe Connect, sem chave Pix, sem saque (D15). "Liberado" é só lançamento no ledger. A Carteira é extrato. Depende de P7 (parceiro e custódia). Sem isso o piloto não paga ninguém.
- **B2. SOS e compartilhar atendimento** (Fase 5.9) não existem. "Contatos de confiança" salva contatos que nenhuma função usa.
- **B3. Profissional não avalia o cliente.** O backend aceita (`profissional_para_cliente`); o app não tem tela.
- **B4. Sem trocar senha ou e-mail com a conta aberta** (só recuperação por e-mail). Formas de pagamento salvas escondidas.
- **B5. Pix:** o pagamento do pedido oferece Pix (o backend sempre lista `pix` e `cartao`), mas o aditivo força cartão porque "o Stripe da conta não tem Pix". Se o Pix não está ativo na conta Stripe, escolher Pix no pagamento principal tende a falhar. Conferir.
- **B6. Prazo de liberação = 0 dias** (decisão de 31/10), enquanto `contexto.md` ainda fala em 7 dias. Os textos do app estão coerentes com 0; o `contexto.md` está velho.

## C. Dados fixos e inconsistências de tela

- **Perfil do profissional (cliente vê):** sempre 3 quadrinhos "Trabalho 1/2/3" mesmo sem portfólio, e corta em 3 se houver mais. "Serviços" repete os títulos do portfólio. "No Trato desde" cai para o **ano atual** se o dado faltar. "Responde em" é "—". Distância sempre 0 (a tela esconde). As fotos do portfólio são buscadas uma a uma, em série.
- **Novo pedido:** faixas de preço (R$ 100–300, R$ 300–800), prazos ("Esta semana", "Sem pressa") e a pergunta de quantidade estão fixos no app (`repositorios_catalogo_api.dart:225–244`). A regra do projeto manda isso para tabela de configuração.
- **Textos fixos no app** (`TextosPadraoTelas`): motivos de disputa, soluções, critérios de avaliação, respostas rápidas do chat, "o que a garantia cobre".
- **Gorjeta:** escondida, mas o código e o texto de recusa continuam.
- **Código de demonstração dentro do app de produção:** `ServicoContaFake` ("Mariana Alves"), `FolhaCartaoFake`, `fake://`, galeria (`--dart-define GALERIA`).
- **Chave e URL no código** (`main.dart:44–46`): URL do Fly e a chave publicável do Supabase como valor padrão. É chave pública, mas a regra 3/4 manda `.env`/defines.
- **Textos jurídicos** são rascunho com aviso; `privacidade@trato.app.br` precisa existir; o texto próprio de cancelamento depende de você.
- **Lista de notificações e extrato** sem paginação (extrato limitado a 50).
- **Backend** responde `versao: 0.1.0` em `/saude` (app está em 0.1.26).
- **Documentação desatualizada:** `docs/STATUS-MVP.md` e `docs/placeholders.md` ainda dizem "Demo" e "sem rota" para contraproposta, conversa antes de contratar, busca e agenda, que já estão ligadas. `app/test/golden/failures/` é resto de 14/11 (os goldens passam hoje).

## D. O que está bom

- Todas as rotas chamadas existem em produção.
- Contraproposta, conversa antes de contratar, aditivo (cartão), nota de materiais, perguntas por categoria, favoritos, endereços, LGPD (consentimentos, exportar, excluir) estão ligados à API.
- Nenhum valor de dinheiro, taxa ou prazo calculado no app; prazos vêm de `/v1/config/publica`.
- Migrations locais batem com as tabelas do Supabase.

## E. Ordem sugerida de correção

1. **Pequenas e seguras (só app/backend, sem decisão):** A5, A6, A7, A9, A10 (ligar ao suporte), A11 (gravar ou tirar a caixa), A14, A3 (esconder Google/Apple até ligar no Supabase), A4 (passar a chave no CI).
2. **Operação:** A1 (segundo processo do agendador no Fly), A2 (push: precisa de projeto Firebase e chaves, com seu OK).
3. **Funcionalidade nova:** A8 (cancelar), A12 (offline), A13 (ausência), B3 (avaliar cliente), B2 (SOS).
4. **Decisão sua:** B1 (como pagar o profissional), B5 (Pix), textos jurídicos.

## F. Situação depois das correções (15/11/2026)

| Item | Situação |
|---|---|
| A1 agendador | Corrigido no código (`TRATO_AGENDADOR_EMBUTIDO=true` no `fly.toml`). **Falta o deploy** e conferir `agendador_execucoes`. |
| A2 push | **Não feito.** Precisa de projeto Firebase, `google-services.json`/`GoogleService-Info.plist`, chave do FCM no servidor e OK. |
| A3 Google/Apple | Corrigido: o botão só aparece se o Supabase tem o provedor ligado. Para usar: ligar no Supabase e passar os client ids. |
| A4 Stripe no CI | Corrigido no workflow. **Falta cadastrar `vars.STRIPE_PUBLISHABLE_KEY` no GitHub.** |
| A5, A6, A7 | Corrigidos (disputa, fotos, retrabalho). |
| A8 | Cancelar pedido: corrigido. Remarcar: não (o servidor responde 501 de propósito). |
| A9 | Corrigido (marcar como lida). Preferências de notificação: não feito. |
| A10 | Parcial: e-mail de suporte pela configuração (`TRATO_SUPORTE_EMAIL`, vazio hoje, então o botão não aparece) e "Relatar um problema" vai aos serviços. Chamado dentro do app pede tabela nova. |
| A11 | Corrigido (caixa removida). |
| A12 | Corrigido (fila em disco e reenvio). |
| A13 | Não feito: não existe ausência do cliente na máquina de estados. Precisa de regra sua. |
| A14 | Corrigido. |
| B1 a B6 | Decisões suas (D13, D15, P7); B3 (avaliar o cliente) corrigido. |
| C | Dados fixos do Novo pedido e do perfil continuam; o retrabalho deixou de usar prazo fixo. |
