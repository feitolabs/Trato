# Seeds do banco (Trato)

Arquivos revisáveis. **Nada foi aplicado em banco real.** Testado só em Postgres local descartável.
Cada seed é idempotente e tem rollback. Todos os valores estão em **um** arquivo: `supabase/seeds/parametros.sql`.

| Seed | Arquivo | Rollback | Depende de |
|---|---|---|---|
| 1 | `supabase/seeds/seed_cidades_categorias.sql` | `supabase/rollback/seed_cidades_categorias_rollback.sql` | P6/P15 |
| 2 | `supabase/seeds/seed_config_taxa.sql` | `supabase/rollback/seed_config_taxa_rollback.sql` | P1, P2, primeiro administrador |
| 3 | `supabase/seeds/seed_contas_ledger.sql` | `supabase/rollback/seed_contas_ledger_rollback.sql` | **P7** |
| 4 | `supabase/seeds/seed_equipe_admin.sql` (só modelo comentado) | idem | João cria o administrador |

## Como rodar (só depois do OK)

Tudo na **mesma sessão**, porque `parametros.sql` cria tabelas temporárias que os seeds leem:

```bash
cat supabase/seeds/parametros.sql supabase/seeds/seed_cidades_categorias.sql supabase/seeds/seed_config_taxa.sql supabase/seeds/seed_contas_ledger.sql | psql "$URL_DO_BANCO"
```

Cada seed roda dentro de uma transação: se faltar um valor, **aborta e não grava nada**, dizendo qual valor falta (`A DEFINIR PELO JOÃO: ...`).
Ordem: 4 (à mão) → 1 → 2 → 3. Rollback: ordem inversa, com `parametros.sql` antes, na mesma sessão.

Teste: `python -I supabase/testes/testar_seeds.py <raiz> <pasta-temporaria>` (venv fora do projeto com `pgserver` e `psycopg2-binary`). 62 verificações: aborto sem parâmetros, idempotência (aplicar 2 vezes), min/max, tabela progressiva desligada, gás/estrutural recusados, aprovação dupla, versão imutável, ledger imutável, rollback e reaplicação.

---

## Seed 1 — `seed_cidades_categorias`

```
PRECISO DO SEU OK
O que:    Criar a cidade do piloto (inativa) e 2 ou 3 categorias de baixo risco, cada uma com 4 perguntas
          guiadas + 1 pergunta de triagem ("envolve obra estrutural ou gás?"), e a garantia/retrabalho em dias.
Por que:  A V2 manda piloto em UMA cidade e 2 ou 3 categorias de escopo observável (P15).
Risco:    Baixo. Só INSERT em cidades, categorias e categoria_perguntas. Conflito = não faz nada.
          O seed recusa nomes com gás, estrutural, fundação, alvenaria, laje.
          A cidade nasce com ativa = false: nenhum pedido entra até o João abrir.
Como desfazer: seed_cidades_categorias_rollback.sql. Se já houver pedido ou profissional ligado, ele falha
          sem apagar (FK RESTRICT); aí use ativa = false.
Posso continuar?
```

**Valores que o João informa** (em `parametros.sql`):

| Chave | O que é | Hoje |
|---|---|---|
| `cidade_nome`, `cidade_uf` | Cidade do piloto (P6/P15). Sugestão do harness: Belo Horizonte / MG, **não confirmada** | NULL |
| `cidade_ativa` | `true` abre a cidade | `false` |
| `cidade_lat`, `cidade_lng` | Centro (opcional) | NULL |
| `cat1_garantia_dias`, `cat2_garantia_dias` | Garantia/retrabalho de cada categoria, em dias | NULL |
| `cat3_incluir`, `cat3_garantia_dias` | Terceira categoria (opcional) e sua garantia | `false` / NULL |
| `catN_nome`, `catN_slug` | Nomes sugeridos: Limpeza residencial, Montagem de móveis, Pintura de interiores. São sugestão do agente | preenchidos |

As perguntas guiadas são texto editorial dentro do seed; revise. Se trocar uma categoria, troque as perguntas da vaga.
A resposta "sim" na triagem de obra estrutural/gás precisa ser tratada pelo backend (bloquear o pedido); o seed só cria a pergunta.

---

## Seed 2 — `seed_config_taxa`

```
PRECISO DO SEU OK
O que:    Criar o catálogo de configuração (13 chaves com min/max) e UMA versão em RASCUNHO com: taxa única
          (bps) e mínimo (centavos), prazos (liberação, janela de reclamação, resposta em 48 h, decisão em
          5 dias úteis, retrabalho em 7 dias) e limites. A tabela progressiva (D2) fica DESLIGADA.
Por que:  O backend lê taxa e prazos da configuração; nada fixo no código (regra de dinheiro do escopo).
Risco:    Baixo. O rascunho não vale para nenhum contrato. O seed nunca aprova nem publica.
          Depois de aprovada, a versão é imutável (trigger): erro se corrige com versão nova.
Como desfazer: seed_config_taxa_rollback.sql apaga o rascunho. Se já foi aprovada, ABORTA (não se apaga
          versão aprovada); publique uma nova versão.
Posso continuar?
```

**Quem aprova (aprovação dupla):** o rascunho é criado por quem está em `config_criada_por` (o administrador).
Quem **aprova é outra pessoa da equipe** (sugestão: financeiro ou jurídico; o João decide). O banco garante `criada_por <> aprovada_por`.
A publicação (aprovada → vigente) é do backend. Taxa e prazos financeiros têm `exige_dupla_aprovacao = true`.

**Valores que o João informa:**

