# Backend: notificações, conversas e agendador

Pacotes novos: `backend/src/trato/notificacoes/` e `backend/src/trato/agendador/`.
Nada aqui chama e-mail, SMS ou push de verdade: os provedores ficam atrás de interface, com fake
para teste e adaptador pronto, **desligado** até o João preencher o `.env`.

## O que foi entregue

| Peça | Onde |
|---|---|
| Serviço que transforma evento do domínio em notificação (preferências, idempotência, deep link, reenvio) | `notificacoes/servico.py`, `eventos.py` |
| Canais `app`, `push` (FCM e APNs), `email` (SMTP), `sms` (só confirmar celular) e fakes | `notificacoes/canais.py` |
| Gancho que liga as transições do pedido às notificações | `notificacoes/ganchos.py` |
| Rotas v1 | `notificacoes/rotas.py` |
| Conversas, leitura e gancho `Mascarador` | `notificacoes/mensagens.py` |
| Agendador: ciclo, trava, registro por chave, executor | `agendador/` |
| Migration (**não aplicada**) | `supabase/migrations/20261029040000_notificacoes_dispositivos_agendador.sql` (+ rollback) |

## Rotas (todas exigem login; cliente ou profissional)

| Rota | O que faz |
|---|---|
| `GET /v1/notificacoes?nao_lidas=&limite=` | Caixa de entrada (canal `app`), mais nova primeiro. Substitui a versão simples de `rotas_app.py` |
| `POST /v1/notificacoes/{id}/lida` | Marca como lida. Idempotente; de outra pessoa = 404 |
| `GET/PUT /v1/notificacoes/preferencias` | Categoria x canal (`app`, `push`, `email`). O `PUT` troca só o que veio. SMS e WhatsApp são recusados (422) |
| `POST /v1/dispositivos` | Registra o token de push (`android`, `ios`, `web`). Mesmo token em outra conta passa para quem registrou |
| `GET /v1/conversas` | Minhas conversas, com não lidas e prévia da última mensagem |
| `POST /v1/mensagens/{id}/lida` | Quem recebeu marca como lida (o autor não) |
| `POST /v1/conversas/{id}/lida` | Marca tudo que a outra parte mandou |

Enviar e listar mensagens de um pedido continuam em `GET/POST /v1/pedidos/{id}/mensagens`
(`api/rotas_app.py`, já existiam).

### Ligação no app (uma linha)

`backend/src/trato/api/app.py`, em `instalar()`: `registrar_rotas(app, contexto)` **antes** de
`criar_router()`. É antes de propósito: o `GET /v1/notificacoes` daqui vale sobre o antigo. Com
`contexto`, já liga os serviços e o gancho (`Contexto.apos_transicao`). Nenhum outro arquivo
existente foi alterado.

## Eventos

`orcamento.recebido`, `orcamento.aceito`, `pagamento.confirmado`, `agenda.lembrete`,
`agenda.codigo_inicio`, `execucao.confirmar_conclusao`, `execucao.aditivo_pendente`,
`disputa.aberta`, `disputa.respondida`, `disputa.decidida`, `disputa.lembrete_resposta`,
`garantia.retrabalho`, `avaliacao.recebida`.

- **Pelo gancho das transições** (automático): aceite, pagamento confirmado (só depois do webhook,
  D13), código de início (ao confirmar a agenda), conclusão para confirmar (check-out), disputa
  aberta/decidida/acordo e retrabalho.
- **Pelo agendador**: lembretes de confirmação, resposta de disputa e aditivo (`trato.rotinas`), e
  lembrete de agendamento.
- **Chamar direto** (`servico.notificar(...)`) de onde acontece, ainda **sem chamador** nas rotas:
  `orcamento.recebido`, `disputa.respondida`, `avaliacao.recebida`. Quem mexe nessas rotas deve
  adicionar a chamada (ver "Pendências").

