# Banco: o que falta aplicar (atualizado em 28/11; nada foi aplicado)

## Resultado da pré-checagem no banco real (28/11, transação só de leitura)

- Aplicado: tudo até `20261124234500` (conferido pelo catálogo, não pelo registro de migrations).
- Faltam **46 migrations**, de `20261125141500` a `20261128020000` (itens 1 a 46 abaixo). Depois vem a 47 (`20261128030000`, 6.9), que **acompanha o backend que a usa**, e a 48 (`20261128040000`, teto da compensação), que acompanha o backend sem a trava `reembolso_direto_na_disputa`.
- Pré-checagens possíveis agora: `termos_v12` 46/46 ok; aditivo pago em dobro: nenhum. Nas demais, o que deu falso são requisitos criados por migrations ainda não aplicadas (`config_termos`: só a unidade criada pela 1). Rodar cada uma no seu ponto da ordem.
- Dados: não achei dado que faça uma migration falhar. Nenhum pedido com 2 contratos não cancelados (item 21); `exclusividades` vazia (1); tipos de Tratinhos (25) e status de usuários (35) cabem nos checks novos; bucket `pedido-midias` privado e ainda sem PDF (18).
- Divergências do banco real em relação aos arquivos: `privado.pode_ver_pedido` e 5 funções de validação (`mensagens_validar`, `notas_material_validar`, `orcamento_conferir_total`, `pagamentos_validar`, `presencas_validar`) diferem só em comentários. `public.rls_auto_enable` difere em mais que comentários (as migrations pendentes não mexem nela; motivo não investigado).
- Nada foi escrito e nenhum backup foi feito.

## Ensaio completo (28/11, Postgres local descartável, só dados fictícios)

- Base: migrations até `20261124234500` (mesmo esquema comparado, salvo as 7 funções acima; policies, grants e dados reais não comparados).
- Dados fictícios: 31 contratos `aguardando_pagamento` (16 com taxa) com pedidos em vários status, 30 pagamentos, 11 repasses `agendado` sem `liberar_em`, 6 disputas, 15 avaliações, 3 lançamentos de Tratinhos, 23 categorias, 20 definições e versão vigente com 17 valores.
- Repetido às 11h13 já com a 48: 48 migrations, mesmo resultado (0 falha, 0 diferença na volta e na reaplicação).
- Ida: as 47 em ordem, com os 6 seeds de definições (cada um rodado 2 vezes) e as pré-checagens nos pontos abaixo. Sem falha. Definições: 20 -> 48. Únicos falsos: 2 linhas esperadas da `lote_a` (requisitos criados pela 24 e pela 25).
- Volta: rollbacks dos seeds e das 47 em ordem inversa, sem falha; catálogo comparado (tabelas, colunas, funções, constraints, gatilhos): **0 diferença** em relação à base. Reaplicação: 0 diferença em relação à 1ª ida.
- As contagens conferidas e o status dos contratos não mudaram na ida nem na volta. A 18 acrescentou PDF ao bucket e o rollback tirou.
- **Não coberto:** dados reais; policies, grants e a definição dos índices (só a existência) na comparação; rollback depois de uso (vários travam de propósito se já houver registros, e então não há volta); rollback de seed com valor já publicado; backend contra o banco novo; agendador; concorrência; tempo e travas em produção.

## Migrations 1 a 41

Ordem (todas com rollback). Prefixo 20261125 nos itens 1-11 e 20261126 nos 12-19.
1 141500 cancelamento/ausência | 2 150000 saldo e estorno de Tratinhos (ALTO, dinheiro) | 3 223000 exclusividade do cliente (ALTO, dinheiro)
4 224500 chamados | 5 224600 medidas | 6 224700 contestação de disputa | 7 225300 aceites imutáveis
8 225400 contestação de nota | 9 225500 incidentes | 10 225600 moderação (muda nota pública) | 11 225700 pedidos do titular
12 061000 compensação de repasses (ALTO, dinheiro) | 13 061100 foto da chegada | 14 195000 regresso | 15 195100 anonimizar contestação
16 204500 lembretes | 17 213500 retorno e impedimento de conta | 18 231800 PDF nas mídias | 19 231900 acesso do atendente_n2
Juntas: 2+3 e 12+14.

