-- ===========================================================================
-- 20261125224500_sac_chamados.sql
-- RASCUNHO (TERMOS-DB4, 1/3). NÃO aplicada no Supabase de produção. Aguarda OK do João.
-- Termos v1.2: 25.3 (protocolo), 25.4 (prazos e novo prazo avisado) e Anexo II.
--
-- Cria public.chamados e public.chamado_mensagens (mensagens só recebem inserção).
-- Protocolo 'SAC-AAAA-NNNNNN' gerado pelo banco (o valor enviado pelo app é ignorado); o
-- número não reinicia na virada do ano. RLS ligada, sem policy; só service_role; sem delete.
-- Só acrescenta; nenhum dado existente é alterado.
--
-- PRAZOS vêm de configuração (o backend calcula responder_ate). NÃO executado aqui;
-- rodar só com OK do João, e gravar os valores numa nova versão de config_parametros:
--   insert into public.config_definicoes (chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao) values
--     ('chamado_resposta_dias_uteis',        'SAC: prazo geral de resposta (25.4)',            'dias_uteis', 1, 30,  array['global'], false),
--     ('chamado_dados_pessoais_resposta_dias','Pedido sobre dados pessoais: resposta (14.9)',  'dias',       1, 15,  array['global'], false),
--     ('incidente_seguranca_cautela_horas',  'Medidas de cautela após relato de segurança (9.6)', 'horas',    1, 24,  array['global'], false)
--   on conflict (chave) do nothing;
--   -- valores do Anexo II: 5, 15 e 24.
--
-- CONFERÊNCIA (somente leitura). Esperado: rls = t, policies = 0, anon/auth = f, del = f.
-- select c.relname, c.relrowsecurity as rls,
--        (select count(*) from pg_policy p where p.polrelid = c.oid) as policies,
--        has_table_privilege('anon', c.oid, 'select') as anon,
--        has_table_privilege('authenticated', c.oid, 'select') as auth,
--        has_table_privilege('service_role', c.oid, 'insert') as svc_insert,
--        has_table_privilege('service_role', c.oid, 'update') as svc_update,
--        has_table_privilege('service_role', c.oid, 'delete') as del
--   from pg_class c where c.relnamespace = 'public'::regnamespace
--    and c.relname in ('chamados', 'chamado_mensagens') order by 1;
--
-- Rollback: supabase/rollback/20261125224500_sac_chamados_rollback.sql
-- ===========================================================================

begin;

-- Gerador de protocolo das tabelas da TERMOS-DB4. Argumentos: prefixo e nome da sequence.
-- Ano no horário de Brasília (UTC-3, sem horário de verão).
create or replace function public.sac_gerar_protocolo()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_numero text;
begin
  v_numero := nextval(format('public.%I', tg_argv[1])::regclass)::text;
  new.protocolo := tg_argv[0] || '-' || to_char(now() at time zone interval '-3 hours', 'YYYY')
                   || '-' || lpad(v_numero, greatest(6, length(v_numero)), '0');
  return new;
end;
$$;
revoke all on function public.sac_gerar_protocolo() from public, anon, authenticated, service_role;

create sequence if not exists public.chamados_protocolo_seq;
revoke all on sequence public.chamados_protocolo_seq from public, anon, authenticated, service_role;

create table if not exists public.chamados (
  id                   uuid primary key default gen_random_uuid(),
  protocolo            text not null unique check (protocolo ~ '^SAC-[0-9]{4}-[0-9]{6,}$'),
  usuario_id           uuid references public.usuarios (id) on delete restrict,
  nome_contato         text check (nome_contato is null or char_length(nome_contato) <= 200),
  contato              text check (contato is null or char_length(contato) <= 320),
  canal                text not null check (canal in ('app', 'email', 'telefone', 'whatsapp', 'painel')),
  categoria            text not null check (categoria in ('duvida', 'reclamacao', 'contestacao',
                                                         'dados_pessoais', 'seguranca', 'outro')),
  assunto              text not null check (btrim(assunto) <> '' and char_length(assunto) <= 200),
  status               text not null default 'aberto'
                         check (status in ('aberto', 'em_atendimento', 'aguardando_usuario',
                                           'respondido', 'encerrado')),
  prioridade           text not null default 'normal'
                         check (prioridade in ('baixa', 'normal', 'alta', 'urgente')),
  responsavel_id       uuid references public.equipe (usuario_id) on delete restrict,
  pedido_id            uuid references public.pedidos (id) on delete restrict,
  medida_id            uuid,  -- FK criada na 20261125224600_medidas_conta
  criado_em            timestamptz not null default now(),
  responder_ate        timestamptz not null,
  primeira_resposta_em timestamptz,
  novo_prazo_ate       timestamptz,
  motivo_extensao      text,
  encerrado_em         timestamptz,
  constraint chamados_identificacao_check check (
    usuario_id is not null or btrim(coalesce(contato, '')) <> ''),
  constraint chamados_extensao_check check (
    novo_prazo_ate is null
    or (btrim(coalesce(motivo_extensao, '')) <> '' and novo_prazo_ate > responder_ate)),
  constraint chamados_encerramento_check check ((status = 'encerrado') = (encerrado_em is not null))
);
create index if not exists ix_chamados_status_prazo on public.chamados (status, responder_ate);
create index if not exists ix_chamados_usuario on public.chamados (usuario_id, criado_em desc)
  where usuario_id is not null;
create index if not exists ix_chamados_pedido on public.chamados (pedido_id) where pedido_id is not null;

