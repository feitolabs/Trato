-- Desfaz 20261113120000_modalidade_remoto.sql. Só rode se NÃO houver pedido remoto em andamento.
drop index if exists public.pedidos_abertos_modalidade_idx;
alter table public.perfis_profissional drop constraint if exists perfis_profissional_atende_algo;
alter table public.perfis_profissional
  drop column if exists atende_remoto, drop column if exists atende_presencial;
drop trigger if exists pedidos_proteger on public.pedidos;
create trigger pedidos_proteger before update on public.pedidos
  for each row execute function public.proteger_colunas('cliente_id', 'categoria_id', 'cidade_id', 'criado_em');
alter table public.pedidos drop column if exists modalidade;
alter table public.categorias drop column if exists aceita_remoto;
