-- DB-FIX69 (2): o atendente_n2 deixa de ler direto a foto da nota contestada e as provas da
-- contestação de nota de material (Termos 6.9). Ele não tem materiais_contestacao_analisar.
--
-- STATUS: PREPARADA, NÃO APLICADA. Aplicar só com o OK explícito do João (CLAUDE.md).
-- Depende de 20261029030500 (F3.8a) e de 20261125225400 (nota_material_contestacoes).
-- Reversão: supabase/rollback/20261126231900_n2_sem_midia_nota_contestada_rollback.sql
--
-- Regras:
--  * "Contestada" vale para contestação em QUALQUER status (inclusive já decidida).
--  * Foto da nota = notas_material.midia_id de nota com contestação (a nota inteira, mesmo quando
--    a contestação é de um item).
--  * Prova da contestação = id da mídia em nota_material_contestacoes.anexos (com ou sem hífens).
--  * Arquivo que TAMBÉM está em disputa_evidencias: o bloqueio da contestação PREVALECE para o
--    atendente_n2. Ele continua vendo as demais provas de disputa.
--  * Só mudam os acessos de EQUIPE do atendente_n2 nos ramos "disputa" e geral. Autor, partes,
--    demais papéis e os ramos "pedido" e "chat" ficam como antes. Por isso, anexo com finalidade
--    'pedido' continua seguindo privado.pode_ver_pedido (que inclui o atendente_n2).
--  * Só leitura direta (RLS de midias e do Storage). O backend usa service_role e confere a
--    permissão por conta própria.

begin;

-- Auxiliar usada só dentro de pode_ver_midia (que é SECURITY DEFINER): ninguém precisa de EXECUTE.
create or replace function privado.midia_de_nota_contestada(midia uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
           select 1
             from public.nota_material_contestacoes c
             join public.notas_material n on n.id = c.nota_id
            where n.midia_id = midia
         )
      or exists (
           select 1
             from public.nota_material_contestacoes c
            cross join lateral jsonb_array_elements_text(c.anexos) as a (arquivo)
            where lower(replace(a.arquivo, '-', '')) = replace(midia::text, '-', '')
         );
$$;
revoke all on function privado.midia_de_nota_contestada(uuid) from public, anon, authenticated, service_role;

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
                  or privado.eh_equipe('mediador', 'lider_suporte')
                  or (privado.eh_equipe('atendente_n2') and not privado.midia_de_nota_contestada(m.id))))
         or (m.finalidade not in ('pedido', 'chat', 'disputa')
             and (privado.eh_parte_do_pedido(m.pedido_id)
                  or privado.eh_equipe('lider_suporte', 'mediador', 'seguranca')
                  or (privado.eh_equipe('atendente_n2') and not privado.midia_de_nota_contestada(m.id))))
       )
  );
$$;

commit;