## Antes de publicar
- Rodar as pré-checagens (supabase/consultas/pre_checagem_termos_v12.sql e pre_checagem_termos_db86.sql); 14-19: supabase/consultas/pre_checagem_termos_db1419.sql (validada só em Postgres local). Consultas por migration: relatório DB-ORDEM-PUB (histórico do Mestre).
- Definições de configuração: supabase/seeds/seed_config_definicoes_termos.sql (depois da 141500; pré-checagem em consultas/pre_checagem_config_termos.sql; a 223000 não tem). Pelo painel: prazo_resposta_disputa_horas 48 para 24.
- 17: falta confirmar o segredo CONTA_IMPEDIMENTO_PEPPER.
- 12: a Segurança vetou antes do ajuste A1; ajuste feito, sem nova revisão registrada. 8 e 10: motivo original do "CORRIGIR" não achado.
- O agendador embutido libera saldos vencidos no 1º ciclo do backend novo.
- Ordem sugerida: banco, depois backend. Compatibilidade do backend publicado com o banco novo não testada.

20 20261127001000 trava de saque por fraude (depois da 19; depende de 224600 e 213500; pré-checagem própria: supabase/consultas/pre_checagem_trava_fraude.sql). Desfazer antes das de que depende.
21 20261127004000 um contrato vigente por pedido (rodar antes do backend novo; rodar de novo se a 225600 vier depois). Acerto dos presos: consultas/acerto_pedidos_presos_reorcar.sql só depois do backend novo, com OK próprio.

## Migrations 22 a 41 (DB-LOTE-A e seguintes; só arquivo, testadas só em Postgres local)

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

## Migrations 42 a 48 (28/11)

Os rollbacks têm o mesmo nome em `supabase/rollback/`, com final `_rollback.sql`.

42 20261128010000 Check-out sem o Código Final, fase 2: grava a decisão (depois da 41). O rollback trava se houver decisão gravada. Desfazer antes da 41.
43 20261128011500 categorias: `incluido` e `nao_incluido` (Termos 3.6; só F3.2). O rollback trava se houver dado preenchido.
44 20261128013000 disputa_pedidos_informacao (Termos 8.4; só F3.2 e F3.6). O rollback trava se houver registro.
45 20261128014500 pedido substituto e índice de faltas (Termos 7.7; depois da 1, que cria cancelamentos_pedido). Um substituto por pedido. O rollback trava se houver vínculo. Desfazer antes da 1.
46 20261128020000 eventos_forca_maior (Termos 7.8 e 22.6; só F3.2 e F3.3). O rollback trava se houver registro.

### 47: 20261128030000_nota_material_estorno_69 (junto com o backend que a usa)

- Termos 6.9. O João aprovou a regra só no código local: **aplicar no banco real exige OK próprio**. Fora das 46.
- Depende de ordens_estorno (já aplicada), 8 (225400), 12 (061000) e 14 (195000). Desfazer antes da 14, da 12 e da 8. Se a 8 ou a 12 forem rodadas de novo, rodar a 47 de novo.
- O rollback trava se houver execução, dívida de material ou `aprovada_em` gravada: depois da 1ª aprovação de contestação de material, não há volta.
- Custo do parcelamento (ajuste de Segurança de 28/11): conferido por cobrança das ordens da contestação e limitado ao custo ainda em aberto no livro.
- Depois dela, marcar `efeito_financeiro='executado'` só pela função `nota_material_executar_estorno` (UPDATE direto é recusado).
- Antes de publicar, conferir no backend (código em alteração em 28/11, não testado contra este banco): custo do parcelamento proporcional; chave das ordens `nota-material/<contestacao_id>/...`; resultado diferente de `ok`/`ja_executada` desfaz a transação. Material pago fora do app: não chamar a função.

### 48: 20261128040000_compensacao_conta_reembolso_retido (dinheiro)

- Corrige o teto "já devolvido desde a abertura da disputa" em `compensacao_estornado_ao_cliente` e `compensacao_criar_divida`: passa a contar o 'reembolso' direto com chave terminada em `/retido/custodia` ou `/retido/a-liberar`, menos `nota-material/%`. Só troca funções; nenhum dado muda.
- Depende da 34 (e, por ela, da 12 e da 14); não depende da 47. Se a 12 ou a 34 rodarem de novo, rodar a 48 (a 34 já manda rodar de novo depois da 12 e da 14). Desfazer antes da 34.
- Ordem com o backend: aplicar antes (ou junto) do backend que remove a trava 409 `reembolso_direto_na_disputa`; nunca retirar a trava sem a 48. Rollback não trava com dados, mas reabre o defeito: religar a trava antes.
- Aberto: `/custo-devolvido` não é contado (ver decisão 11). Aplicar no banco real exige OK do João.

