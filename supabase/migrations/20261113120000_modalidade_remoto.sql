-- Modalidade do serviço: presencial (padrão) ou remoto.
--  * categorias.aceita_remoto: o admin liga por categoria (padrão: só presencial).
--  * pedidos.modalidade: o que o cliente escolheu (padrão: presencial, igual a todos os pedidos de hoje).
--  * perfis_profissional.atende_presencial / atende_remoto: o que cada profissional atende
--    (padrão: só presencial, como os cadastros de hoje).
-- Só acrescenta colunas com padrão (nada muda para quem já existe). Rollback em
-- supabase/rollback/modalidade_remoto_rollback.sql.

alter table public.categorias
  add column aceita_remoto boolean not null default false;

alter table public.pedidos
  add column modalidade text not null default 'presencial'
    check (modalidade in ('presencial', 'remoto'));

-- A modalidade não muda depois que o pedido nasce (como categoria e cidade).
drop trigger if exists pedidos_proteger on public.pedidos;
create trigger pedidos_proteger before update on public.pedidos
  for each row execute function public.proteger_colunas(
    'cliente_id', 'categoria_id', 'cidade_id', 'modalidade', 'criado_em');

alter table public.perfis_profissional
  add column atende_presencial boolean not null default true,
  add column atende_remoto boolean not null default false,
  add constraint perfis_profissional_atende_algo check (atende_presencial or atende_remoto);

-- Pedidos abertos por categoria/modalidade (a busca do profissional filtra por isso).
create index pedidos_abertos_modalidade_idx on public.pedidos (modalidade, categoria_id, criado_em desc)
  where status = 'aberto';
