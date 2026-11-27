# Conferência do Trato contra os Termos v1.2 (25/11/2026)

Base: `termos-de-uso-v1.2.pdf` + `termos-v1.2-ajustes.md`. Leitura de código por Admin (painel), Scout (app) e Segurança (servidor, 2 passadas). Sem testes, sem banco real. O Mestre conferiu no código só o item D1; o resto é relato dos agentes.

Legenda: C = contradiz, F = não existe, P = parcial.

## Onda 1: dinheiro (precisa do OK do João antes de mexer)
| Id | Cláusula | Estado | Problema | Onde |
|---|---|---|---|---|
| D1 | 7.7 | C | Profissional não aparece: pedido cancelado sem estorno (conferido) | `pagamentos/orquestrador.py:775-803`, `pedidos/estados.py` |
| D2 | 5.8, 6.7 | C | Liberação por prazo desligada; não há criação de transferência no parceiro | `agendador/executor.py:49-73`, `__main__.py` |
| D3 | 7.2-7.4, 7.9 | P/F | Sem "Desistir do pedido" de 7 dias, caixa de execução antecipada, reembolso proporcional, retenção até 30% mostrada antes | `pedidos/estados.py:372-381`, app |
| D4 | 7.6 | C/F | Cliente ausente sem 20 min de espera, 24 h para justificar e análise | `pedidos/estados.py:635-652`, app, painel |
| D5 | 13.6 | C | Exclusividade: termo diz cliente paga e não há devolução; código é o profissional. Efeito ainda não definido | `api/exclusividades.py` |
| D6 | 13.4, 13.8, 13.10 | P/F | Validade pode estar vazia no banco; devolução só em estorno total e sem validade original; sem perda no encerramento | `api/moedas.py`, `lgpd/` |
| D7 | 9.5 | F | Pessoa diferente da verificada: sem cancelamento com reembolso integral | servidor |

## Onda 2: direitos do usuário
| Cláusula | Estado | Falta | Área |
|---|---|---|---|
| 8.7 | F | Contestação por outro analista (5 e 10 dias úteis) | servidor, app, painel |
| 25.1-25.4 | F | SAC no app com protocolo, fila e prazos | servidor, app, painel |
| 20.2-20.5, 11.8 | F/P | Aviso de suspensão e remoção com motivo, cláusula e contestação | servidor, painel |
| 9.2-9.6 | F/P | Canal de segurança, 190/192/193, ação em 24 h | servidor, app, painel |
| 1.4, 4.1 | C/F | Versão aceita fixa em "1.0", sem reaceite e registro; sem data de nascimento e trava de 18 anos | app, servidor |
| 11.3 | F | Analista ver a conversa com acesso registrado | servidor, painel |
| 12.6-12.7, 14.9, 14.10 | F/P | Ocultar avaliação, pedir revisão, fila de dados do titular, revisão de decisão automática | servidor, app, painel |
| 5.7, 8.4, 6.10 | P/F | Check-out sem código (5 dias úteis), 10 dias úteis para complementar, prazo e status do estorno | servidor, app, painel |

## Onda 3: correções pequenas (só código, texto ou configuração)
- 8.2: prazo do profissional 48 h -> 24 h (configuração publicada e textos do app).
- 11.2: liberar o contato necessário depois da contratação.
- 12.1: limite de 30 dias para avaliar. 12.3: média com peso para as recentes.
- 12.4: tirar "avalie com cinco estrelas e ganhe". 13.2: tirar "moeda de desconto".
- 15.2: avisos de disputa e pagamento não podem ser desligados. 15.4: separar ofertas.
- 6.4 (quando ligar parcelamento): mostrar juros e diferença do à vista. 13.4: vencimento por crédito no extrato.
- 14.8: registros de acesso 180 dias -> no mínimo 6 meses.
- E-mails novos, MEI obrigatório, piloto BH e Divinópolis.
- 1.2, 1.5, 1.7: textos legais (app diz 1.1, servidor 1.0). Publicar só com os campos preenchidos.
- 4.2: confirmação do celular dispensada (25/11); o João altera o texto.

## Já cumpre (resumo)
Aceite desmarcado no cadastro, exclusão de conta, códigos de início e fim, janela de 48 h, aditivo com aprovação, relato com fotos, denúncia, selo "Novo no Trato", decisão justificada do analista (8.5), retrabalho de 7 dias, garantia 30/90 dias, não orçar o próprio pedido (4.4), bônus igual para qualquer nota.