create table if not exists public.chamado_mensagens (
  id          uuid primary key default gen_random_uuid(),
  chamado_id  uuid not null references public.chamados (id) on delete restrict,
  autor_tipo  text not null check (autor_tipo in ('usuario', 'equipe', 'sistema')),
  autor_id    uuid references public.usuarios (id) on delete restrict,
  texto       text not null default '',
  anexos      jsonb not null default '[]'::jsonb check (jsonb_typeof(anexos) = 'array'),
  interna     boolean not null default false,
  criada_em   timestamptz not null default now(),
  constraint chamado_mensagens_conteudo_check check (btrim(texto) <> '' or anexos <> '[]'::jsonb),
  constraint chamado_mensagens_autor_check check (
    (autor_tipo <> 'equipe' or autor_id is not null) and (autor_tipo <> 'sistema' or autor_id is null)),
  constraint chamado_mensagens_interna_check check (not interna or autor_tipo <> 'usuario')
);
create index if not exists ix_chamado_mensagens_chamado
  on public.chamado_mensagens (chamado_id, criada_em);

-- Mensagem não muda nem some. Única exceção: a função de anonimização (roda como dona)
-- troca só texto e anexos. SECURITY INVOKER de propósito, para enxergar quem altera.
create or replace function public.chamado_mensagens_imutavel()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if coalesce(current_setting('trato.anonimizando', true), '') = 'sim'
            and current_user = (select pg_get_userbyid(f.proowner) from pg_catalog.pg_proc f
                                 where f.oid = to_regprocedure('public.anonimizar_chamado(uuid,uuid,text)'))
       and (to_jsonb(new) - 'texto' - 'anexos') = (to_jsonb(old) - 'texto' - 'anexos') then
      return new;
    end if;
  end if;
  raise exception 'Mensagem de chamado não pode ser alterada nem apagada' using errcode = 'restrict_violation';
end;
$$;
revoke all on function public.chamado_mensagens_imutavel() from public, anon, authenticated, service_role;

-- LGPD: apaga texto e contato de um chamado ENCERRADO, sem apagar linhas, com auditoria.
-- Arquivos anexos no Storage são apagados pelo backend (guardar os caminhos ANTES).
create or replace function public.anonimizar_chamado(p_chamado uuid, p_analista uuid, p_motivo text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_status text;
  v_msgs   integer;
begin
  if p_chamado is null or p_analista is null or p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'chamado, analista e motivo são obrigatórios';
  end if;
  if not exists (select 1 from public.equipe q
                  where q.usuario_id = p_analista and q.ativo and q.revogado_em is null) then
    return 'analista_invalido';
  end if;
  select c.status into v_status from public.chamados c where c.id = p_chamado for update;
  if not found then
    return 'nao_encontrado';
  end if;
  if v_status <> 'encerrado' then
    return 'nao_encerrado';
  end if;
  update public.chamados
     set nome_contato = case when nome_contato is null then null else '[anonimizado]' end,
         contato = case when contato is null then null else '[anonimizado]' end,
         assunto = '[anonimizado]',
         motivo_extensao = case when motivo_extensao is null then null else '[anonimizado]' end
   where id = p_chamado;
  perform set_config('trato.anonimizando', 'sim', true);
  update public.chamado_mensagens set texto = '[anonimizado]', anexos = '[]'::jsonb
   where chamado_id = p_chamado;
  get diagnostics v_msgs = row_count;
  perform set_config('trato.anonimizando', '', true);
  perform public.registrar_auditoria(
    p_analista, 'equipe', 'dado_pessoal.anonimizacao_chamado', 'chamado', p_chamado,
    null, jsonb_build_object('mensagens', v_msgs), btrim(p_motivo), null, null, null);
  return 'ok';
end;
$$;
revoke all on function public.anonimizar_chamado(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.anonimizar_chamado(uuid, uuid, text) to service_role;

drop trigger if exists chamados_protocolo on public.chamados;
create trigger chamados_protocolo before insert on public.chamados
  for each row execute function public.sac_gerar_protocolo('SAC', 'chamados_protocolo_seq');
drop trigger if exists chamados_proteger on public.chamados;
create trigger chamados_proteger before update on public.chamados
  for each row execute function public.proteger_colunas('id', 'protocolo', 'canal', 'criado_em', 'responder_ate');
drop trigger if exists chamados_sem_delete on public.chamados;
create trigger chamados_sem_delete before delete on public.chamados
  for each row execute function public.bloquear_alteracao();
drop trigger if exists chamados_sem_truncate on public.chamados;
create trigger chamados_sem_truncate before truncate on public.chamados
  for each statement execute function public.bloquear_alteracao();

drop trigger if exists chamado_mensagens_imutavel on public.chamado_mensagens;
create trigger chamado_mensagens_imutavel before update or delete on public.chamado_mensagens
  for each row execute function public.chamado_mensagens_imutavel();
drop trigger if exists chamado_mensagens_sem_truncate on public.chamado_mensagens;
create trigger chamado_mensagens_sem_truncate before truncate on public.chamado_mensagens
  for each statement execute function public.bloquear_alteracao();

alter table public.chamados enable row level security;
alter table public.chamado_mensagens enable row level security;
revoke all on table public.chamados, public.chamado_mensagens from public, anon, authenticated, service_role;
grant select, insert, update on table public.chamados to service_role;
grant select, insert on table public.chamado_mensagens to service_role;

commit;
