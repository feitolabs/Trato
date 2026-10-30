# Backend: segurança, antifraude e LGPD (Fase 8)

Pacotes novos: `backend/src/trato/seguranca/` e `backend/src/trato/lgpd/`.
Ligação ao app: **uma linha** em `trato/main.py` (`registrar_rotas(criar_app_da_config())`).
Nos testes: `trato.seguranca.instalacao.instalar_seguranca(app, config)`.
A fábrica do app (`api/fabrica.py`, `api/app.py`) **não foi alterada**. A única mudança em código
existente fora do `main.py` é `persistencia/conversas.py`: `mascarar_contatos` agora delega para
`seguranca/mascaramento.py` (mesma assinatura).

**Todos os limites vêm de configuração** (`.env`, prefixos `TRATO_SEG_*` e `TRATO_LGPD_*`). Os
números no código são só o ponto de partida; listas e dicionários entram como JSON.

## 1. Ameaças cobertas

| Ameaça | Controle | Onde |
|---|---|---|
| Troca de contato antes de contratar (telefone, e-mail, link, rede social, endereço) | Mascaramento do chat; original guardado em `corpo`, `corpo_exibido` mascarado, `mascarada = true` | `seguranca/mascaramento.py` |
| Levar a conversa para fora / pagar por fora | Pontuação de contorno → **flag** para revisão humana (a mensagem não é bloqueada) | `contorno.py`, `conversas.py` |
| Força bruta, raspagem, abuso de rota | Limite de taxa por IP e por usuário, por rota, com bloqueio temporário | `limite_taxa.py`, `http.py` |
| SMS pumping (D14) | Hook de autorização: DDI permitido, backoff, limite por número/dispositivo/IP/faixa, bloqueio temporário | `sms.py`, `POST /v1/seguranca/sms/autorizar` |
| Conta duplicada | Hash (HMAC) de CPF, telefone e dispositivo; repetição abre flag | `duplicidade.py`, `POST /v1/seguranca/identificadores` |
| Fraude decidida por máquina | Máquina só abre **flag**; equipe confirma/descarta; nada é suspenso (V2) | `flags.py`, `GET/POST /v1/seguranca/flags` |
| Clickjacking, sniffing, cache de resposta privada | `X-Frame-Options`, `nosniff`, `Referrer-Policy`, CSP, `Cache-Control: no-store`, HSTS fora do desenvolvimento | `http.py` |
| Chamada de site não autorizado | CORS fechado por padrão; só origens listadas; `*` e `null` recusados | `config.py`, `instalacao.py` |
| Corpo gigante (memória/CPU) | Tamanho máximo do corpo (por `Content-Length` e contando os pedaços), por prefixo | `http.py` |
| Upload malicioso | Tipo, tamanho, nome e conteúdo real (bytes iniciais); o nome original nunca vira caminho | `upload.py`, `POST /v1/seguranca/uploads/validar` |
| Dado pessoal vazando em log | Filtro global redige e-mail, CPF, telefone, Bearer/JWT e parâmetros sensíveis de URL | `logs.py` |
| Direitos do titular (LGPD) | Exportar, excluir (anonimizar), consentimentos com histórico | `lgpd/` |

Todo bloqueio, negação e flag grava na auditoria (`registrar_auditoria`), com ações
`antifraude.*`, `dado_pessoal.*` e `consentimento.*`, **sem dado pessoal em claro** (só categorias,
motivos e hashes). As ações `dado_pessoal.*` sempre levam `motivo`, como o banco exige.

## 2. Mascaramento do chat (F8.1)

Esconde: telefone com espaços, pontos, parênteses, `+55`, dígitos largos, emojis de teclado e
**números por extenso** (“onze nove oito…”, inclusive dezenas); e-mail comum e disfarçado
(“arroba”, “ponto”, `(at)`, `[dot]`, `joao @ gmail . com`); links (`http`, `www`, domínios soltos,
`wa.me`, `t.me`, “ponto com ponto br”); perfis (`@usuario`, “insta: …”); endereço (“Rua X, 123”,
CEP). Perto de “zap”, “fone”, “cel” o mínimo de dígitos cai de 8 para 6.

Não mexe em: preço (`R$ 1.500,00`, `R$ 12.345.678,90`), data (`15/03/2026`, `15.03.2026`), hora,
medidas, “nesse ponto com certeza”, “o instagram é muito usado”.

**Limites conhecidos** (por isso há flag e revisão, não só máscara):
- Quem escreve “nove, oito…” com palavras fora da lista, em outro idioma ou com letras no lugar de
  dígitos (“oito 7 s3is”) escapa. Lista de números por extenso: `_PALAVRAS_DIGITO`.
- Uma lista de números curtos separados por espaço (“10 20 30 40 50”) pode ser mascarada sem
  ser telefone (sobra o `mascarada = true` para a interface avisar).
