-- Desfaz 20261121300000_cpf_opcional_cadastro.sql.
-- ATENÇÃO: restaura NOT NULL em public.usuarios_privados(cpf). Só rode com o OK do João.
-- Vai FALHAR de forma segura (e desfazer a transação) se existirem linhas com cpf is null:
-- preencha ou trate esses registros antes de rodar este rollback.

begin;

alter table public.usuarios_privados
  alter column cpf set not null;

commit;
