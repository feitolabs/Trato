-- Rollback de 20261126195100_anonimizacao_contestacao_medida.sql
-- RASCUNHO. NÃO aplicado no Supabase de produção.
-- Volta os 2 gatilhos da 20261125224600 e remove as funções. Nenhum dado é tocado; o que já
-- foi anonimizado continua anonimizado (a auditoria guarda os caminhos).

begin;

drop trigger if exists medida_contestacoes_anonimizar_trg on public.medida_contestacoes;
drop trigger if exists medida_contestacoes_validar_insert_trg on public.medida_contestacoes;
drop trigger if exists medida_contestacoes_validar_trg on public.medida_contestacoes;
drop trigger if exists medida_contestacoes_proteger on public.medida_contestacoes;
create trigger medida_contestacoes_proteger before update on public.medida_contestacoes
  for each row execute function public.proteger_colunas(
    'id', 'protocolo', 'medida_id', 'usuario_id', 'versao_usuario', 'anexos', 'canal', 'aberta_em',
    'responder_ate');
create trigger medida_contestacoes_validar_trg before insert or update on public.medida_contestacoes
  for each row execute function public.medida_contestacoes_validar();

drop function if exists public.anonimizar_contestacao_medida(uuid, uuid, text);
drop function if exists public.lgpd_arquivos_contestacao_medida(uuid);
drop function if exists public.medida_contestacoes_so_anonimizar();
drop function if exists public.anonimizacao_de_contestacao_em_curso();

commit;
