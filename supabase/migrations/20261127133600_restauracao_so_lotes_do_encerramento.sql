-- ===========================================================================
-- 20261127133600_restauracao_so_lotes_do_encerramento.sql
-- RASCUNHO (DB-SEG-M6). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Termos v1.2: 13.10 e I.11. Depende de 20261127092000.
--
-- Corrige moedas_restauracao_devida. A conta antiga, saldo(início) - saldo(agora), via também
-- créditos criados DEPOIS do encerramento: um deles, vencido antes da restauração, aumentava o
-- devido (devolvia mais do que venceu dos Tratinhos guardados).
--
-- REGRA: simula TODOS os lançamentos do usuário e carteira (mesma ordem e consumo de
-- moedas_saldo) e acompanha, em cada crédito, quantas unidades são "do encerramento":
--   a) crédito com criada_em <= inicio_em: todas;
--   b) crédito posterior de tipo 'estorno' ou 'exclusividade_estorno' com a MESMA expira_em do
--      crédito de onde o gasto saiu: as unidades do encerramento que aquele gasto tirou de
--      créditos com essa validade, cada uma devolvida uma vez só;
--   c) qualquer outro crédito posterior (inclusive estorno com validade nova): nenhuma.
-- Gasto em crédito misto tira primeiro o que não é do encerramento (a favor do usuário); o mesmo
-- vale para dívida abatida por um crédito novo.
-- Devido = soma das unidades do encerramento que SOBRARAM em créditos com
-- inicio_em < expira_em <= max(p_agora, inicio_em).
-- Ligação estorno -> gasto, pela chave: 'estorno-uso:<c>[:...]' -> 'uso:<c>';
-- 'exclusividade-estorno:<id>[:n]' -> 'exclusividade-uso:<id>'.
-- Se a 20261127092000 for rodada de novo depois, rodar esta de novo.
--
-- Mesma assinatura e grants; o gatilho da restauração já usa esta função. Não altera dados.
-- Se moedas_saldo mudar a ordem de consumo, mudar aqui também.
--
-- Rollback: supabase/rollback/20261127133600_restauracao_so_lotes_do_encerramento_rollback.sql
-- ===========================================================================

begin;

do $$
begin
  if to_regprocedure('public.moedas_restauracao_devida(uuid,text,timestamptz)') is null then
    raise exception 'Aplique antes a migration 20261127092000_tratinhos_guarda_restauracao';
  end if;
end;
$$;

create or replace function public.moedas_restauracao_devida(
  p_medida uuid, p_carteira text, p_agora timestamptz default now())
returns integer
language plpgsql stable security definer set search_path = ''
as $$
declare
  r         record;
  v_usuario uuid;
  v_inicio  timestamptz;
  v_fim     timestamptz;
  v_criada  timestamptz[] := '{}';
  v_expira  timestamptz[] := '{}';
  v_resto   bigint[]      := '{}';
  v_n       integer       := 0;
  v_devendo bigint        := 0;
  v_pago    bigint;
  v_falta   bigint;
  v_tirado  bigint;
  v_idx     integer;
  v_total   bigint        := 0;
  v_eleg    bigint[]      := '{}';  -- unidades do encerramento dentro de v_resto
  -- o que cada gasto tirou dessas unidades e ainda não foi devolvido
  g_chave   text[]        := '{}';
  g_expira  timestamptz[] := '{}';
  g_eleg    bigint[]      := '{}';
  v_origem  bigint;
  v_parte   bigint;
  v_k       integer;
