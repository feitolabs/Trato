-- ACERTO dos pedidos presos depois de pagamento expirado (DB-REORCAR).
-- RASCUNHO. Nada foi rodado em produção. Rodar o ARQUIVO INTEIRO só lê (o comando está
-- comentado). O comando grava: só com OK do João, e só depois da migration 20261127004000 e do
-- backend novo no ar (o backend antigo continuaria recusando o novo aceite).
--
-- "Preso" = pedido 'aberto', contrato 'aguardando_pagamento', orçamento dele ainda 'aceito', e
-- NADA de dinheiro: nenhum pagamento confirmado/reembolsado/contestado, nenhum pagamento
-- pendente (um Pix aberto ainda pode confirmar) e nenhum lançamento no livro.
-- O status do contrato NÃO serve para saber se foi pago: o backend não o atualiza.
--
-- 1) CONFERÊNCIA (somente leitura). pode_acertar = true são os candidatos; os demais ficam de
--    fora e precisam de análise manual.
select c.id as contrato_id, c.pedido_id, c.orcamento_id, c.criado_em, p.status as pedido,
       o.status as orcamento,
       (select count(*) from public.pagamentos g where g.contrato_id = c.id
           and (g.confirmado_em is not null
                or g.status in ('confirmado', 'reembolsado_parcial', 'reembolsado', 'contestado'))) as pagos,
       (select count(*) from public.pagamentos g where g.contrato_id = c.id and g.status = 'pendente') as pendentes,
       (select count(*) from public.lancamentos l where l.contrato_id = c.id) as lancamentos,
       exists (select 1 from public.pedido_historico h where h.pedido_id = c.pedido_id
                  and h.prova ->> 'acao' = 'expirar_pagamento') as expiracao_no_historico,
       (o.status = 'aceito'
        and not exists (select 1 from public.pagamentos g where g.contrato_id = c.id
              and (g.confirmado_em is not null or g.status not in ('falhou', 'expirado')))
        and not exists (select 1 from public.lancamentos l where l.contrato_id = c.id)) as pode_acertar
  from public.contratos c
  join public.pedidos p on p.id = c.pedido_id
  join public.orcamentos o on o.id = c.orcamento_id
 where p.status = 'aberto' and c.status = 'aguardando_pagamento'
 order by pode_acertar desc, c.criado_em;

-- 2) COMANDO (grava). Copiar o bloco, colar os contrato_id conferidos em v_ids e rodar.
--    Se qualquer um deixar de atender aos critérios, nada é gravado.
/*
begin;
do $acerto$
declare
  v_ids uuid[] := array[]::uuid[];   -- COLE AQUI: array['<contrato_id>', ...]::uuid[]
  v_orc uuid[];
begin
  if cardinality(v_ids) = 0 then
    raise exception 'Informe os contratos conferidos em v_ids';
  end if;
  lock table public.pagamentos, public.lancamentos in share row exclusive mode;
  perform 1 from public.pedidos where id in (select pedido_id from public.contratos where id = any (v_ids))
    order by id for update;
  with alvo as (
    update public.contratos c set status = 'cancelado'
      from public.pedidos p, public.orcamentos o
     where c.id = any (v_ids) and p.id = c.pedido_id and o.id = c.orcamento_id
       and p.status = 'aberto' and c.status = 'aguardando_pagamento' and o.status = 'aceito'
       and not exists (select 1 from public.pagamentos g where g.contrato_id = c.id
             and (g.confirmado_em is not null or g.status not in ('falhou', 'expirado')))
       and not exists (select 1 from public.lancamentos l where l.contrato_id = c.id)
    returning c.orcamento_id)
  select array_agg(orcamento_id) into v_orc from alvo;
  if coalesce(cardinality(v_orc), 0) <> cardinality(v_ids) then
    raise exception 'Só % de % contratos atendem aos critérios: nada foi gravado',
      coalesce(cardinality(v_orc), 0), cardinality(v_ids);
  end if;
  update public.orcamentos set status = 'expirado' where id = any (v_orc);
  perform public.registrar_auditoria(
            null, 'sistema', 'contrato.cancelado_pagamento_expirado', 'contrato', c.id,
            jsonb_build_object('contrato', 'aguardando_pagamento', 'orcamento', 'aceito'),
            jsonb_build_object('contrato', 'cancelado', 'orcamento', 'expirado'),
            'Acerto DB-REORCAR: pagamento expirado', null, null, null)
     from public.contratos c where c.id = any (v_ids);
  raise notice 'Acertados % contratos', cardinality(v_ids);
end
$acerto$;
commit;
*/
--    DESFAZER (só enquanto o pedido não tiver contrato novo nem outro orçamento aceito):
--      begin;
--      update public.contratos set status = 'aguardando_pagamento' where id = any (array[...]::uuid[]);
--      update public.orcamentos set status = 'aceito'
--       where id in (select orcamento_id from public.contratos where id = any (array[...]::uuid[]));
--      commit;
