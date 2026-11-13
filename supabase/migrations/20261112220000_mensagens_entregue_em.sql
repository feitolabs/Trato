-- Chat: "recebido" (✓✓ cinza). A mensagem passa a guardar quando chegou ao aparelho de quem recebeu.
-- RASCUNHO: não aplicado. Só acrescenta uma coluna anulável e troca o gatilho de proteção.
--
-- Regras (as mesmas da `lida_em`): cada data é preenchida UMA vez (nulo -> data); o resto da
-- mensagem continua imutável. Ler implica receber: se `lida_em` for preenchida sem `entregue_em`,
-- o gatilho completa `entregue_em` com a mesma hora.

alter table public.mensagens add column entregue_em timestamptz;

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
  -- Nada além das duas datas muda.
  if (new.id, new.conversa_id, new.autor_id, new.corpo, new.corpo_exibido, new.mascarada,
      new.midia_id, new.enviada_em)
     is distinct from
     (old.id, old.conversa_id, old.autor_id, old.corpo, old.corpo_exibido, old.mascarada,
      old.midia_id, old.enviada_em) then
    raise exception 'Mensagem não é editável: só entregue_em e lida_em podem ser preenchidos, uma vez'
      using errcode = 'restrict_violation';
  end if;
  -- Cada data só vai de nulo para um valor, nunca volta nem muda.
  if (old.lida_em is not null and new.lida_em is distinct from old.lida_em)
     or (old.entregue_em is not null and new.entregue_em is distinct from old.entregue_em) then
    raise exception 'Mensagem não é editável: entregue_em e lida_em só são preenchidos uma vez'
      using errcode = 'restrict_violation';
  end if;
  if new.lida_em is not null and new.entregue_em is null then
    new.entregue_em := new.lida_em;
  end if;
  return new;
end;
$$;