Regras: preferência desligada não cria a notificação; evento `essencial` entra sempre na caixa
`app` (push e e-mail continuam obedecendo); a `chave` repetida não duplica (no Postgres, com
trava `pg_advisory_xact_lock`, vale para duas instâncias da API); canal externo desligado ou sem
destino nem cria linha; falha de envio deixa `enviada_em` vazio e o agendador reenvia (só o que
tem menos que `TRATO_NOTIF_REENVIO_JANELA_HORAS`). O código de início **nunca** vai no texto nem
no `dados`: só o deep link para a tela. Textos seguem a D13.

## Configuração (`.env`; só `.env.example` vai ao git)

Tudo opcional. Sem nada preenchido só o canal `app` funciona.

| Variável | Para quê |
|---|---|
| `TRATO_NOTIF_DEEP_LINK_BASE` | Esquema do app (`trato://`) |
| `TRATO_NOTIF_PADRAO_APP/PUSH/EMAIL` | Canais ligados para quem nunca mexeu nas preferências |
| `TRATO_NOTIF_REENVIO_JANELA_HORAS`, `..._LOTE` | Até quando e quantas pendentes reenviar por ciclo |
| `TRATO_NOTIF_PUSH_ATIVO`, `FCM_PROJETO_ID`, `FCM_CREDENCIAIS_ARQUIVO` | Push por FCM |
| `TRATO_NOTIF_APNS_ATIVO`, `APNS_CHAVE_ARQUIVO`, `APNS_CHAVE_ID`, `APNS_TIME_ID`, `APNS_BUNDLE_ID` | Push direto por APNs (opcional) |
| `TRATO_NOTIF_EMAIL_ATIVO`, `SMTP_HOST`, `SMTP_PORTA`, `SMTP_USUARIO`, `SMTP_SENHA`, `EMAIL_REMETENTE` | E-mail por SMTP |
| `TRATO_NOTIF_SMS_ATIVO`, `SMS_PROVEDOR_URL`, `SMS_PROVEDOR_CHAVE`, `SMS_MAX_ENVIOS_POR_CELULAR` | SMS de confirmação de celular |
| `TRATO_AGENDADOR_INTERVALO_SEGUNDOS` | Intervalo do ciclo (padrão 60) |
| `TRATO_AGENDADOR_DIAS_CONCLUIDOS_MONITORADOS` | Quantos dias um pedido concluído ainda é vigiado (liberação) |
| `TRATO_AGENDADOR_LEMBRETE_AGENDA_HORAS` | 0 = sem lembrete de agenda; N = avisa N horas antes |

## O que depende do João

1. **Push (FCM/APNs).** Criar o projeto no Firebase (grátis), baixar a conta de serviço (JSON) e
   guardar **fora do git**; para iOS, conta Apple Developer, chave APNs (`.p8`), Key ID e Team ID.
   O adaptador está pronto mas falta o *ponto de integração* que lê o JSON e gera o token OAuth2
   (`token_acesso`) e o transporte HTTP: hoje são parâmetros injetados em `PushFcm`/`PushApns`
   (`canais_da_config` deixa o push **indisponível** sem eles). Depende também do app pedir
   permissão e mandar o token em `POST /v1/dispositivos`.
2. **E-mail.** Escolher o provedor (SMTP de um serviço transacional) e criar remetente/domínio
   (SPF/DKIM). Além disso falta decidir **de onde sai o endereço**: o `ResolvedorEmail` padrão
   devolve nada (e-mail é dado pessoal e o app não o expõe); ligar ao `auth.users` exige OK.
3. **SMS (D14).** Só confirmação do celular no cadastro. Decidir o provedor (P11: Zenvia/Comtele),
   contratar e ligar o Send SMS Hook do Supabase Auth ao `ServicoSmsConfirmacao`. CAPTCHA antes do
   envio e validade de 5 min do código ficam no Auth; o serviço aqui só limita os envios por
   celular. WhatsApp: V1.
4. **Aplicar a migration** `20261029040000_...` no Supabase (tabelas `dispositivos_push` e
   `agendador_execucoes`). **Exige o seu OK**; nada foi escrito no banco real. Rollback em
   `supabase/rollback/notificacoes_dispositivos_rollback.sql`.
