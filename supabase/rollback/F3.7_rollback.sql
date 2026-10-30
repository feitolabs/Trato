-- Desfaz a migration F3.7 (supabase/migrations/20261029030400_f37_chat_notificacoes_auditoria.sql).
-- ATENÇÃO: apaga as tabelas e todos os dados delas, INCLUINDO MENSAGENS E AUDITORIA (imutáveis de propósito).
-- Só rodar com OK do João e nunca depois que houver dado real.
-- Rodar ANTES o rollback F3.8.

drop table if exists public.notificacao_preferencias;
drop table if exists public.notificacoes;
drop table if exists public.mensagens;
drop table if exists public.conversas;
-- CASCADE aqui derruba também auditoria_calcular_hash (usa o tipo da tabela).
drop table if exists public.auditoria cascade;
drop sequence if exists public.auditoria_id_seq;

drop function if exists public.verificar_cadeia_auditoria();
drop function if exists public.registrar_auditoria(uuid, text, text, text, uuid, jsonb, jsonb, text, text, text, text);
drop function if exists public.auditoria_encadear();
drop function if exists public.auditoria_calcular_hash(public.auditoria, text);
drop function if exists public.mensagens_validar();
drop function if exists public.mensagens_proteger();
drop function if exists public.conversas_validar();
