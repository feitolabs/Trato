-- DB-FIX69 (1): o bucket pedido-midias passa a aceitar PDF (o upload do backend já aceita).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Reversão: supabase/rollback/20261126231800_pedido_midias_aceita_pdf_rollback.sql
--
-- EXCEÇÃO ao "só acrescenta DDL": é um UPDATE em storage.buckets (configuração do bucket).
-- Só acrescenta 'application/pdf' à lista. NÃO muda o limite de tamanho (10 MB) nem libera vídeo.
-- Lista nula (qualquer tipo aceito) fica como está. Repetir não duplica o item.

begin;

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'pedido-midias') then
    raise exception 'Bucket pedido-midias não existe: aplique antes a F3.8c';
  end if;
end $$;

update storage.buckets
   set allowed_mime_types = array_append(allowed_mime_types, 'application/pdf')
 where id = 'pedido-midias'
   and allowed_mime_types is not null
   and not ('application/pdf' = any (allowed_mime_types));

commit;
