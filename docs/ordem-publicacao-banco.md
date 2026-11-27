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