begin
  select m.usuario_id, m.inicio_em into v_usuario, v_inicio
    from public.medidas_conta m
   where m.id = p_medida and m.tipo = 'encerramento';
  if not found then
    return null;
  end if;
  if p_carteira is null or p_carteira not in ('cliente', 'profissional') or p_agora is null then
    raise exception 'parâmetros inválidos para moedas_restauracao_devida';
  end if;
  v_fim := greatest(p_agora, v_inicio);

  for r in
    select l.criada_em, l.expira_em, l.quantidade, l.chave_idempotencia, l.tipo
      from public.moedas_lancamentos l
     where l.usuario_id = v_usuario
       and l.carteira = p_carteira
     order by l.criada_em asc, (l.quantidade < 0) asc, l.chave_idempotencia collate "C" asc
  loop
    if r.quantidade > 0 then
      v_pago := least(r.quantidade::bigint, v_devendo);
      v_devendo := v_devendo - v_pago;
      v_n := v_n + 1;
      v_criada[v_n] := r.criada_em;
      v_expira[v_n] := r.expira_em;
      v_resto[v_n]  := r.quantidade::bigint - v_pago;
      v_origem := 0;
      if r.criada_em <= v_inicio then
        v_origem := r.quantidade;
      elsif r.tipo in ('estorno', 'exclusividade_estorno') and r.expira_em is not null then
        for v_k in 1..coalesce(array_length(g_chave, 1), 0) loop
          exit when v_origem = r.quantidade;
          if g_expira[v_k] = r.expira_em and g_eleg[v_k] > 0 and exists (
               select 1
                 from (select case
                                when r.tipo = 'estorno' and starts_with(g_chave[v_k], 'uso:')
                                  then 'estorno-uso:' || substr(g_chave[v_k], 5)
                                when r.tipo = 'exclusividade_estorno'
                                     and starts_with(g_chave[v_k], 'exclusividade-uso:')
                                  then 'exclusividade-estorno:' || substr(g_chave[v_k], 19)
                              end as base) b
                where r.chave_idempotencia = b.base or starts_with(r.chave_idempotencia, b.base || ':')) then
            v_parte := least(g_eleg[v_k], r.quantidade - v_origem);
            g_eleg[v_k] := g_eleg[v_k] - v_parte;
            v_origem := v_origem + v_parte;
          end if;
        end loop;
      end if;
      v_eleg[v_n] := least(v_origem, v_resto[v_n]);
    else
      v_falta := (-r.quantidade)::bigint;

      if v_n > 0 and v_falta > 0 then
        for v_idx in
          select i
            from generate_series(1, v_n) as g(i)
           where v_resto[i] > 0
             and (v_expira[i] is null or v_expira[i] > r.criada_em)
           order by (v_expira[i] is null) asc, v_expira[i] asc nulls last, v_criada[i] asc, i asc
        loop
          v_tirado := least(v_resto[v_idx], v_falta);
          if v_tirado > 0 then
            v_parte := greatest(v_tirado - (v_resto[v_idx] - v_eleg[v_idx]), 0);
            if v_parte > 0 then
              v_eleg[v_idx] := v_eleg[v_idx] - v_parte;
              g_chave := g_chave || r.chave_idempotencia;
              g_expira := array_append(g_expira, v_expira[v_idx]);
              g_eleg := g_eleg || v_parte;
            end if;
            v_resto[v_idx] := v_resto[v_idx] - v_tirado;
            v_falta := v_falta - v_tirado;
          end if;
          exit when v_falta = 0;
        end loop;
      end if;

      if v_n > 0 and v_falta > 0 then
        for v_idx in
          select i
            from generate_series(1, v_n) as g(i)
           where v_resto[i] > 0
             and v_expira[i] is not null
             and v_expira[i] <= r.criada_em
           order by v_expira[i] desc, v_criada[i] desc, i asc
        loop
          v_tirado := least(v_resto[v_idx], v_falta);
          if v_tirado > 0 then
            v_parte := greatest(v_tirado - (v_resto[v_idx] - v_eleg[v_idx]), 0);
            if v_parte > 0 then
              v_eleg[v_idx] := v_eleg[v_idx] - v_parte;
              g_chave := g_chave || r.chave_idempotencia;
              g_expira := array_append(g_expira, v_expira[v_idx]);
              g_eleg := g_eleg || v_parte;
            end if;
            v_resto[v_idx] := v_resto[v_idx] - v_tirado;
            v_falta := v_falta - v_tirado;
          end if;
          exit when v_falta = 0;
        end loop;
      end if;

      v_devendo := v_devendo + v_falta;
    end if;
  end loop;

  if v_n > 0 then
    for v_idx in 1..v_n loop
      if v_eleg[v_idx] > 0 and v_expira[v_idx] > v_inicio and v_expira[v_idx] <= v_fim then
        v_total := v_total + v_eleg[v_idx];
      end if;
    end loop;
  end if;

  return v_total::integer;
end;
$$;
revoke all on function public.moedas_restauracao_devida(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.moedas_restauracao_devida(uuid, text, timestamptz) to service_role;

commit;
