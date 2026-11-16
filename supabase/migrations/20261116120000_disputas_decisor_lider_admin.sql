-- Alinha disputas_validar() aos papéis permitidos na API e no Painel Admin:
-- mediador, lider_suporte e administrador.
create or replace function public.disputas_validar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ctr public.contratos%rowtype;
  decisor public.equipe%rowtype;
  aprovador public.equipe%rowtype;
  valor_em_jogo bigint;
begin
  select * into ctr from public.contratos where id = new.contrato_id;

  if tg_op = 'INSERT' then
    if new.pedido_id is distinct from ctr.pedido_id then
      raise exception 'O pedido da disputa não é o pedido do contrato' using errcode = 'check_violation';
    end if;
    if new.aberta_por not in (ctr.cliente_id, ctr.profissional_id) then
      raise exception 'Só uma das partes do contrato abre disputa' using errcode = 'check_violation';
    end if;
  else
    if old.status in ('decidida', 'cancelada') then
      raise exception 'Disputa % não pode mais mudar', old.status using errcode = 'restrict_violation';
    end if;
  end if;

  if new.status = 'decidida' then
    select * into decisor from public.equipe where usuario_id = new.decidida_por;
    if not found or not decisor.ativo or decisor.revogado_em is not null
       or decisor.papel not in ('mediador', 'lider_suporte', 'administrador') then
      raise exception 'Só um mediador, líder de suporte ou administrador ativo decide a disputa'
        using errcode = 'check_violation';
    end if;
    valor_em_jogo := case new.decisao
                       when 'reembolso_total' then new.valor_congelado_centavos
                       when 'reembolso_parcial' then coalesce(new.valor_reembolso_centavos, 0)
                       else 0 end;
    if valor_em_jogo > coalesce(decisor.alcada_centavos, 0) then
      select * into aprovador from public.equipe where usuario_id = new.aprovada_por;
      if not found or not aprovador.ativo or aprovador.revogado_em is not null
         or aprovador.papel not in ('lider_suporte', 'administrador')
         or aprovador.usuario_id = new.decidida_por then
        raise exception 'Valor acima da alçada: exige aprovação de outra pessoa (líder de suporte ou administrador)'
          using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$$;

