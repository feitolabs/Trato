-- ===========================================================================
-- 20261128014500_pedidos_substituicao_77.sql
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
--
-- Termos v1.2, cláusula 7.7: vincula um pedido de substituição ao pedido
-- original quando o Profissional contratado cancela ou não comparece, e
-- acrescenta índice em public.cancelamentos_pedido para consulta rápida de
-- cancelamentos/faltas repetidas do profissional pelo painel.
--
-- Só acrescenta; sem UPDATE de dados.
-- Depende de: F3.2 (proteger_colunas), F3.3 (pedidos),
--             20261125141500_termos_v12_cancelamento_ausencia_exclusividade (cancelamentos_pedido).
-- Rollback: supabase/rollback/20261128014500_pedidos_substituicao_77_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regclass('public.pedidos') is null then
    raise exception 'Aplique antes a migration 20261029030000_f33_pedidos_orcamentos_contratos.sql (public.pedidos)';
  end if;
end $$;

alter table public.pedidos
  add column if not exists substitui_pedido_id uuid references public.pedidos (id) on delete restrict;

alter table public.pedidos
  drop constraint if exists pedidos_substitui_pedido_check;

alter table public.pedidos
  add constraint pedidos_substitui_pedido_check
    check (substitui_pedido_id is null or substitui_pedido_id <> id);

drop index if exists public.pedidos_substitui_pedido_idx;
create unique index if not exists pedidos_substitui_pedido_uidx
  on public.pedidos (substitui_pedido_id)
  where substitui_pedido_id is not null;

-- Vínculo de substituição nasce com o pedido e não pode ser alterado depois.
drop trigger if exists pedidos_proteger_substituicao on public.pedidos;
create trigger pedidos_proteger_substituicao
  before update on public.pedidos
  for each row execute function public.proteger_colunas('substitui_pedido_id');

-- Índice parcial para consulta de cancelamentos/faltas repetidas do profissional (7.7).
do $$
begin
  if to_regclass('public.cancelamentos_pedido') is not null then
    execute 'create index if not exists ix_cancelamentos_pedido_profissional_faltas
               on public.cancelamentos_pedido (solicitado_por, criado_em desc)
               where tipo = ''cancelamento_profissional''';
  end if;
end $$;

commit;
