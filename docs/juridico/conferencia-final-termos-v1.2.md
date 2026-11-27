# Conferência final dos Termos v1.2 (26/11/2026)

Feita pela Segurança (TERMOS-CONF-FINAL), código local incluindo não commitado, sem rodar testes. Gravada pelo Mestre (resumida na redação, sem mudar vereditos). Texto integral: chat do Mestre, mensagem 1c4b3260-3827-49a2-9f4c-958578f2b588.

**NÃO está 100%.** 243 cláusulas: CUMPRE 50 | PARCIAL 51 | NÃO CUMPRE 22 | DEPENDE DO JOÃO/externo 109 | NÃO CONFERIDO 11. "Cumpre" vale para o código local; vários dependem de migrations não aplicadas e de publicação.

## Achado mais importante (confirmado pelo Mestre no código)
O agendador não passa o saldo de "a liberar" para "liberado" nem envia o lembrete de fim da janela: `config_rotinas_da_api` (backend/src/trato/agendador/executor.py:49) deixa `prazo_liberacao` vazio sem `complemento`; ver rotinas/regras.py:228,244 e persistencia/config.py:102. Afeta 5.8, 6.7, 8.6, 15.3, 17.4 (a compensação, executor.py:441, na prática não roda). `backend/fly.toml` tem o agendador embutido ligado (publicado não conferido).

## NÃO CUMPRE (cláusula: falta; quem)
- 1.2, 1.5: texto v1.2 não publicado (app v1.1, backend v1.0); App, Backend (depende dos campos em branco).
- 1.7, 23.4: sem reaceite quando a versão muda; App, Backend.
- 4.9: sem aviso de 30 dias antes de inativar; Backend.
- 5.3: comprovante e cópia dos Termos só após conclusão; Backend.
- 6.9: sem rota para contestar material (migration 225400 marcada CORRIGIR); Banco, Backend, App, Admin.
- 8.2: prazo ainda 48 h no seed; publicar 24 h; DevOps, App.
- 8.7: sem contestar decisão de disputa (TERMOS-BE-87 em andamento); App, Admin depois.
- 9.5: sem relato "pessoa diferente" com cancelamento e reembolso integral; Backend, App, Admin.
- 12.6: sem ocultar avaliação (225600 CORRIGIR); Banco, Backend, Admin.
- 13.10, I.11: encerramento não trata Tratinhos; Backend, App.
- 13.11, I.12: sem aviso de 30 dias nem saída do programa; Backend.
- 14.10: sem pedido de revisão de decisão automática; Banco, Backend, App, Admin.
- 20.6: medida não trata pedidos e valores (mexe em dinheiro); Backend.
- 20.8: sem encerramento sem falta com 30 dias; Backend, Admin.
- 20.9: sem infração grave nem pedido de retorno; Banco, Backend.
- 22.3: sem prorrogar prazos por falha; Backend, Admin.
- 23.2: sem aviso de 30 dias de mudança dos Termos; Backend, Admin.
- 23.7: sem histórico de versões no app; App.

## PARCIAL (cláusula: falta)
- 1.4 aceite sem versão do servidor/reaceite · 3.6 cidades do piloto · 4.1/14.13 trava 18 anos desligada · 4.3 MEI desligado · 4.6 Termos do Profissional · 4.8 exclusão ignora Tratinhos e valores retidos
- 5.2 validade/prazo/garantia opcionais · 5.5 check-in sem código (João) · 5.7 sem confirmação tácita e caso em 5 dias úteis · 5.8 liberação, aviso e transferência · 6.1 tributos no app
- 6.3 prazo por configuração · 6.4 parcelamento (juros) · 6.8 extra sem pagamento antes · 6.10 prazo/status do estorno · 6.13 depende da 5.3
- 7.4 custos antes de cancelar (João) · 7.5 regra de 24 h · 7.6 `ausencia_exigir_chegada` desligado · 7.7 ajudar a achar outro · 7.8/22.6 evento externo · 7.9
- 8.4 pedido de informação 10 dias úteis · 8.6 compensação sem rodar · 9.3/9.4 categorias de incidente · 9.6 prazo 24 h, bloqueio e retenção
- 11.8 remoção de conteúdo · 12.3 peso para recentes · 12.7 revisão · 12.10 anulação · 13.3 informar valor e validade · 13.4/I.5 aviso de vencimento
- 13.9/I.10 anular Tratinhos · I.3 compensar em atendimento · I.6 aviso do limite · 14.8 apagar ao vencer · 14.9 fila de solicitações em 15 dias
- 15.2 aviso de mudança e SMTP · 15.3 aviso de fim da janela · 15.4 marketing por consentimento · 16.3 guarda em disputa · 17.4 rota de regresso (banco em andamento)
- 20.5 PDF no app e push de bloqueado · 20.7 Tratinhos · 23.6 versão dos Termos no contrato · 25.1 telefone e horários

