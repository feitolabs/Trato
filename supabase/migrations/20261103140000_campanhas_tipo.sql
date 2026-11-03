-- Comunicação e push (painel v2, RF-COM-03): campanha operacional (andamento de serviço) é separada
-- de marketing; marketing respeita a preferência de cada usuário. Só acrescenta uma coluna.

alter table public.campanhas_notificacao add column if not exists tipo text not null default 'marketing'
  check (tipo in ('operacional', 'marketing'));