- Imagens e áudio não são analisados.
- Em memória o repositório só guarda o texto exibido; o original é guardado só no Postgres.

Config: `TRATO_SEG_MASCARA_MIN_DIGITOS`, `TRATO_SEG_MASCARA_MIN_DIGITOS_COM_CANAL`,
`TRATO_SEG_MASCARA_TLDS`.

## 3. Limites configuráveis (padrão inicial)

| Variável (`TRATO_SEG_…`) | Padrão | O que controla |
|---|---|---|
| `LIMITES` (JSON) | geral 300/min por IP e 120/min por usuário; mensagens 60/min; `/me/dados` e `/me/exclusao` 5/h com bloqueio de 1 h; SMS 30/min por IP; webhooks 600/min | regras de limite de taxa (`nome`, `prefixo`, `metodos`, `escopo`, `maximo`, `janela_s`, `bloqueio_s`) |
| `LIMITE_TAXA_ATIVO` | `true` | liga/desliga o limitador |
| `CONFIAR_X_FORWARDED_FOR` | `false` | só ligar atrás de proxy de confiança |
| `CORPO_MAX_BYTES`, `CORPO_MAX_POR_PREFIXO` | 1 MiB | tamanho do corpo |
| `CORS_ORIGENS` | `[]` (fechado) | origens do painel web |
| `HSTS_MAX_AGE_S` | 1 ano | HSTS fora do desenvolvimento |
| `SMS_DDIS_PERMITIDOS` | `["55"]` | países que recebem SMS |
| `SMS_MAX_POR_NUMERO_HORA` / `_DIA` | 3 / 5 | por número |
| `SMS_MAX_POR_DISPOSITIVO_DIA` | 5 | por aparelho |
| `SMS_MAX_NUMEROS_POR_DISPOSITIVO_DIA` | 3 | números diferentes no mesmo aparelho |
| `SMS_MAX_POR_IP_HORA` | 10 | por IP |
| `SMS_FAIXA_DIGITOS`, `SMS_MAX_POR_FAIXA_HORA` | 9, 15 | números vizinhos (padrão de pumping) |
| `SMS_BACKOFF_BASE_S`, `_FATOR`, `_TETO_S` | 30 s, 2×, 900 s | intervalo mínimo entre reenvios |
| `SMS_BLOQUEIO_S` | 3600 | bloqueio temporário ao estourar |
| `SMS_HOOK_SEGREDO` | vazio (rota desligada, 503) | segredo do Send SMS Hook |
| `MAX_CONTAS_POR_DISPOSITIVO` | 2 | acima disso, flag (família pode dividir aparelho) |
| `CONTORNO_LIMIAR` | 3 | pontuação que abre flag |
| `UPLOADS` (JSON) | foto 5 MB, documento 10 MB, anexo 25 MB | tipos e tamanhos por categoria |
| `PIMENTA_IDENTIFICADORES` | vazio | tempero do hash de CPF/telefone/aparelho |
| `TRATO_LGPD_RETENCAO_DIAS` (JSON) | ver §5 | prazos por categoria |
| `TRATO_LGPD_CARENCIA_EXCLUSAO_DIAS` | 7 | tempo para desistir da exclusão |
| `TRATO_LGPD_CONFIRMACAO_VALIDADE_MIN` | 30 | validade do código de confirmação |
| `TRATO_LGPD_FINALIDADES` (JSON) | termos e política obrigatórios; verificação, biometria, localização, marketing | consentimentos aceitos |

Bloqueio temporário de SMS/taxa é **limitação de uso** e expira sozinho. **Nenhuma decisão
automática suspende ou pune conta**: só gera flag.

## 4. Como o antifraude se encaixa

- **SMS**: o Send SMS Hook (D14) chama `POST /v1/seguranca/sms/autorizar` (cabeçalho
  `X-Hook-Segredo`) **antes** de enviar; se `permitido = false`, não envia. CAPTCHA antes do envio
  continua sendo do Supabase Auth (ver pendências).
- **Conta duplicada**: o app (ou o backend no cadastro) chama `POST /v1/seguranca/identificadores`.
  Resposta sempre 204, para não revelar a conta de outra pessoa.
- **Contorno**: o repositório de conversas do contexto é embrulhado (`ConversasVigiadas`) na
  primeira requisição; depois de gravar a mensagem, avalia e, se passar do limiar, abre/atualiza
  uma flag por autor.
- **Revisão**: `GET /v1/seguranca/flags` e `POST /v1/seguranca/flags/{id}/revisao` (papel
  `equipe`). A revisão só registra a decisão.

## 5. LGPD (F8.3)

