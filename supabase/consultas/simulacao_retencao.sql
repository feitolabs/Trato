-- SIMULAÇÃO da guarda (14.8 e 16.3). SOMENTE LEITURA: um único SELECT. Precisa da
-- 20261127190500. NADA é apagado: mostra o que JÁ PODERIA ser tratado na data de referência.
-- O destino de cada tabela (excluir, anonimizar ou manter) é DECISÃO PENDENTE.
-- Para simular outra data, trocar now() em "ref". Bloqueios são os de HOJE.
-- 'acessos_conta' conta o que o expurgo apagaria agora (usa sempre a hora atual).
with ref as (select now() as em),
sit as (
  select s.* from public.pedidos p cross join ref
   cross join lateral public.retencao_pedido_situacao(p.id, ref.em) s
),
v as (select pedido_id from sit where situacao = 'vencido'),
ct as (select c.id from public.contratos c join v on v.pedido_id = c.pedido_id),
cv as (select c.id from public.conversas c join v on v.pedido_id = c.pedido_id),
meses as (
  select greatest(coalesce(max(p.valor), 6), 6)::integer as m
    from public.config_parametros p
    join public.config_versoes x on x.id = p.versao_id and x.status = 'vigente'
   where p.chave = 'acessos_conta_retencao_meses' and p.escopo_tipo = 'global'
)
select secao, item, quantidade from (
  select 1 as ordem, 'pedidos por situação' as secao, situacao as item, count(*) as quantidade
    from sit group by situacao
  union all
  select 2, 'bloqueios (pedidos não liberados)', b, count(*)
    from sit cross join lateral unnest(sit.bloqueios) b group by b
  union all
  select 3, 'registros de pedidos vencidos', t.item, t.n from (
    select 'pedidos' as item, (select count(*) from v) as n
    union all select 'pedidos_endereco', (select count(*) from public.pedidos_endereco e join v on v.pedido_id = e.pedido_id)
    union all select 'pedido_historico (imutável)', (select count(*) from public.pedido_historico h join v on v.pedido_id = h.pedido_id)
    union all select 'contratos', (select count(*) from ct)
    union all select 'mensagens', (select count(*) from public.mensagens m join cv on cv.id = m.conversa_id)
    union all select 'midias (provas; arquivo no Storage)', (select count(*) from public.midias m join v on v.pedido_id = m.pedido_id)
    union all select 'notas_material', (select count(*) from public.notas_material n join ct on ct.id = n.contrato_id)
    union all select 'avaliacoes', (select count(*) from public.avaliacoes a join ct on ct.id = a.contrato_id)
    union all select 'disputas', (select count(*) from public.disputas d join v on v.pedido_id = d.pedido_id)
    union all select 'pagamentos (registro financeiro)', (select count(*) from public.pagamentos g join ct on ct.id = g.contrato_id)
  ) t
  union all
  select 4, 'acessos (fora do prazo, sem bloqueio)', 'acessos_conta', count(*)
    from public.acessos_conta a cross join meses
   where a.ocorrido_em < now() - make_interval(months => meses.m)
     and not public.usuario_com_registros_preservados(a.usuario_id)
     and not exists (select 1 from public.acessos_conta_guardas g
                      where g.usuario_id = a.usuario_id and g.encerrada_em is null)
     and not exists (select 1 from public.disputas d join public.contratos c on c.id = d.contrato_id
                      where a.usuario_id in (c.cliente_id, c.profissional_id)
                        and d.status not in ('acordo', 'decidida', 'cancelada'))
     and not exists (select 1 from public.incidentes_seguranca i
                      where i.status <> 'encerrado' and i.envolvido_id = a.usuario_id)
     and not exists (select 1 from public.incidentes_seguranca i
                       join public.pedidos p on p.id = i.pedido_id
                      where i.status <> 'encerrado' and (p.cliente_id = a.usuario_id or exists
                        (select 1 from public.contratos c where c.pedido_id = p.id
                          and a.usuario_id in (c.cliente_id, c.profissional_id))))
     and not exists (select 1 from public.pedido_guardas pg join public.pedidos p on p.id = pg.pedido_id
                      where pg.encerrada_em is null and (p.cliente_id = a.usuario_id or exists
                        (select 1 from public.contratos c where c.pedido_id = p.id
                          and a.usuario_id in (c.cliente_id, c.profissional_id))))
) r
order by ordem, item;
