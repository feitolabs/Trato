-- Operação do painel (09/11/2026): quem da equipe assumiu a análise de uma disputa.
-- Aplicada no Supabase em 08/11/2026 com o OK do João (nome registrado: disputas_responsavel).
-- Idempotente. Não apaga nem altera dado.
--
-- Com isso o painel mostra "Fulano está analisando" e o backend recusa (409) a decisão de quem não
-- assumiu, para duas pessoas não decidirem o mesmo caso ao mesmo tempo. Trocar o responsável exige
-- motivo e fica na auditoria (feito pelo backend, não aqui).
--
-- O app (papel authenticated) NÃO recebe leitura destas colunas: a lista de colunas liberadas em
-- f38b_policies_rls continua a mesma. Disputa decidida ou cancelada já não muda (gatilho
-- disputas_validar), então o responsável também fica congelado depois da decisão.
--
-- Rollback em supabase/rollback/20261109120000_disputas_responsavel_rollback.sql.

begin;

alter table public.disputas
  add column if not exists responsavel_id uuid references public.equipe (usuario_id) on delete restrict,
  add column if not exists assumida_em timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'disputas_assumida_tem_responsavel' and conrelid = 'public.disputas'::regclass
  ) then
    alter table public.disputas
      add constraint disputas_assumida_tem_responsavel
      check ((responsavel_id is null) = (assumida_em is null));
  end if;
end $$;

create index if not exists disputas_responsavel_id_fk_idx on public.disputas (responsavel_id);

comment on column public.disputas.responsavel_id is
  'Quem da equipe assumiu a análise. Só essa pessoa decide; trocar exige motivo (auditoria).';
comment on column public.disputas.assumida_em is 'Quando o responsável atual assumiu.';

commit;
