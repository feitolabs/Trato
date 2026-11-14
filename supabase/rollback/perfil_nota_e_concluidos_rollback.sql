drop trigger if exists pedidos_concluido_recalcula_perfil on public.pedidos;
drop trigger if exists avaliacoes_recalcula_perfil on public.avaliacoes;
drop function if exists public.pedido_concluido_recalcula_perfil();
drop function if exists public.avaliacao_recalcula_perfil();
drop function if exists public.recalcular_perfil_profissional(uuid);
