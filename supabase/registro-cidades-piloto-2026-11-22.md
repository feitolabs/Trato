# Registro — ajuste de cidades do piloto (22/11/2026)

OK do João (via Mestre, "já temos") para 2 UPDATEs pontuais em `public.cidades`, por `id`, em produção. Nenhum outro INSERT/UPDATE/DELETE foi feito.

## Aplicado

**Divinópolis** — `id = d54b518b-6ed2-4de5-b8e4-8ebac0e92d90`
- Antes: `nome = 'Divinopolis'`, `ativa = true`, `centro_lat = NULL`, `centro_lng = NULL`
- Depois: `nome = 'Divinópolis'`, `ativa = true`, `centro_lat = -20.1386`, `centro_lng = -44.8839`

**Belo Horizonte** — `id = de470309-afb7-49ac-9471-54e8387d4a88`
- Antes: `nome = 'Belo Horizonte'`, `ativa = true`, `centro_lat = NULL`, `centro_lng = NULL`
- Depois: `nome = 'Belo Horizonte'` (inalterado), `ativa = true` (inalterado), `centro_lat = -19.9167`, `centro_lng = -43.9345`

Transação única, `COMMIT` só após confirmar `rowcount = 1` nos dois `UPDATE`s. Antes/depois das demais linhas de `public.cidades`: `total_rows = 2` (só essas duas existem na tabela), e o digest SHA-256 das linhas fora dessas duas (vazio) não mudou. Categoria `[TESTE] Desenvolvimento de software` seguiu `ativa = true`, sem alteração.

## Como desfazer

```sql
begin;

update public.cidades
   set nome = 'Divinopolis', centro_lat = null, centro_lng = null
 where id = 'd54b518b-6ed2-4de5-b8e4-8ebac0e92d90';

update public.cidades
   set centro_lat = null, centro_lng = null
 where id = 'de470309-afb7-49ac-9471-54e8387d4a88';

commit;
```
