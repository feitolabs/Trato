# Fix de acesso (A1, A2, A8, M6, M7, M9–M12 e baixos)

Branch `claude/fix-acesso-adc4fc`. Corrige os achados de `docs/revisao-seguranca.md` que são de
**autorização e acesso**. Os de dinheiro (C1, A3–A7, M1–M5) e do app (M13, M14) são de outras
sessões. **Nada foi escrito no Supabase real.** Mudanças de banco = uma migration NOVA em arquivo,
**não aplicada** (pedido de OK no fim).

Em português simples: antes, qualquer pessoa da equipe lia dinheiro e chat pela API; o código de 4
dígitos podia ser chutado à vontade; o documento do profissional podia ser baixado direto pela equipe
de cadastro, sem registro. Agora cada rota confere o papel certo, o código trava depois de poucos
erros, e documento só sai por URL curta com motivo e registro.

## O que mudou, por achado

| Achado | Correção | Onde |
|---|---|---|
| **A1** código de check-in/out | Contador de erros por **agendamento** e por **IP**; os 2 primeiros erros respondem 422, do 3º em diante há **espera crescente** (backoff, 429 com `Retry-After`); com 5 erros o agendamento **bloqueia** por 15 min (e continua 1 tentativa por bloqueio); 20 erros por IP bloqueiam o IP por 1 h. Cada erro e cada bloqueio vão para a auditoria (`checkin.codigo_incorreto`, `checkin.codigo_bloqueado`) com IP e aparelho, nunca com o código digitado. Código certo zera o contador do agendamento. Tudo em `TRATO_SEG_CODIGO_*`. | `seguranca/tentativas_codigo.py`, `seguranca/cliente.py`, `api/rotas_pedidos.py` (`mudar_estado`), `pedidos/estados.py` (`CodigoNaoConfere`) |
| **A2** matriz da equipe | `eh_participante` não devolve mais `True` para equipe. Equipe só entra por `carregar_pedido(..., equipe=(Permissao...))`, que confere a linha em `equipe` (vigente) e a permissão da matriz **a cada chamada** e **grava `pedido.consulta_equipe` na auditoria**. Sem painel ligado, sem linha, revogado ou sem permissão: **403**. | `api/acesso.py`, `api/servicos.py` |
| A2 (rotas) | pedido/eventos/orçamentos: `PEDIDOS_BUSCAR`; saldo/extrato/pagamento/cobranças/aditivos: `PAGAMENTOS_VER`; disputa: `DISPUTAS_VER`; **chat**: `DISPUTAS_DECIDIR` **e** o pedido precisa ter disputa. | `rotas_pedidos.py`, `rotas_financeiro.py`, `rotas_pagamento.py`, `rotas_app.py` |
| A2 (decisão da disputa) | `POST /v1/pedidos/{id}/disputa/decisao` agora exige `DISPUTAS_DECIDIR`, usa a **alçada de quem decide** (`equipe.alcada_centavos`, vazia = 0; acima dela fica aguardando segunda pessoa) e grava `financeiro.disputa_decisao` com a justificativa (agora obrigatória, 3 a 2000 caracteres). **Recomendação:** remover esta rota quando a `fix-dinheiro` unificar com a do admin (`/v1/admin/disputas`); deixei porque os testes de ponta a ponta do dinheiro dependem dela. | `rotas_pagamento.py` |
| **A8** documentos | A rota do admin já entregava URL assinada com motivo e auditoria (`dado_pessoal.documento_revelado`, gravada **antes** da URL; falha na auditoria = sem URL). Agora: validade da URL vem da configuração (`TRATO_SEG_URL_DOCUMENTO_SEGUNDOS`, padrão 60), há **limite de 30 URLs por operador por hora** (bloqueio de 1 h) e a **leitura direta no Storage e na tabela é fechada pela migration nova**. | `api/admin/contexto.py`, `seguranca/config.py`, migration |
| **M6** conta bloqueada | Policy restritiva também em `storage.objects`; **gatilho de evento** que dá RLS + a restritiva a toda tabela nova de `public`; preenche as que já estiverem sem. | migration |
| **M7** perdedor do orçamento | `privado.pode_ver_pedido`: orçamento/conversa só valem enquanto **não há contrato com outro profissional**. `pedido_historico` passa a usar `privado.pode_ver_historico` (cliente, profissional do contrato e equipe de atendimento; quem só orçou não lê). | migration |
| **M9** texto livre | Título (120), descrição (2000), respostas em texto (500), comentário (1000), até 8 etiquetas de até 40 caracteres: limites em `TRATO_SEG_*`, estouro = 422, e **mascaramento de telefone/e-mail/link/rua na entrada** (o mesmo do chat). | `seguranca/texto_livre.py`, `rotas_pedidos.py`, `rotas_app.py` |
| **M10** aceite | O contrato grava `aceite_ip` e `aceite_dispositivo` (`X-Dispositivo-Id`, ou o user-agent cortado). `X-Forwarded-For` só vale com `TRATO_SEG_CONFIAR_X_FORWARDED_FOR=true` (atrás de proxy de confiança) e usa o **último** item. | `rotas_pedidos.py`, `seguranca/cliente.py` |
| **M11** primeiro login | `ProvedorAuthSupabase` cria `public.usuarios` (cliente, `ativo`) no primeiro token válido, com `insert ... on conflict do nothing` (idempotente, seguro com logins simultâneos). O **papel nunca vem do token**; do `user_metadata` só entra o nome de exibição. Login anônimo e `sub` fora de `auth.users` não criam nada. `usuarios_privados` exige CPF (`not null`), então fica para o passo de cadastro: `UsuariosPostgres.registrar_dados_privados` é idempotente e recusa CPF de outra pessoa. **Falta** a rota que coleta o CPF (depende do desenho do cadastro: ver "Fora do escopo"). | `api/auth_supabase.py`, `persistencia/usuarios.py` |
| **M12** borda | Limite de taxa já existia (`seguranca/`); incluí regras para as rotas sensíveis (envio de verificação, URL de documento, escrita do admin). CORS só por lista (`TRATO_SEG_CORS_ORIGENS`, sem `*`). `/docs`, `/redoc` e `/openapi.json` **só existem** em `TRATO_SEG_AMBIENTES_COM_DOCS` (padrão: desenvolvimento, dev, local, teste); ambiente desconhecido = desligado. | `seguranca/config.py`, `api/app.py`, `api/fabrica.py` |
| **B1** | `iss` conferido quando `SUPABASE_URL` está no `.env` (`<url>/auth/v1`); token de outro projeto cai. | `api/auth_supabase.py` |
| **B8** (parte) | `.github/dependabot.yml` (pip, pub e Actions, semanal, só abre PR). | `.github/dependabot.yml` |

