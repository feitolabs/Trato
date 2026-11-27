# Plano: Trato 100% dentro dos Termos v1.2

OK do João: até **04:00 de 26/11/2026**. Vale para código local e arquivos de banco. **Fora:** aplicar no banco, Stripe, push, deploy e API externa real (pedir à parte).

Meta: todas as cláusulas de `conferencia-v1.2.md` como CUMPRE (ou NÃO SE APLICA), considerando `termos-v1.2-ajustes.md`.

## Etapas
| # | Etapa | Cláusulas | Quem | Situação |
|---|---|---|---|---|
| 1 | Estorno por ausência, push, bugs do app, e-mails, MEI, 18 anos no app, avisos, avaliação, chat, Tratinhos | 7.7, 4.1, 11.2, 12.1, 13.4, 13.8, 15.2 | Backend, Flutter, Banco | Código local entregue, incluindo APP3 (25/11 22:50); falta revisão |
| 2 | Erros de pagamento | 5.8, 6.10, 6.11, 7.7 | Backend | Entregue em 25/11 22:30 (código local); testes novos conferidos; falta revisão |
| 2b | Avisos por e-mail, brecha do cadastro, idade no servidor, endereço no chat, exclusividade em memória e pg_local | 15.2, 4.1, 5.4, 13.8 | Backend | Entregue 25/11 23:41 (testes conferidos); exclusividade em memória vai com a etapa 5 |
| 3 | Revisão da Segurança (etapas 1 e 2) e correções | todas as acima | Seguranca | Banco: achados das duas revisões corrigidos em arquivo (25/11 23:4x); falta a Segurança reconferir (junto com a revisão do servidor) |
| 4 | Cancelamento, desistência e cliente ausente | 7.2-7.6, 7.9 | Backend, Flutter, Admin | Servidor, app e painel entregues (testes conferidos 26/11); filtro de privacidade em andamento; falta anexar comprovante de retenção pelo painel; repasse depende do Stripe |
| 5 | Exclusividade do cliente | 13.6, I.4 | Banco, Backend, Flutter | Servidor, app e botão do painel entregues no código local (testes conferidos); falta listar exclusividades no painel |
| 6 | Contestação, SAC com protocolo, suspensão, leitura de conversa | 8.7, 11.3, 11.8, 20, 25 | Admin (desenho), Banco, Backend, telas | SAC pronto no servidor e no app (testes conferidos); medidas de conta em andamento; painel de atendimento (ADM5) em andamento; falta conta bloqueada entrar no app; contestação de disputa (8.7) não iniciada |
| 7 | Demais itens da conferência (disputa, avaliações, dados, segurança, comprovante, Tratinhos) | 5.3, 5.7, 6.9, 8.2, 8.4, 9, 12, 13, 14 | todos | Banco em arquivo (DB5, não aplicado); app APP4 e APP5 entregues; rotas pedidas pelo app em Shared/termos-app5-api-para-backend.md; servidor e painel não iniciados |
| 8 | Conferência final cláusula por cláusula, texto v1.2 no app | todas | Seguranca, Scout, Mestre | Não iniciada; nenhum 100% antes dela |

## Dependem do João (bloqueiam o 100%)
- Campos em branco do documento (CNPJ, endereço, telefones, encarregado, links, itens entre colchetes, 17.6 com advogado).
- E-mails `@tratofeitolabs.com.br` recebendo.
- Repasse pelo Stripe (6.7, 5.8): desenho da conta e OK próprio.
- Aplicar banco, publicar backend e app: OK próprio.

## Decididas pelos Termos (João, 25/11: não perguntar o que o documento responde)
1. Medidas e contestações: pessoa da equipe com papel de análise (Analista, seção 2 e 20.2): mediador, líder de suporte, segurança, administrador.
2. 8.7: outro Analista é obrigatório no sistema, sem exceção. Falta de equipe é pendência de operação.
3. Contestação que muda a decisão com valor já repassado: compensação de valores futuros do profissional (8.6, 17.4). Não criar espera no repasse.
4. Conta suspensa ou bloqueada contesta pelo app (rota restrita) e pelo SAC (20.5).

Situação atualizada em 25/11 22:30.
5. Parcelamento volta no cancelamento pelo cliente antes do check-in e no reembolso total por disputa (6.10, 7.2, 7.4). Contestação de cartão aberta não segura estorno (o termo não prevê).

## Para o Backend na etapa 5 (do relatório DB3)
- Incluir `"*exclusividade_cliente.sql"` em `pg_local.py` depois de `"*moedas_saldo_e_estorno_validade.sql"`.
- Chamar `exclusividade_cliente_contratar` (após pagamento confirmado) e `_expirar`; mudar o estado do pedido na mesma transação; filtrar `pagador`; traduzir o erro do gatilho; registrar quem declarou a falha.
- Parar de oferecer a exclusividade paga pelo profissional.
- Contar a validade do pedido reaberto desde a reabertura.

## Para o Backend e o Admin (relatórios DB4 e APP3)
- 20.4: o aviso nunca é adiado, só o detalhe do motivo (`aviso_adiado` fica sempre falso).
- Conferir papel, atividade e alçada de analista e aprovador; nova decisão não move dinheiro sozinha.
- Gravar as definições de prazo em `config_definicoes`; incluir no `pg_local.py`, após DB1 e DB2: `*exclusividade_cliente.sql`, `*sac_chamados.sql`, `*medidas_conta.sql`, `*disputa_contestacoes.sql`.
- Incluir `avaliar_ate` e `prazo_encerrado` em `GET /v1/pedidos`.

