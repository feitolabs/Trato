# Banco: o que falta aplicar (relato do Banco, 26/11, só leitura; produção não consultada)

Ordem (todas com rollback). Prefixo 20261125 nos itens 1-11 e 20261126 nos 12-19.
1 141500 cancelamento/ausência | 2 150000 saldo e estorno de Tratinhos (ALTO, dinheiro) | 3 223000 exclusividade do cliente (ALTO, dinheiro)
4 224500 chamados | 5 224600 medidas | 6 224700 contestação de disputa | 7 225300 aceites imutáveis
8 225400 contestação de nota | 9 225500 incidentes | 10 225600 moderação (muda nota pública) | 11 225700 pedidos do titular
12 061000 compensação de repasses (ALTO, dinheiro) | 13 061100 foto da chegada | 14 195000 regresso | 15 195100 anonimizar contestação
16 204500 lembretes | 17 213500 retorno de conta | 18 231800 PDF nas mídias | 19 231900 acesso do atendente_n2
Juntas: 2+3 e 12+14.

## Antes de publicar
- Rodar as pré-checagens (supabase/consultas/pre_checagem_termos_v12.sql e pre_checagem_termos_db86.sql); 14-19: supabase/consultas/pre_checagem_termos_db1419.sql (validada só em Postgres local). Consultas por migration: relatório DB-ORDEM-PUB (histórico do Mestre).
- Definições de configuração: supabase/seeds/seed_config_definicoes_termos.sql (depois da 141500; pré-checagem em consultas/pre_checagem_config_termos.sql; a 223000 não tem). Pelo painel: prazo_resposta_disputa_horas 48 para 24.
- 17: falta confirmar o segredo CONTA_IMPEDIMENTO_PEPPER.
- 12: a Segurança vetou antes do ajuste A1; ajuste feito, sem nova revisão registrada. 8 e 10: motivo original do "CORRIGIR" não achado.
- O agendador embutido libera saldos vencidos no 1º ciclo do backend novo.
- Ordem sugerida: banco, depois backend. Compatibilidade do backend publicado com o banco novo não testada.
- backend/tests/integracao/pg_local.py não lista 18 e 19.

20 20261127001000 trava de saque por fraude (depois da 19; depende de 224600 e 213500; pré-checagem própria: supabase/consultas/pre_checagem_trava_fraude.sql). Desfazer antes das de que depende.
21 20261127004000 um contrato vigente por pedido (rodar antes do backend novo; rodar de novo se a 225600 vier depois). Acerto dos presos: consultas/acerto_pedidos_presos_reorcar.sql só depois do backend novo, com OK próprio.

## DB-LOTE-A (27/11): migrations depois da 21 (só arquivo; testadas só em Postgres local)

