-- Reversão de 20261126231900_n2_sem_midia_nota_contestada.sql.
-- Restaura o corpo original de privado.pode_ver_midia (F3.8a) e remove a função auxiliar.
-- Os privilégios da função são preservados pelo create or replace. Não apaga dados.
-- Rodar ANTES do rollback de 20261125225400 (a auxiliar lê a tabela de contestações).

begin;

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

drop function if exists privado.midia_de_nota_contestada(uuid);

commit;
