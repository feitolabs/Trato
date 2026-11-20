# Etapa B: Tratinhos do profissional e exclusividade de 48h (plano de execução)

Plano do Mestre, 20/11/2026. Base: rascunho do agente Hydrogen (`etapa-b-exclusividade-spec.md`, na pasta de trabalho dele) e as decisões do João em `docs/decisoes-moedas-e-exclusividade.md` (as decisões do João valem mais que o rascunho). Cada tarefa abaixo é pequena (até 30 minutos). Dois agentes nunca mexem nos mesmos arquivos. Nada é aplicado no banco ou implantado sem o OK do João.

## 1. Decisões que fecham a spec (todas do João, 20/11/2026)
- Exclusividade exige um **pedido aberto elegível** do cliente (não urgente, categoria que permite). Fica atrelada a um `pedido_id`.
- Cliente responde em **6 horas** (configurável). Recusar ou ignorar: as 100 Tratinhos voltam inteiras na hora.
- "Atender" = o profissional **enviar o orçamento** dentro das 48h. Aceito o aceite do cliente, a exclusividade fica `ativa` por 48h.
- **Carteira do profissional separada da do cliente:** moeda de profissional nunca vira desconto pago pela empresa.
- Bônus do profissional: 50 Tratinhos, **1 por cliente, vitalício**, liberado após 7 dias sem disputa. Validade 90 dias.
- Cliente aceita **outro** orçamento antes das 48h: a exclusividade é liberada e as 100 Tratinhos voltam ao profissional.
- Depois de uma **recusa**, o mesmo profissional não pede exclusividade ao mesmo cliente por **30 dias** (configurável).
- **Urgência fora:** `pedidos.urgente = true` ou categoria urgente (vazamento, falta de luz, chaveiro). 48h sem atendimento: o profissional perde as 100.
- Máximo **3 exclusividades ao mesmo tempo** por profissional (conta `aguardando_cliente` e `ativa`). Custo **100**, duração **48h**.
- Textos: profissional "prioridade que você ganhou avaliando", nunca "comprar cliente". Cliente "Sem compromisso" e "Recusar e ver outros" com o mesmo destaque de "Aceitar".

## 2. Contrato do banco (rodada 1, nomes exatos)
Migration `supabase/migrations/20261121100000_exclusividade_schema.sql` (+ rollback). **Só esquema**, sem funções de exclusividade (rodada 2).
- `moedas_lancamentos`: coluna `carteira text not null default 'cliente' check (carteira in ('cliente','profissional'))`; `tipo` ganha `bonus_avaliacao_profissional`, `exclusividade_uso`, `exclusividade_estorno`; índice único parcial `(usuario_id, parceiro_id) where tipo = 'bonus_avaliacao_profissional'`; índice `(usuario_id, carteira, criada_em desc)`.
- `moedas_pendentes`: coluna `tipo_lancamento text not null default 'bonus_avaliacao' check in ('bonus_avaliacao','bonus_avaliacao_profissional')`; índice único parcial `(usuario_id, parceiro_id) where tipo_lancamento = 'bonus_avaliacao_profissional' and status in ('pendente','liberado')`.
- `moedas_config` (colunas novas): `bonus_avaliacao_profissional_moedas` 50, `exclusividade_custo_moedas` 100, `exclusividade_duracao_horas` 48, `exclusividade_max_simultaneas` 3, `exclusividade_prazo_resposta_horas` 6, `exclusividade_bloqueio_recusa_dias` 30.
- `categorias.permite_exclusividade boolean not null default true`. O UPDATE de dados das categorias urgentes NÃO entra na migration: vai como comentário com o comando.
- `pedidos.status` passa a aceitar `reservado`.
- Tabela `exclusividades` como no rascunho (profissional_id, cliente_id, pedido_id, status, moedas_cobradas, chave_idempotencia unique, criada_em, responder_ate, respondida_em, expira_em, encerrada_em, atualizado_em), com status `aguardando_cliente`, `ativa`, `recusada`, `expirada_sem_resposta`, `concluida`, `expirada_sem_atendimento`, `cancelada`; índice único parcial `(pedido_id) where status in ('aguardando_cliente','ativa')`; índices `(profissional_id, status)`, `(status, responder_ate)`, `(status, expira_em)`; RLS ligada, sem policy, grants só service_role.
- Correção obrigatória: recriar `moedas_reservar_desconto` (mesma assinatura da migration 20261120200000) para que o **saldo conte só a carteira `cliente`**.

## 3. Contrato do backend e do painel (rodada 1)
- Config em níveis: as 6 colunas novas lidas com fallback aos padrões; `GET/PUT /v1/admin/moedas/config` incluem os 6 campos (opcionais no PUT, motivo e auditoria como hoje).
- Saldo por carteira: o desconto usa só `carteira = 'cliente'`; o profissional usa `carteira = 'profissional'`.
- `GET /v1/me/moedas` passa a devolver também `saldo_profissional` (int) e `moedas_pendentes_profissional` (int).
- Bônus do profissional ao avaliar um cliente (`direcao = profissional_para_cliente`): pendente de 7 dias, chave `avaliacao-prof:<profissional_id>:<cliente_id>`, 1 por cliente; sem as colunas novas no banco, NÃO credita (fail-closed). Não consome o orçamento de desconto da empresa.

## 4. Rodadas
- **Rodada 1 (em paralelo, pastas diferentes):** Banco B1 (migration de esquema, só escrita), Backend B3 (carteira e bônus do profissional), Admin A1 (6 campos novos na tela de Tratinhos).
- **Aplicar B1 no Supabase** (OK do João) antes de implantar o Backend B3.
- **Rodada 2:** Banco B2 (funções SQL: solicitar, responder, expirar oferta, expirar 48h, concluir, cancelar por pedido; débito e estorno no livro), depois Backend B4 (serviço, rotas, estado `reservado`, rotina).
- **Rodada 3:** Flutter F1 (profissional) e F2 (cliente), depois uma revisão única da Seguranca e o deploy.

## 5. Ainda em aberto
- Mapear as categorias urgentes reais do catálogo (o Banco lista os `slug` do seed e propõe o UPDATE).
- O cliente pode cancelar uma exclusividade `ativa` sem aceitar outro orçamento? Rascunho propõe "a decidir"; fica para a rodada 2.
