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

## 6. Rodada 2: contrato das funções SQL da exclusividade (Banco B2) e do backend (B4a)
O dinheiro e a concorrência ficam em funções SQL atômicas, como na reserva de desconto (padrão já revisado pela Seguranca): `SECURITY DEFINER`, `set search_path = ''`, objetos qualificados, execute só `service_role`, transação, `pg_advisory_xact_lock` por profissional, `for update skip locked` nas rotinas. O ledger é o `moedas_lancamentos` (imutável), com `carteira = 'profissional'`. Saldo do profissional = soma de `quantidade` com `carteira = 'profissional'` e sem vencer (`expira_em is null or expira_em > p_agora`). Todas recebem `p_agora timestamptz` (testável). Migration `20261121200000_exclusividade_funcoes.sql` (+ rollback). Sem escrever nada no banco real sem OK.

1. `exclusividade_solicitar(p_profissional uuid, p_pedido uuid, p_chave text, p_agora timestamptz, p_custo int, p_max_simultaneas int, p_prazo_resposta_horas int, p_bloqueio_recusa_dias int) returns table (resultado text, exclusividade_id uuid, responder_ate timestamptz, saldo_restante int)`.
   `resultado`: `ok` | `ja_existe` (mesma `p_chave`: devolve a existente, sem cobrar de novo) | `saldo_insuficiente` | `limite_simultaneas` (conta `aguardando_cliente` e `ativa` do profissional) | `pedido_indisponivel` (pedido não está `aberto`, ou já tem exclusividade em andamento) | `pedido_urgente` (`pedidos.urgente`) | `categoria_sem_exclusividade` (`categorias.permite_exclusividade = false`, pela categoria do pedido) | `bloqueado_recusa` (o mesmo profissional foi recusado pelo mesmo cliente há menos de `p_bloqueio_recusa_dias`) | `proprio_pedido` (profissional = cliente do pedido). Se `ok`: cria a exclusividade `aguardando_cliente` com `responder_ate = p_agora + prazo`, e lança `exclusividade_uso` de `-p_custo` (carteira `profissional`, `parceiro_id` = cliente, `referencia_id` = exclusividade, chave `exclusividade-uso:<id>`). Nada muda quando `resultado <> 'ok'`. O pedido continua `aberto` enquanto `aguardando_cliente`.
2. `exclusividade_responder(p_exclusividade uuid, p_cliente uuid, p_decisao text, p_agora timestamptz, p_duracao_horas int) returns table (resultado text, expira_em timestamptz)`.
   `resultado`: `ok` | `nao_encontrada` (não existe ou não é do cliente) | `ja_respondida` | `prazo_vencido` (se `responder_ate < p_agora`: marca `expirada_sem_resposta` e estorna, como a rotina). `aceitar`: status `ativa`, `respondida_em`, `expira_em = p_agora + duração`, e o pedido vai de `aberto` para `reservado` na mesma transação (se o pedido não estiver mais `aberto`: cancela a oferta com estorno e devolve `pedido_indisponivel`). `recusar`: status `recusada`, `encerrada_em`, estorno integral (`exclusividade_estorno`, `+moedas_cobradas`, chave `exclusividade-estorno:<id>`), idempotente por status.
3. `exclusividade_expirar(p_agora timestamptz) returns table (exclusividade_id uuid, motivo text, profissional_id uuid, cliente_id uuid, pedido_id uuid)`. `motivo = 'sem_resposta'`: ofertas `aguardando_cliente` com `responder_ate < p_agora` viram `expirada_sem_resposta` com estorno. `motivo = 'sem_atendimento'`: `ativa` com `expira_em < p_agora` viram `expirada_sem_atendimento` SEM estorno, e o pedido volta de `reservado` para `aberto`. Idempotente por status; devolve só as recém-processadas.
4. `exclusividade_encerrar_por_pedido(p_pedido uuid, p_profissional_aceito uuid, p_agora timestamptz) returns table (exclusividade_id uuid, resultado text, profissional_id uuid)`. Usada quando o cliente aceita um orçamento ou cancela o pedido. Se existe exclusividade `aguardando_cliente` ou `ativa` no pedido: se `p_profissional_aceito` é o profissional da exclusividade, vira `concluida` (sem estorno; o pedido segue o fluxo normal); senão (outro profissional, ou nulo por cancelamento) vira `cancelada` com **estorno integral**. Idempotente por status. Quem muda o estado do pedido é o backend.
Índices únicos parciais já existentes garantem 1 exclusividade em andamento por pedido. Todas as cobranças e estornos usam `exclusividade_uso` e `exclusividade_estorno` do livro, nunca o orçamento de desconto da empresa.

Backend B4a (sem notificações e sem agendador, que ficam na B4b): `Estado.RESERVADO`, ações `RESERVAR_EXCLUSIVIDADE` e `EXPIRAR_EXCLUSIVIDADE` e transições (`reservado` → `aberto` | `orcamento_aceito` | `cancelado`); repositório em memória e Postgres de exclusividades chamando as 4 funções; rotas `POST /v1/profissional/exclusividades`, `GET /v1/profissional/exclusividades`, `GET /v1/pedidos/{id}/exclusividade`, `POST /v1/pedidos/{id}/exclusividade/{id}/responder`; `enviar_orcamento` bloqueia outros profissionais quando o pedido está `reservado` (só o profissional da exclusividade `ativa` envia) e a lista de pedidos abertos mostra `reservado` só a ele; aceitar orçamento e cancelar pedido chamam `exclusividade_encerrar_por_pedido`. Validações de 403 (profissional verificado, atende categoria e região) ficam no backend, antes da função SQL.