## Seeds das 23 definições (só catálogo; não gravam valor nem publicam)

| Seed (supabase/seeds/) | Definições | Rodar depois da |
|---|---|---|
| seed_config_definicoes_termos.sql | 11 | 1 (pré-checagem `pre_checagem_config_termos.sql`) |
| seed_config_avisos_previos.sql | 5 | 1 |
| seed_config_definicoes_123_75.sql | 2 | 1 |
| seed_termos_e_config_100.sql | 3 | 22 |
| seed_config_retencao.sql | 1 | 33 |
| seed_config_checkout_sem_codigo.sql | 1 | 41 |

Rollback de cada um: `supabase/rollback/<nome>_rollback.sql`, antes de desfazer a migration da coluna "depois da".
Outras 5 definições nascem nas migrations: 2 (`prazo_avaliacao_dias`), 16 (dois lembretes), 17 (`conta_retorno_prazo_dias`) e 20 (`trava_fraude_prazo_maximo_dias`). Total: 28 novas.
Não conferidos nesta pré-checagem: seeds de cidades, categorias, equipe e contas do livro.

## Pré-checagens por ponto da ordem (supabase/consultas/, só leitura)

| Antes da | Arquivo (pre_checagem_...) |
|---|---|
| 1 | termos_v12.sql |
| 12 | termos_db86.sql |
| 14 | termos_db1419.sql |
| 20 | trava_fraude.sql |
| 22 | lote_a.sql (2 falsos esperados: requisitos criados pela 24 e pela 25) |
| 29 | aditivo_pago_unico.sql (o SELECT [2] vazio) |
| 30 | seg_sql.sql |

`config_termos` vai depois da 1 e antes do seed. As migrations 33 a 48 não têm arquivo próprio: usar os pré-requisitos descritos em cada item.

## Decisões abertas antes de publicar (João)

1. OK para escrever no banco (migrations e seeds) e como fazer o backup antes. A 47 precisa de OK separado.
2. Valores das 28 definições novas, pelo painel (inclui `nota_minimo_avaliacoes`) e confirmação das fórmulas e prazos marcados como proposta (item 23; item 37 só origem 'app').
3. `prazo_resposta_disputa_horas`: vigente 48; este documento manda 24.
4. A versão vigente ainda tem `taxa_bps` 750 e `taxa_minima_centavos` 300, com o app gratuito. 16 de 31 contratos têm taxa maior que zero (o último de 16/11). Não conferido se o backend novo ignora essas chaves.
5. Há 1 versão de configuração aguardando aprovação (14 valores, 1 diferente da vigente) e 1 rascunho (17, 1 diferente): decidir o destino antes de criar a nova versão. Equipe ativa: 3 administradores.
6. Datas das versões 1.0 e 1.1 dos Termos (item 22; data passada é irreversível) e comando dos contratos já pagos.
7. Segredo `CONTA_IMPEDIMENTO_PEPPER` (item 17): não conferido.
8. Revisão de Segurança pendente da 12; motivo do "CORRIGIR" da 8 e da 10 não achado.
9. Os 11 repasses agendados estão sem `liberar_em`: efeito do 1º ciclo do agendador novo não simulado. Os 31 contratos estão `aguardando_pagamento`, inclusive de pedidos concluídos: causa não investigada; conferir com o Backend antes de publicar.
10. Material pago fora do app: o banco não identifica o caso e não permite marcar o encerramento manual. Decidir se precisa.
11. `/custo-devolvido` no teto da compensação: pelo caminho de estorno, o custo do parcelamento devolvido já conta como "devolvido ao cliente"; pelo reembolso direto, a 48 não conta. Decidir se deve contar.

## Notas por item (22 a 28) e rollbacks

- Pré-checagem de 22 a 28: supabase/consultas/pre_checagem_lote_a.sql.
- Definições dos avisos prévios (depois da 141500): supabase/seeds/seed_config_avisos_previos.sql. Valores pelo painel.
- Desfazer na ordem inversa (28 a 22); a 28 antes da 25 e a 26 antes da 24. Os rollbacks são os de mesmo nome em supabase/rollback/.
- backend/tests/integracao/pg_local.py: o Backend deve conferir se lista todas até a 48 (não conferido em 28/11).
