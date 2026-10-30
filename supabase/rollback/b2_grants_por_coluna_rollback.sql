-- Desfaz 20261030140000_b2_grants_por_coluna.sql. Só rodar com OK do João.
revoke select on public.aditivos, public.lancamentos, public.repasses, public.retrabalhos,
  public.eventos_webhook from authenticated;
grant select on public.aditivos, public.lancamentos, public.repasses, public.retrabalhos,
  public.eventos_webhook to authenticated;