### Configuração nova (tudo opcional; os valores abaixo são o padrão)

`TRATO_SEG_CODIGO_MAX_ERROS_AGENDAMENTO=5`, `_CODIGO_JANELA_S=86400`, `_CODIGO_BLOQUEIO_S=900`,
`_CODIGO_ERROS_SEM_ESPERA=2`, `_CODIGO_BACKOFF_BASE_S=10`, `_CODIGO_BACKOFF_FATOR=2.0`,
`_CODIGO_BACKOFF_TETO_S=300`, `_CODIGO_MAX_ERROS_IP=20`, `_CODIGO_JANELA_IP_S=3600`,
`_CODIGO_BLOQUEIO_IP_S=3600`, `_AMBIENTES_COM_DOCS=["desenvolvimento","dev","local","teste"]`,
`_TITULO_MAX_CHARS=120`, `_DESCRICAO_MAX_CHARS=2000`, `_RESPOSTA_MAX_CHARS=500`,
`_COMENTARIO_MAX_CHARS=1000`, `_ETIQUETAS_MAX=8`, `_ETIQUETA_MAX_CHARS=40`,
`_URL_DOCUMENTO_SEGUNDOS=60`. As regras de limite de taxa seguem em `TRATO_SEG_LIMITES` (JSON).
**Em produção defina `TRATO_AMBIENTE=producao`** (senão o padrão é `desenvolvimento` e os docs ficam ligados).

## Testes

- Os `xfail` **A1, A2 (3 testes) e A8** viraram testes normais, sem enfraquecer: A2 continua exigindo 403
  para `t-equipe`; A8 agora confere que a migration nova remove as duas policies. Ajuste necessário no A1:
  o teste antigo esperava 422 nos 30 palpites; com o limite, os primeiros respondem 422 e o resto 429, e o
  **código certo também é recusado** (essa é a verdade que o teste protege).
- `tests/api/test_fix_acesso_codigo.py` (A1), `test_fix_acesso_permissoes.py` ("papel errado = 403" para
  **cada papel da equipe × cada rota de leitura**, calculado a partir da própria matriz, mais auditoria e
  revogação), `test_fix_acesso_texto_aceite_docs.py` (M9, M10, M12, A8), `test_fix_acesso_jwt.py` (B1, M11).
- `tests/integracao/test_fix_acesso_postgres.py` (M11 no Postgres local, pgserver): primeiro login,
  repetição, 8 logins simultâneos, `sub` fantasma, anônimo, conta bloqueada, `claims` de papel ignorados,
  cadastro → pedido.
- `supabase/testes/testar_banco.py` (suíte SQL completa, Postgres local descartável): expectativas de A8 e M7
  atualizadas (a equipe de cadastro **deixa** de ler documento; quem perdeu o orçamento **deixa** de ver o
  pedido) e blocos novos para M6 e M7, além do rollback da migration nova.
- Mudanças em testes de outras áreas, consequência direta de A2: `conftest.py` ganhou equipe com papel real
  (`t-mediador`, `t-financeiro`, `t-n1`…); os testes que usavam `t-equipe` como superusuário (decisão de disputa
  nos testes de ponta a ponta, saldo, ver pedido) passaram a usar o papel certo. **Quem mexer nesses testes na
  `fix-dinheiro` (por ex. o A7) deve usar `t-mediador` na decisão da disputa.**

