-- Desfaz 20261109120000_disputas_responsavel.sql. Apaga só quem assumiu cada disputa (o histórico
-- de quem assumiu continua na auditoria). Rodar ANTES de voltar o backend para a versão sem a coluna.

begin;

drop index if exists public.disputas_responsavel_id_fk_idx;

alter table public.disputas
  drop constraint if exists disputas_assumida_tem_responsavel,
  drop column if exists assumida_em,
  drop column if exists responsavel_id;

commit;