| Rota | O que faz |
|---|---|
| `GET /v1/me/dados` | exporta meus dados em JSON (`trato-lgpd-1`), mais consentimentos e o que fica por lei com o prazo |
| `POST /v1/me/exclusao` | passo 1 (sem corpo): mostra o que será anonimizado/mantido, pendências e devolve `token_confirmacao`; passo 2 (`{"token_confirmacao": …}`): agenda após a carência |
| `GET /v1/me/exclusao` / `DELETE /v1/me/exclusao` | situação / cancelar durante a carência |
| `POST/GET /v1/me/consentimentos` | registrar, revogar e consultar (histórico só cresce) |
| `POST /v1/lgpd/exclusoes/processar` | (equipe) anonimiza quem passou da carência e não tem pendência |

Regras: pendência (pedido em andamento, disputa aberta, valor retido) impede a confirmação e adia
a anonimização. **Ledger, auditoria, mensagens e contratos nunca são alterados** (o serviço nem
tem como chegar neles: só a `FonteDadosPessoais` anonimiza perfil, contato e documentos). Aceites
obrigatórios (termos, privacidade) só saem com o encerramento da conta.

Prazos de retenção **propostos** (`TRATO_LGPD_RETENCAO_DIAS`): financeiro 1825, auditoria 1825,
contratos/pedidos 1825, mensagens/disputas 1825, logs de acesso 180, documentos de verificação 90.
São sugestões; **não são parecer jurídico**.

Em modo `memoria` as rotas funcionam com repositórios em memória (perdem tudo ao reiniciar). Em modo
`postgres` sem adaptador (`contexto.extras["lgpd"]`) respondem **503**, para não perder consentimento
em silêncio.

## 6. O que falta e de quem depende

**João (dono do banco / CLAUDE.md: escrever no banco precisa do OK)**
1. Aprovar e aplicar migrations para: `consentimentos` (append-only, com RLS e bloqueio de
   alteração como o resto), `pedidos_exclusao`, `antifraude_identificadores` (tipo + hash +
   usuário), `antifraude_flags`. Nada disso foi criado nem aplicado; a proposta de colunas está nas
   interfaces `lgpd/repositorios.py`, `seguranca/flags.py` e `seguranca/duplicidade.py`.
2. Escrever os adaptadores Postgres (exportação/anonimização por tabela) depois dessa aprovação.
3. Definir `TRATO_SEG_SMS_HOOK_SEGREDO`, `TRATO_SEG_PIMENTA_IDENTIFICADORES` e
   `TRATO_SEG_CORS_ORIGENS` no `.env` de produção (nunca no git). Sem a pimenta os hashes mudam a
   cada reinício.
4. Rodar atrás de proxy? Então ligar `CONFIAR_X_FORWARDED_FOR` (só se for proxy de confiança).
5. Mais de uma instância da API: o limitador e os contadores de SMS são **em memória, por
   processo**. Trocar `Contadores` por Redis/Postgres antes de escalar.
6. Provedor de SMS e CAPTCHA (D14, P11) na configuração do Supabase Auth; o hook precisa apontar
   para esta rota.

**Jurídico / DPO / contador** (ver `docs/advogado-e-contador.md`)
1. Prazos de retenção por categoria (§5) e o prazo de documentos/selfie (N10).
2. Base legal de cada finalidade de consentimento e o texto/versão de cada aceite.
3. Carência de 7 dias e o que “excluir” significa com ledger e contratos (anonimizar x guardar).
4. Se o antifraude por CPF/telefone/dispositivo e a análise de mensagens exigem aviso específico
   na política de privacidade e RIPD.
5. Revisão do fluxo de exportação (formato, prazo de resposta, identificação do titular).
6. Logs de acesso (Marco Civil, art. 15): confirmar prazo e onde ficam, já que o app não os guarda
   hoje.

**Limitações técnicas assumidas**
- Redação de logs não cobre `exc_info` (stack traces) nem logs de bibliotecas que escrevam fora do
  `logging`; o certo continua sendo não logar dado pessoal.
- O token de confirmação de exclusão volta na resposta do passo 1 (o app pede o “tem certeza?”).
  Para reforçar, exigir reautenticação recente ou confirmação por e-mail (depende do provedor).
- O limite “por usuário” usa o hash do token (não decodifica o JWT): renovar o token reinicia o
  contador; o limite por IP cobre isso.
- CSP é `default-src 'none'` (API pura); `/docs` e `/redoc` ficam sem CSP para carregar seus scripts.
  Em produção convém desligar essas páginas.

## 7. Testes

```bash
cd backend
.venv/Scripts/python -m pytest tests/seguranca -q
```

`tests/seguranca/`: `test_mascaramento.py` (casos difíceis e frases legítimas), `test_antifraude.py`
(SMS, duplicidade, contorno, flags), `test_http.py` (cabeçalhos, CORS, corpo, taxa, upload, logs),
`test_lgpd.py` (exportar, exclusão em dois passos, carência, imutáveis, consentimentos). Tudo em
memória; nada toca o Supabase.