| Chave | O que é | Hoje |
|---|---|---|
| `config_criada_por` | uuid de quem está em `public.equipe` (o primeiro administrador, seed 4) | NULL |
| `taxa_bps` | Taxa única (P2). Ex.: 750 = 7,5%. **Mais** minimo e maximo da trava | NULL |
| `taxa_minima_centavos` | Taxa mínima por serviço em centavos (0 = sem mínimo) (P2). **Mais** minimo e maximo | NULL |
| `prazo_liberacao_dias` | Liberação do pagamento (P1: 7 dias ou 48 h?) | NULL (limites 1..30, sugestão do agente) |
| `prazo_confirmacao_cliente_horas` | Confirmação do cliente (P1), opcional | NULL (12..168) |
| `prazo_congelar_disputa_horas` | Prazo para abrir disputa e congelar o repasse (escopo 72 h × D3: P17/N17), opcional | NULL (24..168) |
| `janela_chargeback_dias` | Janela de reclamação | 7 (D3) |
| `prazo_resposta_disputa_horas` | Resposta da outra parte | 48 (escopo 3.5) |
| `prazo_decisao_disputa_dias_uteis` | Decisão do Trato | 5 (escopo 3.5) |
| `prazo_retrabalho_atendimento_dias` | Atendimento do retrabalho | 7 (escopo 3.6) |
| `garantia_retrabalho_dias_padrao` | Garantia padrão (categoria tem a sua) | 30 (escopo 3.6) |
| `valor_minimo_servico_centavos` | Valor mínimo do serviço | 3000 (escopo 8.2) |
| `limite_orcamentos_por_pedido` | Máximo de orçamentos por pedido | 5 (escopo 4) |
| `minimo`/`maximo` de cada chave | Trava de segurança; os já preenchidos são **sugestão do agente** | ver arquivo |
| `taxa_progressiva_ativa` | **Deve ficar 0**: o seed recusa outro valor (D2 em espera até a simulação de margem) | 0 |
| `seed_faixa` (3 linhas) | Faixas da tabela progressiva. Opcional; entram, mas a tabela continua desligada | vazias |

Fora desta versão, de propósito: `adiantamento_bps` (D5 em espera), `parcelas_max_cartao` (P3), `limite_valor_72h` (P1).

Limite do teste local: o Postgres embutido não tem `btree_gist`, então o EXCLUDE de faixas sobrepostas não é exercitado (só roda no Supabase).

---

## Seed 3 — `seed_contas_ledger`

```
PRECISO DO SEU OK
O que:    Criar 4 contas de SISTEMA do ledger no caminho A (espelho do provedor): a_receber_do_provedor
          (ativo), receita_taxa (receita), custo_provedor (despesa), estornos_reembolsos (despesa).
          Nenhum nome é específico de um provedor.
Por que:  O ledger precisa dessas contas para registrar cobrança, taxa e custo sem guardar saldo do Trato (D15).
Risco:    DEPENDE DO P7. Se o parceiro/caminho mudar, os códigos podem mudar; conta com lançamento nunca
          mais sai (ledger imutável). Por isso o seed só roda com ledger_p7_confirmado = 'true'.
Como desfazer: seed_contas_ledger_rollback.sql só vale ANTES de qualquer lançamento (desliga o trigger de
          DELETE só dentro da transação). Com partidas nas contas, ABORTA: correção é por estorno.
Posso continuar?
```

**Valores que o João informa:** `ledger_p7_confirmado` = `'true'` quando responder o P7 (hoje `false`).
Contas **por usuário** (`a_pagar_profissional`, uma por profissional) **não entram em seed**: o backend cria no primeiro uso.

Ponto a decidir junto com o P7: o modelo de dados citava também `retido_servico`, que não estava no pedido e não foi criada.
Os códigos antigos (`caixa_parceiro`, `receita_trato`, `despesa_stripe`) só aparecem nos testes das migrations, não no backend.

---

## Seed 4 — `seed_equipe_admin` (só modelo)

```
PRECISO DO SEU OK
O que:    Nada é executado. O arquivo só descreve, comentado, como o João cria o primeiro administrador:
          criar o usuário no painel do Supabase e inserir uma linha em usuarios e equipe com o uuid dele.
Por que:  config_versoes.criada_por exige alguém em equipe; a aprovação dupla exige uma segunda pessoa.
Risco:    Nenhum no arquivo. E-mail, senha e uuid reais NUNCA entram no repositório (o teste confere que
          não há e-mail no arquivo).
Como desfazer: revogar (ativo = false) em vez de apagar; ver o rollback comentado.
Posso continuar?
```

**O João faz:** criar o administrador e uma segunda pessoa (ex.: financeiro) e informar o uuid do administrador em `config_criada_por`.

---

## Lista única do que o João precisa informar

1. **Cidade do piloto**: nome e UF (P6/P15). Abrir (`cidade_ativa`) agora ou depois.
2. **Categorias**: confirmar ou trocar os nomes sugeridos; incluir a 3ª ou não; revisar as perguntas.
3. **Garantia/retrabalho em dias** de cada categoria.
4. **Taxa única** em bps e **taxa mínima** em centavos (P2), com as travas minimo/maximo de cada uma.
5. **Prazo de liberação** (P1) e, se valer, confirmação do cliente em horas.
6. **Prazo para congelar o repasse numa disputa** (se aplicável; N17/P17).
7. Confirmar ou trocar os valores marcados "sugestão do escopo" (7 dias, 48 h, 5 dias úteis, 7 dias, 30 dias, R$ 30, 5 orçamentos) e as travas "sugestão do agente".
8. **P7**: caminho A confirmado → `ledger_p7_confirmado = 'true'`.
9. **Primeiro administrador** e uma segunda pessoa para aprovar (criados por ele, no painel).
