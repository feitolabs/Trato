-- Reversão de 20261126231800_pedido_midias_aceita_pdf.sql.
-- Só tira 'application/pdf' da lista do bucket pedido-midias. NÃO apaga arquivos nem linhas:
-- PDFs já enviados continuam guardados; só novos envios de PDF voltam a ser recusados.
-- ATENÇÃO: se o PDF já estivesse liberado antes da migration (ajuste feito fora das migrations),
-- esta reversão também o tira. Confira a lista antes de aplicar a migration:
--   select allowed_mime_types, file_size_limit from storage.buckets where id = 'pedido-midias';

begin;

update storage.buckets
   set allowed_mime_types = array_remove(allowed_mime_types, 'application/pdf')
 where id = 'pedido-midias'
   and 'application/pdf' = any (allowed_mime_types);

commit;
