# Registro: config de prazo da disputa 72 h -> 48 h

- **Data:** 2026-11-20 (escrita no Supabase de produção com o OK do João, "pode, mas documente").
- **Motivo:** decisão do João: janela de disputa e repasse em até 48 h. Os Tratinhos seguem 7 dias (não mudou).
- **O que foi escrito:** uma versão NOVA de config em **rascunho**, copiando a vigente (v2, 17 parâmetros) e mudando só `prazo_congelar_disputa_horas`.
- **Id da versão:** `835228cc-bc35-4239-9aeb-a8df79dc981e` (número 5; os números 3 e 4 não existem na tabela. Colunas `identity` pulam números quando uma transação é desfeita; a causa exata não foi investigada).
- **Criada por:** "Admin Trato" (`equipe.usuario_id` = `012258b3-8f23-4ab5-943a-ed9993b6f54c`), único admin genérico ativo. Aprovador precisa ser outra pessoa.
- **Antes / depois:** `prazo_congelar_disputa_horas` 72 -> 48. `prazo_liberacao_dias` fica 0. As outras 15 chaves ficaram iguais (conferido com SELECT: 1 única diferença).
- **Estado:** **RASCUNHO, NÃO publicada.** A v2 continua vigente com 72. Nenhuma versão aprovada foi alterada.
- **Auditoria:** a inserção foi feita por SQL, então NÃO gerou a linha de auditoria `config.rascunho_criado` que a rota do painel gera. Este arquivo é o registro.

## SQL executado (numa transação, com conferência antes do commit)

```sql
with nova as (
  insert into public.config_versoes (status, criada_por, motivo)
  values ('rascunho', '012258b3-8f23-4ab5-943a-ed9993b6f54c',
          'Janela de disputa em 48h (decisao do Joao): prazo_congelar_disputa_horas 72 -> 48')
  returning id, numero
)
insert into public.config_parametros (versao_id, chave, valor, escopo_tipo, escopo_id, escopo_texto)
select nova.id, p.chave,
       case p.chave when 'prazo_congelar_disputa_horas' then 48 else p.valor end,
       p.escopo_tipo, p.escopo_id, p.escopo_texto
from nova, public.config_parametros p
join public.config_versoes v on v.id = p.versao_id and v.status = 'vigente';
```

## Para publicar (falta fazer)

O fluxo (`backend/src/trato/api/admin/rotas_config.py` e `postgres.py`) exige:

1. `POST /v1/admin/config/versoes/{id}/enviar` (permissão `CONFIG_PROPOR`): rascunho -> aguardando aprovação.
2. `POST /v1/admin/config/versoes/{id}/aprovar` (permissão `CONFIG_APROVAR`) por **outra pessoa** diferente de quem criou (regra `criada_por <> aprovada_por`). Ex.: outro admin ativo, como o Gabriel Victor.
3. `POST /v1/admin/config/versoes/{id}/publicar` (permissão `CONFIG_APROVAR`): aprovada -> vigente; a v2 vira `substituida`.

Tudo isso também existe no painel admin, na tela de configuração. Por isso não foi publicado por SQL: exige aprovação de segunda pessoa.

## Para desfazer

- **Ainda rascunho:** descartar pelo painel ou `DELETE /v1/admin/config/versoes/835228cc-bc35-4239-9aeb-a8df79dc981e`. Equivale a apagar os parâmetros e a versão (só vale em rascunho ou aguardando aprovação).
- **Depois de publicada:** usar a reversão `POST /v1/admin/config/versoes/{id_v2}/reverter`, que cria uma versão (`revertida_de` = v2, valor 72) e também passa por aprovação de outra pessoa. Alternativa: nova versão com `prazo_congelar_disputa_horas` = 72.