## Pedido de OK — migration NOVA (não aplicada)

```
PRECISO DO SEU OK
O que:       aplicar no Supabase a migration supabase/migrations/20261030000000_fix_acesso_storage_pedido_historico.sql
Por que:     fecha A8 (equipe de cadastro lê documentos/selfie direto, sem registro), M6 (conta bloqueada lê o
             Storage; tabela futura nasce sem a policy restritiva) e M7 (quem perdeu o orçamento vê o pedido e o
             histórico com prova em JSON).
O que faz:   (1) remove as policies trato_verificacao_leitura (storage.objects) e verificacao_documentos_select
                e revoga o SELECT de authenticated em verificacao_documentos; (2) cria a policy restritiva
                conta_ativa_obrigatoria em storage.objects, o gatilho de evento trato_conta_ativa_tabela_nova
                (RLS + restritiva em tabela nova de public) e completa tabelas que estejam sem ela;
                (3) troca privado.pode_ver_pedido, cria privado.pode_ver_historico e troca a policy
                pedido_historico_select. Só DDL e policies; nenhum dado é lido nem escrito.
Risco:       médio. (a) Depois de aplicar, a equipe de cadastro só vê documento pela rota do backend
             (POST /v1/admin/verificacoes/{id}/documentos/{doc}/url), que exige o assinador do Storage ligado
             ao service_role; sem ele a rota responde 503. Ligar o assinador ANTES de aplicar.
             (b) `create event trigger` normalmente exige superusuário; no Supabase o papel `postgres` costuma
             poder (a plataforma já tem um, o rls_auto_enable). Se o Supabase recusar, o resto da migration
             vale e só esse trecho (gatilho de evento) é aplicado depois por outro caminho, ou trocado por um
             teste no CI que falha se faltar a policy (já está em testar_banco.py).
             (c) Policies mudam o que cada pessoa enxerga: quem orçou e perdeu para outro profissional passa a
             receber lista vazia do pedido.
Como desfazer: supabase/rollback/fix_acesso_rollback.sql (restaura a função e as policies antigas e remove
             o gatilho). As policies restritivas criadas para tabelas que já existiam sem elas ficam (inofensivas).
Testado:     Postgres local descartável (pgserver), padrão de privilégios "real" do projeto: aplicação, suíte de
             segurança e rollback + reaplicação (ver resultado abaixo). Nada rodou no Supabase real.
Posso continuar? (aplicar só com o seu "sim")
```

## Não resolvido / fora do escopo desta branch

- **Contadores em memória** (A1 e limite de taxa): valem por processo. Com mais de uma instância, trocar
  `Contadores` por Redis ou pela tabela no Postgres (a interface é a mesma). Em A1 isso importa: 2 instâncias
  = o dobro de tentativas.
- **A1, avisos:** o bloqueio vai para a auditoria, mas **não** avisa o cliente nem o suporte (precisa de
  notificação; a flag antifraude `Seguranca.abrir_flag` existe só quando a segurança está instalada). Considerar
  código de 6 dígitos (a revisão sugeriu) é decisão de produto e muda o app.
- **M6:** "banir a sessão no Auth ao bloquear" chama a API do Supabase Auth (efeito real); não implementado.
  O JWT de conta bloqueada já é recusado pelo backend (consulta o banco a cada chamada); o que falta é a
  leitura direta pelo PostgREST até o token expirar, e a policy restritiva cobre isso.
- **A8:** retenção de documentos (`verificacao_documentos.excluir_em`, N10) é decisão do advogado/DPO.
- **M11:** falta a rota que coleta o CPF e grava `usuarios_privados` (o repositório está pronto e testado). CPF
  precisa de validação de dígitos e decisão sobre guardar em claro ou só o hash (o schema hoje guarda o texto).
  Também falta o aceite dos termos (`aceite_termos_versao/em`).
- **Baixos (B\*):**
  - B1 e B8 (Dependabot): feitos aqui. B8 ainda sem `pip-audit` no CI e sem lock com hash (mexe no CI/`pyproject`).
  - B2 (concessão por coluna em `repasses`, `lancamentos`…): exige migration de grants por coluna e acompanhar
    o que o backend lê; fica para quando o ledger for ligado ao banco (junto da `fix-dinheiro`).
  - B3 (mensagem do gatilho no erro) e B4/B7 (webhook/Stripe): pacotes `persistencia/` e `pagamentos/`, da `fix-dinheiro`.
  - B5: coberto em parte (toda tabela de `public` tem a restritiva, checado no `testar_banco.py`); falta o teste
    "toda tabela tem RLS e nenhum grant a anon" no CI.
  - B6 (um papel por conta): decisão de produto.
- **M8** (upload/EXIF no backend), **M13** e **M14** (app e `verificar.py`): não eram desta tarefa.
