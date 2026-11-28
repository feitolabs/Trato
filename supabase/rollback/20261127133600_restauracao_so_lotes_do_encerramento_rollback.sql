-- Rollback de 20261127133600_restauracao_so_lotes_do_encerramento.sql
-- RASCUNHO (DB-SEG-M6). NÃO aplicado no Supabase de produção. Não toca em dados.
-- Volta a função da 20261127092000 (com o defeito que esta migration corrige).
-- Rodar ANTES do rollback da 20261127092000.

begin;

create or replace function public.moedas_restauracao_devida(
  p_medida uuid, p_carteira text, p_agora timestamptz default now())
returns integer
language sql stable security definer set search_path = ''
as $$
  select greatest(public.moedas_saldo(m.usuario_id, p_carteira, m.inicio_em)
                  - public.moedas_saldo(m.usuario_id, p_carteira, greatest(p_agora, m.inicio_em)), 0)::integer
    from public.medidas_conta m
   where m.id = p_medida and m.tipo = 'encerramento';
$$;
revoke all on function public.moedas_restauracao_devida(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.moedas_restauracao_devida(uuid, text, timestamptz) to service_role;

commit;
