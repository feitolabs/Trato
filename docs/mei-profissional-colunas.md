# MEI do profissional: colunas necessárias (nota para o agente Banco)

O backend (`backend/src/trato/profissional/mei.py`) hoje guarda o estado em memória
(`RepositorioMei` / `MeiEmMemoria`). Para persistir, falta uma migration e um adaptador Postgres
que implemente `obter(profissional_id)` e `salvar(registro)`. Sem migration criada pelo backend.

Sugestão: colunas em `perfis_profissionais` (ou tabela `profissional_mei` 1:1 por profissional).

| Coluna | Tipo | Regra |
|---|---|---|
| `cnpj` | `text` | 14 dígitos, só números; nulo se não informado. Índice único parcial (um CNPJ por profissional ativo). |
| `mei_status` | `text` | check in (`nao_informado`, `pendente`, `valido`, `invalido`); padrão `nao_informado`. |
| `mei_motivo` | `text` | frase curta em português mostrada ao app (extra, além das 3 pedidas). |
| `mei_validado_em` | `timestamptz` | nulo enquanto `pendente`/`nao_informado`. |
| `razao_social` | `text` | vem da BrasilAPI; nulo se não validou. |

Pontos de atenção:
- RLS: o profissional lê só a própria linha; escrita só pelo backend (service role).
- Leitura tolerante: se a coluna ainda não existe, o backend trata como `nao_informado`.
- `cnpj` e `razao_social` são dado cadastral: entram na lista de dados do LGPD/export.

## Rotas (contrato para o app)
- `GET /v1/profissional/mei` e `PUT /v1/profissional/mei` com `{"cnpj": "..."}`; só papel profissional.
- Saída: `cnpj`, `mei_status`, `motivo`, `razao_social`, `validado_em`, `pode_orcar_e_receber`.
- Com o bloqueio ligado (`TRATO_MEI_OBRIGATORIO=true`), `POST /v1/pedidos/{id}/orcamentos` dá 422
  sem `mei_status == valido`.
