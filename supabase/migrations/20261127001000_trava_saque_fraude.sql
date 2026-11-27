-- ===========================================================================
-- 20261127001000_trava_saque_fraude.sql
-- RASCUNHO (DB-TRAVA-FRAUDE). NÃO aplicada no Supabase de produção. Aguarda OK do João
-- (o OK dado vale só para criar o arquivo).
-- Termos v1.2: 20.6 (reter por fraude pelo tempo necessário à apuração, sem passar do prejuízo
-- apurado), 20.2 (automática no máximo 72 h), 17.4.
-- Depende de 20261125224600_medidas_conta e 20261126213500_retorno_e_impedimento_conta.
--
-- O que acrescenta (nenhum dado existente é alterado):
--   1. public.medidas_conta: `motivo_fraude` (padrão false) e `limite_retencao_centavos`
--      (teto da retenção = prejuízo apurado). As travas antigas ficam false/nulo: não seguram nada.
--   2. Regras: fraude só em 'trava_saque'; limite obrigatório e > 0 com fraude, nulo sem fraude;
--      fraude exige data final de no máximo o prazo configurado a partir do início; início não
--      pode ser futuro; nasce não revertida; trava de analista exige papel de análise ativo.
--      A automática continua limitada a 72 h (check já existente).
--   3. Depois de gravada: motivo_fraude e limite não mudam; a data final só pode ser encurtada;
--      reversão não é desfeita. RENOVAR = medida nova (analista, motivo, limite e data final).
--      Vencida (fim_em <= agora) ou revertida, deixa de valer sozinha: nada precisa rodar.
--   4. config_definicoes: `trava_fraude_prazo_maximo_dias` (1 a 90, dupla aprovação). Nenhum valor
--      é gravado; sem valor publicado vale 30. Mudar o prazo não altera travas já gravadas.
--
-- Papéis conferidos no banco para trava por fraude de analista (equipe ativa e não revogada):
--   mediador, lider_suporte, seguranca, administrador
--
-- Rollback: supabase/rollback/20261127001000_trava_saque_fraude_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if not exists (select 1 from pg_attribute
                  where attrelid = to_regclass('public.medidas_conta')
                    and attname = 'infracao_grave' and not attisdropped) then
    raise exception 'Aplique antes as migrations 20261125224600 e 20261126213500';
  end if;
end;
$$;

alter table public.medidas_conta
  add column if not exists motivo_fraude boolean not null default false,
  add column if not exists limite_retencao_centavos bigint;

alter table public.medidas_conta drop constraint if exists medidas_conta_motivo_fraude_check;
alter table public.medidas_conta add constraint medidas_conta_motivo_fraude_check
  check (not motivo_fraude or tipo = 'trava_saque');

alter table public.medidas_conta drop constraint if exists medidas_conta_limite_retencao_check;
alter table public.medidas_conta add constraint medidas_conta_limite_retencao_check
  check (case when motivo_fraude
              then limite_retencao_centavos is not null and limite_retencao_centavos > 0
              else limite_retencao_centavos is null end);

alter table public.medidas_conta drop constraint if exists medidas_conta_fraude_prazo_check;
alter table public.medidas_conta add constraint medidas_conta_fraude_prazo_check
  check (not motivo_fraude or fim_em is not null);

insert into public.config_definicoes (
  chave, descricao, unidade, minimo, maximo, escopos_permitidos, exige_dupla_aprovacao
)
values (
  'trava_fraude_prazo_maximo_dias',
  'Prazo máximo de cada trava de saque por fraude, contado do início (20.6)',
  'dias', 1, 90, array['global'], true
)
on conflict (chave) do nothing;

create or replace function public.trava_fraude_prazo_maximo_dias_vigente()
returns integer
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select p.valor::integer
       from public.config_parametros p
       join public.config_versoes v on v.id = p.versao_id
      where v.status = 'vigente'
        and p.chave = 'trava_fraude_prazo_maximo_dias'
        and p.escopo_tipo = 'global'
      limit 1),
    30
  );
$$;
revoke all on function public.trava_fraude_prazo_maximo_dias_vigente() from public, anon, authenticated;
grant execute on function public.trava_fraude_prazo_maximo_dias_vigente() to service_role;

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

drop trigger if exists medidas_conta_fraude_proteger on public.medidas_conta;
create trigger medidas_conta_fraude_proteger before update on public.medidas_conta
  for each row execute function public.proteger_colunas('motivo_fraude', 'limite_retencao_centavos');
drop trigger if exists medidas_conta_fraude_validar_trg on public.medidas_conta;
create trigger medidas_conta_fraude_validar_trg before insert or update on public.medidas_conta
  for each row execute function public.medidas_conta_fraude_validar();

commit;
