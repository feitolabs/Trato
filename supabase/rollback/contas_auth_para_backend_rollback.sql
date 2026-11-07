-- Desfaz 20261107130000_contas_auth_para_backend.sql (só funções; dados intactos). Só com OK do João.
-- Atenção: sem elas, Busca > Usuários e Equipe voltam a falhar no painel.
drop function if exists privado.contas_auth(uuid[]);
drop function if exists privado.conta_auth_por_email(text);