## CUMPRE
1.6, 4.2, 4.4, 5.1, 5.6, 5.9, 5.10, 6.2, 6.5, 6.11, 7.1, 7.2, 7.3, 8.1, 8.3, 8.5, 9.2, 11.1, 11.2, 11.3, 11.6, 11.7, 12.1, 12.2, 12.4, 12.5, 12.8, 13.1, 13.2, 13.5, 13.6, 13.7, 13.8, I.1, I.2, I.4, I.7, I.8, I.9, 15.6, 16.4, 20.1-20.4, 23.5, 25.2-25.5.

## DEPENDE DO JOÃO ou externo (109)
- Com decisão ou terceiro: 1.1 (CNPJ), 6.7 (Stripe), 9.9, 9.10, 12.9, 14.2 (encarregado), 15.1 (SMTP, domínio, telefone), 17.6 (advogado).
- Declaratórias/obrigações das partes (valem com o v1.2 publicado; classificadas pela natureza, não lidas uma a uma): 1.3; 3.1-3.5, 3.8; 4.5, 4.7; 6.6, 6.12; 8.8-8.11; 9.1, 9.7, 9.8, 9.11; 10.4, 10.5; 11.4, 11.5; 14.1, 14.5-14.7, 14.14, 14.15; 15.5; 16.2, 16.5-16.7; 17.1-17.3, 17.5, 17.7-17.10; 18; 19; 20.10; 21; 22.1, 22.2, 22.4, 22.5, 22.7, 22.8; 23.1, 23.3, 23.8; 24; 25.6, 25.7; I.13.

## NÃO CONFERIDO (11)
3.7, 5.4, 10.1, 10.2, 10.3, 10.6, 14.3, 14.4, 14.11, 14.12, 16.1. Também falta: Anexo II linha a linha, telas de compensação, configuração real e Política de Privacidade.

## Ordem sugerida
1) liberação e lembretes no agendador (dinheiro); 2) 8.7, 20.6, 9.5, 6.9, 5.3; 3) publicar v1.2 com reaceite e histórico; 4) configuração (24 h, 18 anos, MEI, exigir chegada) só junto do app novo; 5) externos.

## Atualização 26/11 20:55 (Scout, 11 cláusulas que faltavam; sem testes)
- CUMPRE: 5.4, 10.1, 10.6, 14.4
- PARCIAL: 3.7 (serviços proibidos/habilitação), 10.2 (data do selo), 14.3 (IP/aparelho), 14.12 (posição também no pedido), 16.1 (registro de acessos)
- NÃO CUMPRE: 10.3 (selfie no check-in e retirar selo)
- DEPENDE DO JOÃO: 14.11
Totais: CUMPRE 54 | PARCIAL 56 | NÃO CUMPRE 23 | DEPENDE DO JOÃO 110 | sem conferir 0. Não desconta o trabalho feito após 19:50.

## Atualização 26/11, noite (Scout, só leitura, parcial; sem testes). Vale sobre as listas acima
- Fechados no código local: liberação/lembrete no agendador, retenção por incidente/dano, 5.3, 6.9 (devolução ainda sem código), 8.7, 12.6, 13.10/I.11, 14.9/14.10, 20.9. 1.7/23.4: servidor pronto, app em andamento.
- NÃO CUMPRE abertos: 1.2/1.5, 4.9, 9.5, 10.3, 13.11/I.12, 20.6, 20.8, 22.3, 23.2, 23.7.
- PARCIAIS com lacuna confirmada: 4.1/14.13, 4.3, 4.6, 5.2, 5.8/8.6, 6.4, 6.10, 7.6, 8.4, 10.2, 12.3, 13.4/I.5, 13.9/I.10, 14.8, 15.2, 15.4, 16.1/14.3, 23.6, 25.1. 8.2: publicar 24 h e acordo com devolução.
- Não reconferidos (não tratar como fechados): 1.4, 3.6, 3.7, 4.8, 5.5, 5.7, 6.1, 6.3, 6.8, 6.13, 7.4, 7.5, 7.7, 7.8/22.6, 7.9, 9.3, 9.4, 9.6, 11.8, 12.7, 12.10, 13.3, 14.12, 15.3, 16.3, 17.4, 20.5, 20.7, I.3, I.6, I.9.

## Reconferência 26/11 (Scout, só leitura)
- Cumpre: 6.1, 6.13, 7.4 (cliente).
- Parcial: 1.4, 3.7, 4.8, 5.5, 5.7, 6.3, 6.8, 7.5, 7.7, 7.9, 9.3, 9.4, 9.6, 11.8, 12.7, 12.10, 13.3, 14.12, 15.3, 16.3, 20.5, 20.7.
- Sem dinheiro nem migration nova: 12.7 (app, enviado ao Flutter), 1.4 (app), 9.3/9.4 (app; chamado de segurança retém liberação, avaliar), 11.8 (backend).
