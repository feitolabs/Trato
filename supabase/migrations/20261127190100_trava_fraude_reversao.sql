-- ===========================================================================
-- 20261127190100_trava_fraude_reversao.sql
-- RASCUNHO (DB-SEG-SQL). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 20.6. Depende de 20261127001000.
-- Na primeira reversão da trava por fraude, revertida_por tem de ser da equipe ativa, com papel
-- mediador, lider_suporte, seguranca ou administrador (os mesmos de quem aplica).
-- Erro: SQLSTATE 23514. Se a 001000 rodar de novo, rodar esta de novo.
--
-- Rollback: supabase/rollback/20261127190100_trava_fraude_reversao_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.medidas_conta_fraude_validar()') is null then
    raise exception 'Aplique antes a migration 20261127001000_trava_saque_fraude';
  end if;
end;
$$;

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
  if old.revertida_em is null and new.revertida_em is not null and not exists (
    select 1 from public.equipe q
     where q.usuario_id = new.revertida_por and q.ativo and q.revogado_em is null
       and q.papel in ('mediador', 'lider_suporte', 'seguranca', 'administrador')
  ) then
    raise exception 'Reversão de trava por fraude exige analista ativo com papel de análise'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.medidas_conta_fraude_validar() from public, anon, authenticated, service_role;

commit;
