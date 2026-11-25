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

## Persistência no Postgres (implementada)
- Adaptador: `backend/src/trato/persistencia/mei.py` (`MeiPostgres`), usado pela rota quando o app
  roda com banco; a memória só nos testes.
- `cnpj` só é gravado quando `mei_status = 'valido'`. Pendente e inválido gravam só estado e motivo
  (cnpj nulo), para não ocupar `ux_perfis_profissional_cnpj` (evita squatting). Por isso o
  pendente não guarda o CNPJ: o app manda o CNPJ de novo para tentar outra vez.
- Violação de unicidade (23505) vira "CNPJ em uso" dentro do backend e a API responde 422 com o
  mesmo texto de "CNPJ não validado", sem revelar que o número existe.
- Quem já está `valido` não perde o MEI por uma tentativa que falhou.
- `PUT /v1/profissional/mei`: 422 com `detail` curto quando o resultado é inválido; limite de
  5 por hora por usuário (regra `mei_cnpj` em `seguranca/config.py`).
- `TRATO_MEI_OBRIGATORIO` continua desligado (só o João liga).
