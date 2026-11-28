-- Rollback de 20261127190100_trava_fraude_reversao.sql
-- RASCUNHO (DB-SEG-SQL). NÃO aplicado no Supabase de produção. Não toca em dados.
-- Volta a função da 001000. Rodar ANTES do rollback da 001000.

begin;

create or replace function public.medidas_conta_fraude_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_prazo integer;
begin
  if tg_op = 'INSERT' then
    if not new.motivo_fraude then
      return new;
    end if;
    if new.revertida_em is not null or new.revertida_por is not null then
      raise exception 'Trava por fraude deve nascer vigente, sem reversão'
        using errcode = 'check_violation';
    end if;
    if new.inicio_em > now() + interval '5 minutes' then
      raise exception 'Trava por fraude não pode começar no futuro'
        using errcode = 'check_violation';
    end if;
    v_prazo := public.trava_fraude_prazo_maximo_dias_vigente();
    -- dias de 24 h (não depende do fuso da sessão); fim nulo é barrado pelo check
    if new.fim_em > new.inicio_em + make_interval(hours => v_prazo * 24) then
      raise exception 'Trava por fraude passa do prazo máximo de % dias', v_prazo
        using errcode = 'check_violation';
    end if;
    if new.origem = 'analista' and not exists (
      select 1 from public.equipe q
       where q.usuario_id = new.aplicada_por and q.ativo and q.revogado_em is null
         and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')
    ) then
      raise exception 'Trava por fraude exige analista ativo com papel de análise'
        using errcode = 'check_violation';
    end if;
    return new;
  end if;

  if not old.motivo_fraude then
    return new;
  end if;
  if new.fim_em is distinct from old.fim_em and (new.fim_em is null or new.fim_em > old.fim_em) then
    raise exception 'A data final da trava por fraude só pode ser encurtada; renovar é medida nova'
      using errcode = 'restrict_violation';
  end if;
  if old.revertida_em is not null
     and (new.revertida_em is distinct from old.revertida_em
          or new.revertida_por is distinct from old.revertida_por) then
    raise exception 'Reversão de trava por fraude não muda' using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.medidas_conta_fraude_validar() from public, anon, authenticated, service_role;

commit;
