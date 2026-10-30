-- Desfaz a migration F3.8c (supabase/migrations/20261029030700_f38c_storage.sql).
-- Só rodar com OK do João.

drop policy if exists trato_verificacao_leitura on storage.objects;
drop policy if exists trato_pedido_midias_leitura on storage.objects;
drop policy if exists trato_chat_anexos_leitura on storage.objects;
drop policy if exists trato_avatar_leitura on storage.objects;

-- ATENÇÃO: no Supabase, DELETE direto em storage.buckets é bloqueado quando a plataforma proíbe
-- apagar das tabelas do Storage por SQL (mensagem "Use the Storage API"). Se este comando for
-- recusado, apague os buckets VAZIOS pelo painel ou pela API do Storage. Buckets com arquivos
-- reais nunca devem ser apagados por rollback.
delete from storage.buckets where id in ('verificacao', 'pedido-midias', 'chat-anexos', 'avatar');