22 20261127061000 versão dos Termos no contrato. Depois: seed supabase/seeds/seed_termos_e_config_100.sql (só definições; NÃO grava versão dos Termos). As versões 1.0 e 1.1 estão comentadas no seed: data passada é irreversível; só com OK do João para cada data. Contratos já pagos: comando no cabeçalho, com OK próprio.
23 20261127061100 nota com peso nas recentes (depende da 225600; fórmula é proposta, confirmar; recalcular perfis com OK próprio).
24 20261127061200 registro de acessos (o expurgo não roda sozinho).
25 20261127092000 guarda e restauração de Tratinhos (depende de 150000, 224600 e 213500).
26 20261127122500 preservar registros em incidente aberto, Termos 9.6 (depende de 224500, 224600, 225500, 225700, 195100 e 24). Se a 24 for rodada de novo depois, rodar esta de novo.
27 20261127122600 recusa pedido e contrato novos de conta anonimizada.
28 20261127133600 correção do cálculo da restauração (conta só os Tratinhos que existiam no encerramento, inclusive os estornados depois com a validade original). Obrigatória junto com a 25, antes de qualquer restauração; se a 25 for rodada de novo, rodar a 28 de novo.
29 20261127185000 um pagamento vigente por aditivo (índice único; não depende das 22-28). Antes: supabase/consultas/pre_checagem_aditivo_pago_unico.sql (o SELECT [2] tem de vir vazio; com duplicado a migration falha sem alterar nada). O backend precisa tratar o erro 23505 de pagamentos_aditivo_pago_uidx antes de aplicar. Desfazer: rollback de mesmo nome, em qualquer ordem.
30 20261127190000 expurgo de acessos sem corrida e protegendo as partes de incidente aberto (depois da 26). Obrigatória antes de ligar o expurgo.
31 20261127190100 reversão da trava por fraude exige analista ativo (depois da 20). Aplicar junto.
32 20261127190200 fuso America/Sao_Paulo e desempate de contratos (depois da 21 e da 22).
33 20261127190500 guarda por prazo (14.8 e 16.3): guardas por Pedido e consulta de elegibilidade; não apaga nada (depois da 30, da 32, da 224700 e da 225400). Se a 30 rodar de novo, rodar a 33. Depois: supabase/seeds/seed_config_retencao.sql. Simulação (só leitura): supabase/consultas/simulacao_retencao.sql. Pré-requisito: to_regprocedure('public.expurgo_acessos_enfileirar()') não nulo e to_regclass('public.pedido_guardas') nulo. Desfazer a 33 antes da 30 e da 32 (o rollback da 32 trava com a 33 aplicada).
34 20261127191500 redução de compensação por contestação (depois da 12 e da 14: 061000 e 195000). O backend precisa usar o valor efetivo antes da primeira redução. Se a 12 ou a 14 rodar de novo, rodar a 34. Pré-requisito: to_regprocedure('public.compensacao_papel_ok(uuid,text[])') não nulo e to_regclass('public.compensacoes_reducoes') nulo. Desfazer antes da 14 e da 12.
35 20261127201500 status 'inativo' em public.usuarios (Termos 4.9; depende apenas de 20261029025430 F3.2; não depende das 22-34). Pré-requisito: to_regclass('public.usuarios') não nulo. Desfazer: rollback de mesmo nome em qualquer ordem (trava com erro se ainda houver linha com status = 'inativo').
36 20261127205000 tabela public.janelas_indisponibilidade (Termos 22.3; sem dependência de migrations anteriores; só registra, não prorroga prazo; histórico sem apagar, só encerrar uma vez). Pré-requisito: to_regclass('public.janelas_indisponibilidade') nulo. Desfazer: rollback de mesmo nome em qualquer ordem (trava com erro se ainda houver linhas registradas).
37 20261127213000 prazo de resposta da exclusividade prorrogado por falha do app (Termos 22.3; depois da 3 [223000] e da 36). Considera só origem 'app' (confirmar). Se a 2 [150000] ou a 3 rodarem de novo, rodar a 37. Pré-requisito: to_regprocedure('public.exclusividade_prazo_resposta(timestamptz,timestamptz)') nulo na primeira vez. Desfazer antes da 36, da 3 e da 2; ofertas mantidas só pela prorrogação expiram no ciclo seguinte.
38 20261127220000 validade do orçamento prorrogada por falha do app ou do pagamento na exclusividade do cliente (Termos 22.3; depois da 3 [223000] e da 36; não depende da 37). Se a 3 rodar de novo, rodar a 38. Pré-requisito na primeira vez: to_regprocedure('public.orcamento_validade_vigente(timestamptz,timestamptz,timestamptz)') nulo. Desfazer antes da 36 e da 3.
39 20261127223000 selo do profissional: histórico imutável e retirada até regularização (Termos 10.3; só depende da F3.2/F3.3). ANTES de usar a retirada, o backend precisa tratar o erro 23001 'selo_retirado' na aprovação de verificação. Pré-requisito: to_regclass('public.selo_eventos') nulo na primeira vez. Rollback trava se houver evento.
40 20261127223100 disputas.resultado_esperado (Termos 8.4; só depende da F3.6). Aplicar antes do backend que grava a coluna. Rollback trava se houver valor preenchido.
41 20261127230000 casos de Check-out sem o Código Final (Termos 5.7; fase 1, sem dinheiro; só F3.2/F3.3). Depois: supabase/seeds/seed_config_checkout_sem_codigo.sql. Pré-requisito: to_regclass('public.checkout_sem_codigo_casos') nulo na primeira vez. Rollback trava se houver caso.
Rodou de novo a 24 ou a 26: rodar a 30. A 20: rodar a 31. A 21 ou a 22: rodar a 32. Pré-checagem de 30 a 32: supabase/consultas/pre_checagem_seg_sql.sql. Desfazer 30 a 32 antes das migrations de que dependem.

- Pré-checagem de 22 a 28: supabase/consultas/pre_checagem_lote_a.sql.
- Definições dos avisos prévios (depois da 141500): supabase/seeds/seed_config_avisos_previos.sql. Valores pelo painel.
- Desfazer na ordem inversa (28 a 22); a 28 antes da 25 e a 26 antes da 24. Os rollbacks são os de mesmo nome em supabase/rollback/.
- backend/tests/integracao/pg_local.py lista até a 29; faltavam 30 a 36 (27/11 20h50). Às 22h21 o backend já listava a 36 (em edição); a 37 e a 38 não; conferir 39 a 41.
