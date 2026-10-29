-- F3.8a — Funções auxiliares das policies (schema privado) e privilégios padrão fechados.
-- Fonte: docs/modelo-de-dados.md, seções 9 e 10 (aprovado pelo João em 28/10/2026).
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Só DDL. Não cria policy (isso é a F3.8b) e não mexe em dados.
-- Depende da F3.2 a F3.7. Reversão: supabase/rollback/F3.8a_rollback.sql
--
-- Decisões:
--  * As funções ficam no schema `privado`, que a API (PostgREST) não expõe e ao qual `anon` nem tem USAGE.
--    Assim ninguém as chama por RPC; só as policies as usam.
--  * Toda função é SECURITY DEFINER com `set search_path = ''`, nomes totalmente qualificados e
--    EXECUTE revogado de public e anon (só authenticated e service_role).
--    Isso evita recursão entre policies e escalada por search_path.
--  * As funções só respondem sobre quem está logado (auth.uid()): nenhuma recebe "o usuário" como argumento.
--  * Privilégios padrão do schema public: objetos novos NÃO nascem acessíveis a anon/authenticated
--    (o padrão do Supabase dá tudo a eles). Quem precisar de acesso concede explicitamente.

-- Mudança de padrão: tabelas, sequências e funções futuras do schema public nascem fechadas.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;

create schema if not exists privado;
revoke all on schema privado from public, anon;
grant usage on schema privado to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Equipe
-- ---------------------------------------------------------------------------
create or replace function privado.eh_equipe(variadic papeis text[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.equipe e
     where e.usuario_id = (select auth.uid())
       and e.ativo and e.revogado_em is null
       and e.papel = any (papeis)
  );
$$;

create or replace function privado.eh_equipe_qualquer()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.equipe e
     where e.usuario_id = (select auth.uid()) and e.ativo and e.revogado_em is null
  );
$$;

-- Conta que não está bloqueada nem anonimizada (usada numa policy restritiva em todas as tabelas).
create or replace function privado.conta_ativa()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.usuarios u
     where u.id = (select auth.uid()) and u.status in ('ativo', 'restrito')
  );
$$;

-- ---------------------------------------------------------------------------
-- Perfis e relações entre pessoas
-- ---------------------------------------------------------------------------
create or replace function privado.profissional_aprovado(profissional uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis_profissional p
                  where p.usuario_id = profissional and p.status = 'aprovado');
$$;

-- O usuário logado tem relação com `outro`: contrato, orçamento ou conversa (para ver nome e foto).
create or replace function privado.eh_contraparte(outro uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
           select 1 from public.contratos c
            where (c.cliente_id = (select auth.uid()) and c.profissional_id = outro)
               or (c.profissional_id = (select auth.uid()) and c.cliente_id = outro))
      or exists (
           select 1 from public.conversas v
            where (v.cliente_id = (select auth.uid()) and v.profissional_id = outro)
               or (v.profissional_id = (select auth.uid()) and v.cliente_id = outro))
      or exists (
           select 1 from public.orcamentos o join public.pedidos p on p.id = o.pedido_id
            where (p.cliente_id = (select auth.uid()) and o.profissional_id = outro and o.status <> 'rascunho')
               or (o.profissional_id = (select auth.uid()) and p.cliente_id = outro));
$$;

-- O logado é profissional que contratou ou orçou para este cliente (nota do cliente é restrita, 25.3).
create or replace function privado.eh_profissional_do_cliente(cliente uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.contratos c
                  where c.cliente_id = cliente and c.profissional_id = (select auth.uid()))
      or exists (select 1 from public.orcamentos o join public.pedidos p on p.id = o.pedido_id
                  where p.cliente_id = cliente and o.profissional_id = (select auth.uid()));
$$;

-- ---------------------------------------------------------------------------
-- Pedido, endereço e contrato
-- ---------------------------------------------------------------------------
create or replace function privado.eh_cliente_do_pedido(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.pedidos p
                  where p.id = pedido and p.cliente_id = (select auth.uid()));
$$;

create or replace function privado.eh_profissional_do_pedido(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.contratos c
                  where c.pedido_id = pedido and c.profissional_id = (select auth.uid()));