## Autorização condicional (João, 25/11 à noite)
Palavras dele: "Quando terminar de deixar o app 100% cumprindo o termo, já pode aplicar, testar e verificar o app".
- Vale só **depois** da etapa 8 (conferência final) aprovada.
- Leitura adotada: aplicar as migrations no Supabase, publicar o backend, gerar o APK de teste, testar e verificar.
- Fora: Stripe real, lojas, merge na `main`, tag.

## Antes de ligar rotas novas (Segurança, REV-DB2)
- Papel do analista conferido no backend (RBAC) com teste.
- medidas_conta que não mudem `usuarios.status` precisam barrar a exclusividade no backend.
- Nunca forçar rollback da 223000 com exclusividade ativa.

## Pendente fora das etapas (relatório FIX-DISPUTA)
- 8.6: compensar reembolso de valor já liberado ao profissional (o ledger recusa hoje).
- `harness/subir-backend-teste.py` não liga o pagamento (decisão no painel de teste responde 503): DevOps.
- Decisões antigas do painel sem estorno: SELECT no relatório; conferir cada cobrança no Stripe antes de recuperar (exige OK).
- E-mail em produção (15.2): faltam secrets SMTP no Fly, domínio com SPF/DKIM, migration 20261107130000 conferida (relatório BE2). Faltam avisos de suspensão, encerramento e mudança dos Termos.
- Backend (relatório DB-FIX2): não enviar data de consentimento nem flag de 7 dias (o banco calcula); um só cancelamento por pedido; contestação de nota inteira não convive com a de item. Antes de aplicar: `supabase/consultas/pre_checagem_termos_v12.sql` (todos `presente=true`).
6. Check-in sem o pedido expresso, desistência em 7 dias: reembolso integral automático (7.2, 7.3, CDC art. 49).
- App (etapa 4): usar `POST /v1/pedidos/{id}/desistir` e `GET .../desistencia`; enviar `consentimento_execucao_imediata` na cobrança, caixa desmarcada.
- Backend (DB-FIX3): em `api/desistencia.py` ~79, sem data de pagamento confirmado considerar dentro do prazo (hoje usa o aceite do orçamento).
- Backend (APP6): `GET .../desistencia` deve filtrar ou informar o tipo do registro (não rotular cliente ausente como desistência); consentimento de execução imediata deve valer só a escolha do pagamento confirmado (desmarcar na nova tentativa vale; mais favorável ao consumidor).
- ET4b: a retenção por ausência fica "a liberar" e depende do repasse (etapa do Stripe); a foto da chegada não é guardada no banco (só o horário); ligar `ausencia_exigir_chegada` e publicar o app com a caixa de consentimento antes ou junto do servidor.
- Backend (ADM2): URL assinada com auditoria para o analista ver anexos da ausência; `desistencia: bool` em `DisputaResumoOut`; `motivo` obrigatório em `/ausencias/{id}/confirmar`; número do pedido, nomes e valor em `AusenciaOut`. Publicar o painel só depois do backend.
- Backend (APP7): URLs assinadas dos anexos e comprovantes também para o cliente, antes da cobrança; contestação da decisão de ausência (8.7); ligar `ausencia_exigir_chegada` para um 503 passageiro não virar ausência direta.
7. Exclusividade: aceitar outro profissional ou cancelar o pedido encerra sem devolver (13.6 só devolve por falha do Trato ou desistência do profissional).
- Backend (APP8): `creditos` (saldo restante e vencimento por crédito) em `GET /v1/me/moedas` (13.4).
8. Retenção por ausência só é confirmada depois dos 5 dias úteis de contestação (8.7), mesmo sem contestação; retirar a retenção continua liberado.
- Admin (próxima, ADM4): `/ausencias/{id}/confirmar` exige `{motivo, retirar_retencao}`; anexos com `?motivo=`; decisão de contestação por outro analista; aba de conversa; campo `desistencia` na disputa; `docs/api-admin.md` desatualizado.
- Backend (APP9, privacidade): `GET /v1/pedidos/{id}/ausencia` não deve devolver ao profissional o texto da justificativa nem da contestação do cliente; informar o tipo do arquivo nos anexos.
- Backend (ADM3): listagem/busca de exclusividades pagas pelo cliente para o painel (e no detalhe do pedido); código estável nas recusas.
- Admin (ADM5, depois do ADM4): `GET /v1/admin/chamados` virou `{itens,total,limite,deslocamento}` (o painel atual espera lista); fila "Atendimento" com assumir, resposta, nota interna, prazo e encerrar (`sac_responder`).
- Backend (ADM4): anexos da ausência por POST com motivo obrigatório; upload ou lista de arquivos do pedido para comprovante de retenção; informar quem decidiu; ponto de leitura de conversa para o papel segurança (Risco, no painel).
- Backend (APP10, 20.5): conta bloqueada recebe 403 com `codigo: conta_bloqueada` (ou status em `GET /v1/me`) para o app mostrar a tela de bloqueio com "Falar com o Trato"; hoje o app faz logout. Aviso do chamado deveria trazer `chamado_id`.
