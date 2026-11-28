-- ===========================================================================
-- 20261127185000_aditivo_pago_uma_vez.sql
-- RASCUNHO (DB-SEG-A1). NÃO aplicada no Supabase de produção (OK só para arquivo).
-- Um aditivo não pode ter dois pagamentos 'confirmado', 'reembolsado_parcial' ou 'contestado'.
-- 'pendente', 'falhou', 'expirado' e 'reembolsado' (devolvido por inteiro) não contam.
-- Vale no INSERT e no UPDATE de status. Erro: SQLSTATE 23505, restrição
-- pagamentos_aditivo_pago_uidx.
-- Não apaga nem altera dado. Com duplicado já existente, falha e nada muda.
-- Antes: supabase/consultas/pre_checagem_aditivo_pago_unico.sql
--
-- Rollback: supabase/rollback/20261127185000_aditivo_pago_uma_vez_rollback.sql
-- ===========================================================================

begin;

-- segura gravações entre a conferência e a criação do índice
lock table public.pagamentos in share mode;

do $$
declare
  v_n     integer;
  v_lista text;
begin
  select count(*), string_agg(d.aditivo_id::text, ', ' order by d.aditivo_id)
    into v_n, v_lista
    from (select p.aditivo_id from public.pagamentos p
           where p.aditivo_id is not null and p.status in ('confirmado', 'reembolsado_parcial', 'contestado')
           group by p.aditivo_id having count(*) > 1) d;
  if v_n > 0 then
    raise exception 'Há % aditivo(s) pago(s) mais de uma vez; nada foi alterado. Resolva antes (estorno é decisão à parte). Aditivos: %',
      v_n, v_lista using errcode = 'unique_violation';
  end if;
end;
$$;

create unique index if not exists pagamentos_aditivo_pago_uidx
  on public.pagamentos (aditivo_id)
  where status in ('confirmado', 'reembolsado_parcial', 'contestado');

commit;