## Anexo: servidor, cláusula por cláusula (versão final, 25/11)
Caminhos em `backend/src/trato/`. $ = mexe em dinheiro. "Busca" = não achado por busca no código. Leitura apenas, sem testes nem banco real.

| Cláusula | Veredito | Prova | Correção | Tipo | $ |
|---|---|---|---|---|---|
| 4.1 | CUMPRE no servidor | api/rotas_cadastro.py:32-34 | app pedir nascimento | código | não |
| 4.2 | NÃO SE APLICA: dispensada pelo João em 25/11; vale a confirmação por e-mail; o texto será alterado | - | nenhuma no código | texto (João) | não |
| 4.3 | CONTRADIZ: aceita qualquer CNPJ; exigência desligada | profissional/mei.py:72 | só MEI e ligar | código, config | não |
| 4.4 | CUMPRE (unicidade no banco não conferida) | api/rotas_app.py:670; api/rotas_pedidos.py:265 | - | - | não |
| 4.8 | PARCIAL | persistencia/lgpd.py:35-62 | valores retidos e Tratinhos | código | sim |
| 5.1 | CUMPRE | api/modelos.py:67-95; pedidos/estados.py:372-381 | - | - | não |
| 5.2 | PARCIAL: validade, prazo e garantia opcionais; não achei barreira a aceite vencido | api/rotas_app.py:116-125,718 | exigir campos e barrar | código | sim |
| 5.3 | CONTRADIZ: recibo só após conclusão; sem cópia dos Termos | api/rotas_financeiro.py:353,409 | enviar na contratação | código | não |
| 5.4 | NÃO CONFERIDO: visto em rodada anterior, sem linha | - | conferir | - | não |
| 5.5 | PARCIAL: permite check-in sem código com justificativa | pedidos/estados.py:622-633 | decidir se mantém | código ou texto | não |
| 5.6 | CUMPRE | uploads/servico.py:49-51 | - | - | não |
| 5.7 | PARCIAL: sem confirmação tácita; sem fila do analista em 5 dias úteis | rotinas/regras.py:192-194; api/modelos.py:330 | abrir caso | código | sim |
| 5.8 | CONTRADIZ: 48 h existe; liberação por prazo desligada | agendador/executor.py:49-73 | liberar e transferir | código, config | sim |
| 5.9 | Ver 12.1 | api/rotas_app.py:1566-1600 | - | - | não |
| 5.10 | CUMPRE | pedidos/estados.py:372-381 | - | - | não |
| 6.1 | PARCIAL | pagamentos/taxa.py:23-34 | tributos no texto | texto | não |
| 6.2 | CUMPRE (nome do parceiro não conferido) | busca por número/CVV sem campo | - | - | não |
| 6.3 | PARCIAL: prazo fora do seed | persistencia/config.py:81 | publicar configuração | config | não |
| 6.4 | PARCIAL (parcelamento desligado) | pagamentos/parcelamento.py:6,50-64 | juros e diferença | código | sim |
| 6.5 | CUMPRE; seed com taxa sem uso | pagamentos/taxa.py:1-5; supabase/seeds/parametros.sql:76-81 | limpar seed | config | risco |
| 6.6 | NÃO SE APLICA (sem taxa) | - | - | texto | não |
| 6.7 | CONTRADIZ no código: cobrança sem destino ao profissional; o valor fica na conta Stripe do Trato (configuração da conta não conferida) | pagamentos/provedor/stripe_teste.py:150-173; busca por transfer_data | desenhar repasse; advogado | código | sim |
| 6.8 | PARCIAL | api/rotas_pedido_contrato.py:748-813 | exigir pagamento antes do extra | código | sim |
| 6.9 | NÃO EXISTE contestação | api/rotas_pedido_contrato.py:292-310 | rota e fila | código, migration | sim |
| 6.10 | PARCIAL: pede o estorno na hora; se falhar, nada reenvia; sem prazo estimado ao cliente | pagamentos/orquestrador.py:849 (único chamador) e 932-944; api/rotas_financeiro.py:47 | rotina de reenvio, status e prazo | código | sim |
| 6.11 | PARCIAL: risco de devolver duas vezes | pagamentos/orquestrador.py:643-708 | travar estorno | código | sim |
| 6.12 | PARCIAL (resto é texto) | seguranca/mascaramento.py | - | texto | não |
| 6.13 | PARCIAL: ver 5.3 | api/rotas_financeiro.py:353 | idem | código, texto | não |
| 7.1 | CUMPRE | pedidos/estados.py:372-381 | - | - | não |
| 7.2 | PARCIAL: devolve 100%, mas não há desistência após check-in | pedidos/estados.py:372-381; pagamentos/orquestrador.py:790-803 | desistir em 7 dias | código | sim |
| 7.3 | NÃO EXISTE | busca | caixa e proporcional | código, migration | sim |
| 7.4 | NÃO EXISTE a retenção (hoje mais favorável ao cliente) | pagamentos/orquestrador.py:790-803 | retenção até 30% | código | sim |
| 7.5 | PARCIAL: aceite da outra parte existe; sem regra de 24 h | api/rotas_reagendamento.py:166,218-225 | aplicar 24 h | código | sim |
| 7.6 | CONTRADIZ | pedidos/estados.py:635-652 | 20 min, 24 h, analista | código, migration | sim |
| 7.7 | CONTRADIZ: sem estorno (conferido) | pagamentos/orquestrador.py:775-803 | estornar | código | sim |
| 7.8 | PARCIAL: sem motivo próprio; cancelar não vale após check-in | busca; pedidos/estados.py:372-381 | motivo e regra | código | sim |
| 7.9 | Ver 7.2 a 7.7 (tabela do PDF a confirmar) | - | - | - | sim |
| 8.1 | CUMPRE no registro (retenção real depende de 6.7) | api/rotas_pedidos.py:160-175,668-700 | - | - | sim |
| 8.2 | CONTRADIZ: 48 h | supabase/seeds/parametros.sql:86 | 24 h | config | não |
| 8.3 | CUMPRE | api/rotas_pedidos.py:160-175; commit a7f6aea | - | - | não |
| 8.4 | NÃO EXISTE | busca | 10 dias úteis | código, config | não |
| 8.5 | CUMPRE | api/admin/rotas_disputas.py:98-204; disputas/prazos.py | - | - | não |
| 8.6 | CUMPRE no principal | disputas/maquina.py; supabase/seeds/parametros.sql:88 | - | - | sim |
| 8.7 | NÃO EXISTE | disputas/maquina.py:6-9 | contestação | código, migration | sim |
| 9.5 | NÃO EXISTE | api/rotas_denuncia.py:26-93 | incidente e reembolso | código, migration | sim |
| 9.6 | PARCIAL: bloqueio no painel, sem prazo de 24 h | api/admin/rotas_risco.py:179-340 | prazo e cautelas | código | sim |
| 11.2 | CONTRADIZ: mascara após contratação | persistencia/conversas.py; commit a7f6aea | liberar o necessário | código | não |
| 11.3 | NÃO EXISTE | busca | leitura com registro | código, migration | não |
| 12.1 | NÃO EXISTE limite de 30 dias | api/rotas_app.py:1566-1600 | limitar | código | não |
| 12.2 | CUMPRE: o texto não é editado, só há resposta | persistencia/dinheiro.py:588 | - | - | não |
| 12.3 | NÃO EXISTE peso para recentes | busca | média ponderada | código | não |
| 12.4 | CUMPRE no servidor | api/rotas_app.py:1634-1650 | texto do app | texto | não |
| 12.5 | CUMPRE | api/rotas_app.py:1634-1650 | - | - | não |
| 12.6 | NÃO EXISTE ocultação | api/admin (sem rota de avaliações) | fila e aviso | código | não |
| 12.7 | PARCIAL: resposta existe; pedir revisão não | api/rotas_app.py:1536 | revisão | código | não |
| 12.8 | CUMPRE hoje (nada remove avaliação) | persistencia/dinheiro.py:588 | - | - | não |
| 12.9 | NÃO SE APLICA (opcional) | - | - | - | não |
| 12.10 | PARCIAL: uma avaliação por pedido; sem anulação | api/rotas_app.py:1607 | detectar e anular | código | sim |
| 13.1 | CUMPRE no padrão (configuração real não conferida) | api/moedas.py:39 | - | - | sim |
| 13.2 | CUMPRE no servidor; o app chama de "moeda" | busca por saque; app/lib/telas/ajuda/servico_ajuda_local.dart:30 | texto | texto | não |
| 13.3 | PARCIAL | api/moedas.py:27-54; api/indicacoes.py | informar antes; ajuste | código | sim |
| 13.4 | CONTRADIZ: o crédito vence mas o gasto não, então o valor gasto é descontado de novo no vencimento; sem ordem por vencimento nem aviso; validade pode estar vazia | api/moedas.py:260,602,1052,1476-1482 (lido, não reproduzido) | consumo por crédito, validade, aviso | código, config, talvez migration | sim |
| 13.5 | PARCIAL | api/moedas.py:1293-1315 | alinhar usos | config | sim |
| 13.6 | CONTRADIZ: quem paga é o profissional | api/exclusividades.py:1-20,299-308 | efeito a definir | código | sim |
| 13.7 | CUMPRE | api/moedas.py:1293-1315 | - | - | sim |
| 13.8 | PARCIAL: só estorno total, sem validade original | pagamentos/orquestrador.py:882-896; api/moedas.py:1487-1508 | corrigir | código | sim |
| 13.9 | PARCIAL | agendador/executor.py:221-245 | anulação pela equipe | código, migration | sim |
| 13.10 | NÃO EXISTE | busca em lgpd/ | aviso e 90 dias | código, migration | sim |
| 13.11 | PARCIAL: desligar o programa bloqueia o uso na hora; sem aviso de 30 dias | api/moedas.py:1293-1294 | prazo de saída | código | sim |
| I.1 | Ver 13.2 | idem 13.2 | - | - | não |
| I.2 | Ver 13.1 | idem 13.1 | - | - | sim |
| I.3 | PARCIAL: sem ajuste por atendimento | api/admin/rotas_moedas.py:72-115 | rota | código | sim |
| I.4 | Ver 13.6 | idem 13.6 | - | - | sim |
| I.5 | Ver 13.4 | idem 13.4 | - | - | sim |
| I.6 | PARCIAL: teto existe; aviso prévio não conferido | api/moedas.py:40 | informar na tela | texto | não |
| I.7 | CUMPRE (sem transferência) | busca | - | - | não |
| I.8 | CUMPRE (sem efeito na nota) | api/rotas_app.py:1634-1650 | - | - | não |
| I.9 | Ver 13.8 | idem 13.8 | - | - | sim |
| I.10 | Ver 13.9 | idem 13.9 | - | - | sim |
| I.11 | Ver 13.10 | idem 13.10 | - | - | sim |
| I.12 | Ver 13.11 | idem 13.11 | - | - | sim |
| I.13 | NÃO SE APLICA (texto) | - | - | - | não |
| 14.8 | PARCIAL: 180 dias | lgpd/config.py:29 | 6 meses | config | não |
| 14.9 | PARCIAL | lgpd/servico.py:60-190 | fila, 15 dias | código | não |
| 14.10 | NÃO EXISTE | busca | revisão humana | código | não |
| 20.1 | PARCIAL | api/admin/rotas_usuarios.py:137-175 | gradação | código | não |
| 20.2 | PARCIAL: humano decide; sem limites de 72 h e 7 dias | seguranca/flags.py:1-6 | prazos | código, config | não |
| 20.3 | PARCIAL | persistencia/usuarios.py:15 | prazo | código | não |
| 20.4 | NÃO EXISTE aviso | api/admin/rotas_usuarios.py:146-178 | aviso com motivo | código | não |
| 20.5 | NÃO EXISTE | busca | contestação | código, migration | não |
| 20.6 | NÃO EXISTE | api/admin/rotas_usuarios.py:166-168 | pedidos e dinheiro | código | sim |
| 20.7 | PARCIAL | lgpd/servico.py:115-190 | Tratinhos | código | sim |
| 20.8 | NÃO EXISTE | busca | aviso de 30 dias | código | não |
| 20.9 | NÃO EXISTE | busca | marca de infração | código, migration | não |
| 20.10 | NÃO SE APLICA (texto) | - | - | - | não |
| 22.3 | NÃO EXISTE prorrogação | busca | regra | código | sim |
| Ajuste e-mails | CONTRADIZ | api/rotas_legal.py:117,229-303,359 | trocar, publicar v1.2 | texto | não |
| Ajuste piloto | PARCIAL: configuração real não conferida | supabase/seeds | conferir | config | não |

### Pendente
- Correções do teste anterior sem entrega final: Flutter (C15, C16, C18) e Backend (push em dobro).
- Banco e configuração publicada não conferidos.
