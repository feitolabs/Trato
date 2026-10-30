-- Cadastro do profissional: disponibilidade, portfólio e solicitações de upload.
--
-- STATUS: APLICADA no Supabase em 30/10/2026 com o OK do João (inclui os privilégios explícitos do final).
-- Reversão: supabase/rollback/profissional_disponibilidade_portfolio_uploads_rollback.sql
--
-- * perfis_profissional.disponibilidade / portfolio: json simples, validado pela API
--   (limites em TRATO_PRO_*). Sem dado pessoal: texto já passou pelo mascaramento de contato.
-- * upload_solicitacoes: cada URL de envio assinada emitida (quem pediu, destino, caminho,
--   tipo e tamanho declarados). Só o backend (service_role) lê e grava; RLS ligada, sem policy.
--   O registro final continua em public.midias / public.verificacao_documentos.

alter table public.perfis_profissional
  add column disponibilidade jsonb not null default '[]'::jsonb,
  add column portfolio       jsonb not null default '[]'::jsonb;

create table public.upload_solicitacoes (
  id            uuid primary key default gen_random_uuid(),
  dono_id       uuid not null references public.usuarios (id) on delete restrict,
  destino       text not null
                  check (destino in ('pedido', 'antes', 'durante', 'depois', 'checkin', 'checkout',
                                     'nota_material', 'disputa', 'retrabalho', 'chat', 'avatar',
                                     'verificacao')),
  pedido_id     uuid references public.pedidos (id) on delete restrict,
  tipo_documento text,
  bucket        text not null check (bucket in ('pedido-midias', 'chat-anexos', 'avatar', 'verificacao')),
  caminho       text not null check (btrim(caminho) <> ''),
  content_type  text not null,
  tamanho_bytes bigint not null check (tamanho_bytes > 0),
  status        text not null default 'pendente' check (status in ('pendente', 'concluida')),
  registro_id   uuid,  -- id em midias ou verificacao_documentos, quando concluída
  criada_em     timestamptz not null default now(),
  unique (bucket, caminho)
);
create index upload_solicitacoes_dono_idx on public.upload_solicitacoes (dono_id, criada_em desc);
alter table public.upload_solicitacoes enable row level security;

-- Privilégios explícitos (igual às demais tabelas): anon/authenticated nada; service_role sem DELETE/TRUNCATE.
revoke all on table public.upload_solicitacoes from public, anon, authenticated, service_role;
grant select, insert, update on table public.upload_solicitacoes to service_role;
