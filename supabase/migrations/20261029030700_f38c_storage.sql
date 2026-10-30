-- F3.8c — Buckets privados do Storage e suas policies de leitura.
-- Fonte: docs/modelo-de-dados.md, seção 10.2 (Storage) e escopo 3.1 (documentos só da equipe).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- ÚNICA exceção ao "só DDL": o INSERT em storage.buckets. Ele cria a infraestrutura dos buckets
-- (configuração, não dado de negócio) e não pode ser feito de outro jeito por SQL.
-- Depende da F3.8a e da F3.3. Reversão: supabase/rollback/F3.8c_rollback.sql
--
-- Regras:
--  * Todos os buckets são PRIVADOS (public = false): nunca URL pública; leitura por URL assinada curta
--    gerada pelo backend, ou pelo SELECT abaixo.
--  * Não há policy de INSERT/UPDATE/DELETE: o app não grava no Storage direto. Upload vai por URL de
--    envio assinada pelo backend (service_role ignora a RLS).
--  * Limite de tamanho (10 MB) e tipos de arquivo são PROVISÓRIOS, para o João confirmar.
--
-- Caminhos dos arquivos (convenção para o backend):
--   verificacao/<profissional_id>/<verificacao_id>/<arquivo>
--   pedido-midias/<pedido_id>/<arquivo>     (registrado em public.midias)
--   chat-anexos/<pedido_id>/<arquivo>       (registrado em public.midias, finalidade 'chat')
--   avatar/<usuario_id>/<arquivo>           (registrado em usuarios.foto_path)

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('verificacao', 'verificacao', false, 10485760,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']),
  ('pedido-midias', 'pedido-midias', false, 10485760,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic']),
  ('chat-anexos', 'chat-anexos', false, 10485760,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']),
  ('avatar', 'avatar', false, 5242880,
   array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Documentos de verificação (documento, selfie, antecedentes): só a equipe de cadastro.
create policy trato_verificacao_leitura on storage.objects for select to authenticated
  using (bucket_id = 'verificacao' and privado.eh_equipe('cadastro'));

-- Fotos do pedido e anexos de chat: quem pode ver a mídia correspondente (mesma regra de public.midias).
create policy trato_pedido_midias_leitura on storage.objects for select to authenticated
  using (bucket_id = 'pedido-midias' and privado.pode_ver_midia_por_caminho(bucket_id, name));
create policy trato_chat_anexos_leitura on storage.objects for select to authenticated
  using (bucket_id = 'chat-anexos' and privado.pode_ver_midia_por_caminho(bucket_id, name));

-- Foto de perfil: quem pode ver aquele usuário (a RLS de usuarios vale dentro da subconsulta).
create policy trato_avatar_leitura on storage.objects for select to authenticated
  using (bucket_id = 'avatar'
         and exists (select 1 from public.usuarios u where u.foto_path = name));