$$;

create or replace function privado.eh_parte_do_pedido(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.eh_cliente_do_pedido(pedido) or privado.eh_profissional_do_pedido(pedido);
$$;

create or replace function privado.eh_parte_do_contrato(contrato uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.contratos c
                  where c.id = contrato
                    and (select auth.uid()) in (c.cliente_id, c.profissional_id));
$$;

-- Pedido visível: dono; profissional que contratou, orçou ou conversou; profissional aprovado com a
-- categoria (não suspensa) e a região do pedido enquanto ele está aberto; equipe de atendimento.
-- Endereço completo NÃO passa por aqui (ver pode_ver_endereco).
create or replace function privado.pode_ver_pedido(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.pedidos p
     where p.id = pedido
       and (
            p.cliente_id = (select auth.uid())
         or exists (select 1 from public.contratos c
                     where c.pedido_id = p.id and c.profissional_id = (select auth.uid()))
         or exists (select 1 from public.orcamentos o
                     where o.pedido_id = p.id and o.profissional_id = (select auth.uid()))
         or exists (select 1 from public.conversas v
                     where v.pedido_id = p.id and v.profissional_id = (select auth.uid()))
         or (p.status = 'aberto'
             and (p.expira_em is null or p.expira_em > now())
             and exists (select 1 from public.perfis_profissional pp
                          where pp.usuario_id = (select auth.uid()) and pp.status = 'aprovado')
             and exists (select 1 from public.profissional_categorias pc
                          where pc.profissional_id = (select auth.uid())
                            and pc.categoria_id = p.categoria_id and pc.suspensa_em is null)
             and exists (select 1 from public.profissional_regioes pr
                          where pr.profissional_id = (select auth.uid())
                            and pr.cidade_id = p.cidade_id
                            and (pr.bairro is null or lower(pr.bairro) = lower(coalesce(p.bairro, '')))))
         or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador',
                              'financeiro', 'seguranca')
       )
  );
$$;

-- Endereço completo: o dono; o profissional do contrato ATIVO depois de liberado_em (N12);
-- segurança durante o atendimento; mediador quando há disputa.
create or replace function privado.pode_ver_endereco(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.pedidos_endereco e join public.pedidos p on p.id = e.pedido_id
     where e.pedido_id = pedido
       and (
            p.cliente_id = (select auth.uid())
         or (e.liberado_em is not null and e.liberado_em <= now()
             and exists (select 1 from public.contratos c
                          where c.pedido_id = p.id and c.profissional_id = (select auth.uid())
                            and c.status in ('ativo', 'concluido', 'em_disputa')))
         or (privado.eh_equipe('seguranca')
             and exists (select 1 from public.contratos c
                          where c.pedido_id = p.id and c.status in ('ativo', 'em_disputa')))
         or (privado.eh_equipe('mediador')
             and exists (select 1 from public.disputas d
                          where d.pedido_id = p.id and d.status <> 'cancelada'))
       )
  );
$$;

-- Orçamento visível: o autor; o cliente do pedido (menos rascunho); equipe de atendimento (menos rascunho).
create or replace function privado.pode_ver_orcamento(orcamento uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.orcamentos o join public.pedidos p on p.id = o.pedido_id
     where o.id = orcamento
       and (
            o.profissional_id = (select auth.uid())
         or (o.status <> 'rascunho'
             and (p.cliente_id = (select auth.uid())
                  or privado.eh_equipe('atendente_n1', 'atendente_n2', 'lider_suporte', 'mediador', 'financeiro')))
       )
  );
$$;

create or replace function privado.eh_parte_do_agendamento(agendamento uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.agendamentos a join public.contratos c on c.id = a.contrato_id
                  where a.id = agendamento and (select auth.uid()) in (c.cliente_id, c.profissional_id));
$$;

-- ---------------------------------------------------------------------------
-- Disputa, garantia, avaliação
-- ---------------------------------------------------------------------------
create or replace function privado.eh_parte_da_disputa(disputa uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.disputas d join public.contratos c on c.id = d.contrato_id
                  where d.id = disputa and (select auth.uid()) in (c.cliente_id, c.profissional_id));
