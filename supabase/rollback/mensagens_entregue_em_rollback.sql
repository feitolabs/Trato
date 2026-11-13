-- Desfaz 20261112220000_mensagens_entregue_em.sql (volta ao gatilho da F3.7: só lida_em, uma vez).
create or replace function public.mensagens_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op <> 'UPDATE' then
    raise exception 'Mensagem não pode ser removida (% em %.%)', tg_op, tg_table_schema, tg_table_name
      using errcode = 'restrict_violation';
  end if;
  if old.lida_em is not null
     or new.lida_em is null
     or (new.id, new.conversa_id, new.autor_id, new.corpo, new.corpo_exibido, new.mascarada,
         new.midia_id, new.enviada_em)
        is distinct from
        (old.id, old.conversa_id, old.autor_id, old.corpo, old.corpo_exibido, old.mascarada,
         old.midia_id, old.enviada_em) then
    raise exception 'Mensagem não é editável: só lida_em pode ser preenchido, uma vez'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
alter table public.mensagens drop column entregue_em;