5. **Prazos das rotinas.** Sem configuração publicada o agendador não inventa número: liberação
   por prazo e lembretes ficam desligados até `prazo_liberacao`, `lembrete_*` etc. existirem na
   configuração (hoje só validade, pagamento, tolerância, confirmação, resposta/decisão de disputa
   e janela de congelamento vêm da `ConfigApi`; ver P1).

## Mensagens e o `Mascarador`

`Mascarador` (`notificacoes/mensagens.py`) é a interface que a sessão de segurança implementa;
`MascaradorSimples` reaproveita `persistencia.conversas.mascarar_contatos`. Hoje ele é aplicado
na **prévia** de `/v1/conversas`; o mascaramento ao **gravar** a mensagem continua no repositório
(`ConversasPostgres.enviar`). Para trocar de verdade: injetar o novo `Mascarador` em
`ServicoMensagens` e fazer o repositório usá-lo.

## Agendador

```bash
# No .env: TRATO_PERSISTENCIA=postgres e DATABASE_URL (e as demais do docs/api-persistencia.md)
cd backend
.venv/Scripts/python -m trato.agendador            # laço contínuo (Ctrl+C / SIGTERM para)
.venv/Scripts/python -m trato.agendador --uma-vez  # um ciclo e sai (para cron)
```

Cada ciclo: pega a trava, lê os pedidos ativos, pergunta a `trato.rotinas.rotinas_do_instante`
o que fazer e executa (transição como `SISTEMA`, liberação no ledger, lembrete como notificação),
marca cada chave em `agendador_execucoes`, reenvia notificações pendentes e solta a trava.

- **Trava:** `pg_try_advisory_lock` numa conexão dedicada (solta sozinha se o processo morrer).
  Duas instâncias ao mesmo tempo: a segunda devolve `travado=True` e espera o próximo ciclo. Em
  testes e processo único há `TravaEmMemoria`.
- **Idempotência em duas camadas:** chave da rotina em `agendador_execucoes` e executores que já
  são idempotentes (transição confere o estado; ledger recusa a mesma chave; notificação tem
  chave). Se o processo cair entre executar e marcar, o ciclo seguinte repete sem duplicar efeito.
- **Relógio:** `Agendador(..., relogio=...)`; nada lê a hora do sistema.
- **Como serviço (sem deploy aqui):** um processo único por ambiente. Exemplos para quando o João
  escolher onde hospedar: `systemd` (`ExecStart=.../python -m trato.agendador`,
  `Restart=always`), um serviço "worker" no Render/Railway/Fly com o mesmo comando, ou cron a cada
  minuto com `--uma-vez`. Pode rodar mais de uma réplica: a trava impede o duplicado.

### Limitações conhecidas

- A origem dos pedidos (`FonteContexto`) usa o `Contexto`. Em modo `postgres`, **ledger,
  disputas e garantias ainda são em memória** (fábrica; F3.5 refeita no caminho A, D15). Logo a
  liberação por prazo e as rotinas de disputa só funcionam de verdade quando essas tabelas
  existirem; as transições por prazo (expirar, concluir por prazo) e os lembretes já usam o banco.
- `aditivo_pendente_desde` e `urgente` não existem nos repositórios: lembrete de aditivo e a
  validade de pedido urgente ficam sem dado até alguém fornecê-los.
- Lembrete de decisão de disputa é da equipe (sem destinatário individual): fica para o painel
  admin.

## Testes

```bash
cd backend
.venv/Scripts/python -m pytest -q tests/test_notificacoes_servico.py tests/api/test_notificacoes_api.py tests/api/test_agendador.py
.venv/Scripts/python -m pytest -q tests/integracao/test_notificacoes_postgres.py   # precisa de pgserver
```

Cobrem: preferências desligadas, idempotência (inclusive 8 threads no Postgres), reenvio depois de
falha e fora da janela, token inválido, adaptadores desligados por padrão, SMS só para
confirmação com limite, rotas e isolamento entre pessoas, conversas e leitura, rotinas reais com
relógio injetado e **duas instâncias do agendador ao mesmo tempo** (memória e advisory lock no
Postgres local).