$$;

create or replace function privado.eh_parte_da_garantia(garantia uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.garantias g join public.contratos c on c.id = g.contrato_id
                  where g.id = garantia and (select auth.uid()) in (c.cliente_id, c.profissional_id));
$$;

-- Mediador só entra no pedido/chat quando existe disputa (não cancelada) sobre ele.
create or replace function privado.mediador_com_disputa_no_pedido(pedido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.eh_equipe('mediador')
     and exists (select 1 from public.disputas d where d.pedido_id = pedido and d.status <> 'cancelada');
$$;

-- Nota do cliente não é pública (25.3): só ele, o profissional que o atende/atendeu e o moderador.
create or replace function privado.pode_ver_avaliacao(avaliacao uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.avaliacoes a
     where a.id = avaliacao
       and (
            a.avaliador_id = (select auth.uid())
         or a.avaliado_id = (select auth.uid())
         or privado.eh_equipe('moderador')
         or (a.status = 'publicada' and a.direcao = 'cliente_para_profissional')
         or (a.status = 'publicada' and a.direcao = 'profissional_para_cliente'
             and privado.eh_profissional_do_cliente(a.avaliado_id))
       )
  );
$$;

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------
create or replace function privado.eh_participante_da_conversa(conversa uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.conversas v
                  where v.id = conversa and (select auth.uid()) in (v.cliente_id, v.profissional_id));
$$;

create or replace function privado.mediador_da_conversa(conversa uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.conversas v
                  where v.id = conversa and privado.mediador_com_disputa_no_pedido(v.pedido_id));
$$;

-- ---------------------------------------------------------------------------
-- Mídias (e Storage)
-- ---------------------------------------------------------------------------
-- Foto do pedido: quem vê o pedido. Chat: só os participantes da conversa em que foi enviada.
-- Disputa: as partes se a evidência é visível a elas (ou se foram elas que enviaram). Demais: as partes.
create or replace function privado.pode_ver_midia(midia uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.midias m
     where m.id = midia
       and (
            m.enviada_por = (select auth.uid())
         or (m.finalidade = 'pedido' and privado.pode_ver_pedido(m.pedido_id))
         or (m.finalidade = 'chat'
             and (exists (select 1 from public.mensagens ms
                           where ms.midia_id = m.id and privado.eh_participante_da_conversa(ms.conversa_id))
                  or privado.mediador_com_disputa_no_pedido(m.pedido_id)))
         or (m.finalidade = 'disputa'
             and (exists (select 1 from public.disputa_evidencias de
                           where de.midia_id = m.id and de.visivel_as_partes
                             and privado.eh_parte_da_disputa(de.disputa_id))
                  or privado.eh_equipe('mediador', 'atendente_n2', 'lider_suporte')))
         or (m.finalidade not in ('pedido', 'chat', 'disputa')
             and (privado.eh_parte_do_pedido(m.pedido_id)
                  or privado.eh_equipe('atendente_n2', 'lider_suporte', 'mediador', 'seguranca')))
       )
  );
$$;

create or replace function privado.pode_ver_midia_por_caminho(balde text, caminho text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.midias m
                  where m.bucket = balde and m.storage_path = caminho and privado.pode_ver_midia(m.id));
$$;

-- ---------------------------------------------------------------------------
-- Ledger: o profissional enxerga só o que é da própria conta
-- ---------------------------------------------------------------------------
create or replace function privado.conta_e_minha(conta uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.contas_ledger c
                  where c.id = conta and c.usuario_id = (select auth.uid()));
$$;

create or replace function privado.lancamento_envolve_minha_conta(lancamento uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.partidas p join public.contas_ledger c on c.id = p.conta_id
                  where p.lancamento_id = lancamento and c.usuario_id = (select auth.uid()));
$$;

-- ---------------------------------------------------------------------------
-- Permissões das funções: ninguém de fora (anon, public) executa; só quem as policies precisam.
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema privado from public, anon;
grant execute on all functions in schema privado to authenticated, service_role;
