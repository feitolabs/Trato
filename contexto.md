# contexto.md — Projeto Trato (Feito Labs)

> Leia este arquivo inteiro antes de fazer qualquer coisa.
> Ele é a sua ordem de serviço. Siga na ordem. Não pule etapas.

---

## 0. O que é este projeto

O **Trato** é um app de serviços (pedreiro, eletricista, diarista, etc.).
O cliente descreve o problema, recebe orçamentos e paga. O dinheiro fica **retido** até o serviço acabar.
Lema: **"Serviço feito, dinheiro liberado."**

- O app **não se chama mais WorkNet**. O nome é **Trato**. Use "Trato" em tudo (código, telas, textos, pastas).
- Empresa: **Feito Labs**.
- Pasta do projeto: `C:\Empresas\Feito Labs\Apps\Trato`

### Arquivos desta pasta (leia todos, nesta ordem)

1. `regras.txt` — regras obrigatórias. **Manda mais que tudo.**
2. `observações extras que discutimos d.txt` — decisões novas. **Valem mais que o PDF do escopo.**
3. `Trato— Escopo Completo do Produto.pdf` — o que o app faz (88 páginas).
4. `Trato — Telas do app.pdf` — o protótipo e o design (27 telas). **O visual tem que ficar igual.**

### Qual arquivo vence quando eles discordam

`regras.txt` > `observações extras` > `Telas do app (design)` > `Escopo`

O PDF do escopo ainda fala "WorkNet" e "taxa de 5%". Isso está **velho**. Vale o que está nas observações.

---

## 1. Regras obrigatórias (copiadas do regras.txt — não mude)

1. Backend: **Python**.
2. Frontend: **Flutter**.
3. Usar arquivos **.env**.
4. **Nunca** deixar senha ou chave escrita direto no código (hardcoded).
5. Banco de dados: conectar no **Supabase** e usar o projeto **"Trato"**.
6. Repositório: conectar no **GitHub** e usar o repositório **"Trato"**.
7. **Respeitar o design e o protótipo.**
8. ~~Usar o expodev.~~ **Removida pelo João. Ignore. Não use Expo.**

**Objetivo:** desenvolver o app pensando em **Android e iOS**, **totalmente responsivo** e **intuitivo**, obedecendo fielmente as regras do escopo e do design.

---

## 2. Decisões novas (das observações extras)

1. **Taxa do Trato:** usar **tabela progressiva**. A **taxa base é 7,5%**. A **taxa mínima deve ser configurável** (fica em tabela no banco, nunca fixa no código).
2. **Risco de chargeback:** o **cliente tem até 7 dias para reclamar** (ou ir à Justiça). Não é o Trato que cobre sozinho.
3. **Calcular a porcentagem do Stripe** e mostrar quanto sobra para o Trato em cada serviço (Pix e cartão).
4. **Orçamento é grátis.** Depois de aceito, o cliente paga **30% adiantado** do valor combinado para o profissional começar. Ao encerrar, paga o restante.
5. **Liberação do dinheiro ao profissional:**
   - O dinheiro **só é liberado ao encerrar** o serviço.
   - Se passar **7 dias** e estiver tudo certo, libera o saldo.
   - Opção: pagar **aos poucos**, conforme o serviço avança (por etapas).
6. **Problema = disputa.** Se algo der errado, o pedido entra em **disputa** e o valor fica congelado.
7. **Nota dos materiais:** o profissional precisa **enviar a notinha** ao cliente, para o cliente ver quanto custou cada material.
8. **Aditivo:** se algo não estava previsto (troca de peça, material extra), o profissional cria um **aditivo com preço**. Só vale se o cliente aprovar no app.

> Onde o escopo diz "5%", troque por "taxa progressiva, base 7,5%, configurável".
> Onde o escopo diz "WorkNet", troque por "Trato".

---

## 3. O método: Harness Engineering (explicado simples)

**Ideia:** o agente (você) sozinho erra. Então a gente monta um **"arreio" (harness)** em volta de você: regras claras, tarefas pequenas, testes automáticos e aprovação humana. Assim você trabalha rápido **e** seguro.

O harness tem 5 peças. Monte todas **antes** de programar o app:

| Peça | O que é | Onde fica |
|---|---|---|
| **1. Instruções fixas** | Regras que você relê sempre | `CLAUDE.md` (copia curta das regras e deste arquivo) |
| **2. Memória em arquivo** | Você não confia na sua memória. Anota tudo em arquivo | `harness/PROGRESSO.md`, `harness/DECISOES.md`, `harness/PENDENCIAS.md` |
| **3. Tarefas pequenas** | Cada tarefa cabe numa sessão e tem critério de pronto | `harness/TAREFAS.md` |
| **4. Verificação automática** | Testes, lint e checagem de segredos que rodam sozinhos | `harness/verificar.sh` (ou `.ps1` no Windows) |
| **5. Portões de aprovação** | Pontos onde você para e espera o OK do João | seção 4 abaixo |

### O ciclo de cada tarefa (sempre igual)

1. **Ler** `PROGRESSO.md` e pegar a próxima tarefa de `TAREFAS.md`.
2. **Planejar** em português simples (3 a 6 linhas). Se a tarefa mexe em algo perigoso, **pare e peça OK** (seção 4).
3. **Fazer** só aquela tarefa. Nada além.
4. **Verificar** rodando `harness/verificar` (testes + lint + sem segredos + confere com o design).
5. **Registrar** o que foi feito, o que falhou e o que ficou pendente em `PROGRESSO.md`.
6. **Mostrar o resultado** ao João e seguir para a próxima.

Se a verificação falhar: **corrija e rode de novo**. Não marque como pronta uma tarefa que não passou.
Se falhar 3 vezes seguidas: **pare e explique o problema ao João**.

---

## 4. Ações perigosas — NUNCA faça sem aprovação do João

Isto vem direto das regras do João. Vale em **todas** as etapas.

**Precisa de OK antes (mostre o plano em português simples e espere):**

- Escrever no banco: `INSERT`, `UPDATE`, `DELETE`, `DROP`, `ALTER`, `TRUNCATE`. Isso inclui **criar migrations** e **aplicar migrations** no Supabase.
- Apagar arquivos, ou sobrescrever arquivos **fora do projeto**.
- Chamar API externa com efeito real, enviar e-mail ou mensagem (Stripe real, SMS real, WhatsApp real).
- `git commit`, `git push`, deploy, mudar serviços, permissões ou configurações do sistema.
- Qualquer ação que não dá para desfazer.

**Pode fazer direto, sem pedir:**

- Ler arquivos, listar pastas, abrir PDFs.
- Consultas de leitura (`SELECT`), ver tabelas, ver logs.
- Criar e editar arquivos de código **dentro do projeto**.
- Rodar testes, lint e análise local.

**Sempre avise sobre erros e riscos**, mesmo que ninguém tenha perguntado. Nunca esconda um aviso.

### Como pedir aprovação

Escreva assim:

```
PRECISO DO SEU OK
O que vou fazer: (frase simples)
Por que: (frase simples)
Risco: (o que pode dar errado)
Como desfazer: (se der)
Posso continuar? (sim/não)
```

---

## 5. Estilo de resposta

- Português do Brasil. Frases curtas. Sem enrolação.
- Não narre cada passo. Mostre o resultado.
- Direto e técnico, e depois **uma explicação curta em linguagem simples**.
- Exemplo: em vez de "a solução é usar async", diga "usa async".

---

## 6. O passo a passo — do início ao fim

Faça uma fase por vez. **Só avance quando a fase atual passar na verificação e o João aprovar.**

### FASE 0 — Entender e preparar o harness

**Objetivo:** ler tudo e montar o arreio.

1. Ler os 4 arquivos da pasta (seção 0). Ler as 88 páginas do escopo e as 27 telas.
2. Escrever `harness/RESUMO.md`: o que é o app, quem usa (cliente, profissional, equipe), o que é MVP, V1 e V2.
3. Escrever `harness/DECISOES.md` com as decisões da seção 2.
4. Escrever `harness/PENDENCIAS.md` com as dúvidas que encontrar no escopo (fundo de garantia, chargeback, parceiro de pagamento, cidade do piloto).
5. Criar `CLAUDE.md` curto com as regras da seção 1 e a seção 4.
6. Criar `harness/TAREFAS.md` quebrando as fases 1 a 9 abaixo em tarefas pequenas, cada uma com **"pronto quando..."**.
7. Criar `harness/verificar` (testes + lint + busca de segredos).

**Pronto quando:** os arquivos existem e o João aprovou a lista de tarefas.

### FASE 1 — Ambiente e segurança de base

1. Criar estrutura de pastas: `backend/` (Python), `app/` (Flutter), `harness/`, `docs/`.
2. Criar `.env.example` (só nomes das variáveis, **sem valores**) e `.gitignore` que ignore `.env`.
3. Conferir que **nenhum segredo** está no código (regra 4). Adicionar essa checagem no `verificar`.
4. Pedir ao João as chaves reais do Supabase, do GitHub e do Stripe. Ele coloca no `.env`. **Você nunca escreve chave no código ou no chat.**
5. **[PRECISA DE OK]** Conectar no projeto **"Trato"** do Supabase (começar só lendo: listar tabelas).
6. **[PRECISA DE OK]** Conectar no repositório **"Trato"** do GitHub (primeiro commit só com o OK dele).

**Pronto quando:** Flutter e Python rodam "olá mundo", `.env` funciona e a checagem de segredos passa.

### FASE 2 — Design (antes de ter tela, tenha o design)

1. Extrair do PDF de telas: cores, fontes, espaçamentos, ícones, botões, campos.
2. Criar o **tema Flutter** (`app/lib/tema/`) com esses valores. Nada de cor solta no código.
3. Criar componentes reutilizáveis: botão, campo, cartão, chip de status, linha do tempo.
4. Garantir **responsivo**: celular pequeno, celular grande e tablet. Teste com tamanhos diferentes.
5. Conferir lado a lado com o protótipo (regra 7).

**Pronto quando:** uma tela de exemplo fica igual ao protótipo em Android e iOS.

### FASE 3 — Banco de dados (Supabase, projeto "Trato")

> Tudo aqui **escreve no banco**. Mostre o plano e espere OK **antes de cada migration**.

1. Ler as entidades da seção 11.2 do escopo (usuário, perfil, verificação, categoria, pedido, orçamento, contrato, etapa, aditivo, agendamento, pagamento, lançamento, repasse, disputa, garantia, avaliação, chat, notificação, auditoria).
2. Desenhar o modelo em `docs/modelo-de-dados.md` e mostrar ao João.
3. Regras importantes do escopo:
   - Valores em **centavos inteiros**.
   - **Taxa, prazos e limites em tabela de configuração**, nunca fixos no código.
   - **Livro-razão (ledger)** imutável: só se corrige com estorno.
   - **RLS** (regras por linha): cliente vê só seus pedidos; profissional só os da sua categoria e os que contratou; **endereço completo só depois da contratação**.
   - Auditoria imutável de ações sensíveis.
4. **[PRECISA DE OK]** Aplicar as migrations, uma de cada vez.
5. Rodar o verificador de segurança do Supabase (advisors) e corrigir o que ele apontar.

**Pronto quando:** tabelas criadas, RLS ligado em todas, testes de acesso passando (um usuário não vê dados de outro).

### FASE 4 — Backend em Python (as regras de dinheiro moram aqui)

**Regra de ouro do escopo:** nenhuma regra de dinheiro roda no app. O app só pede e mostra.

1. **Máquina de estados do pedido** (10 estados): Aberto → Orçamento aceito → Pago e retido → Agendado → Em andamento → Em confirmação → Concluído. Saídas: Cancelado, Em disputa, Retrabalho. Cada mudança valida **quem pode, quando e com qual prova**.
2. **Cálculo da taxa:** tabela progressiva, base 7,5%, mínima configurável. Mostrar total, taxa e líquido do profissional.
3. **Cálculo do Stripe** (decisão 3): custo no Pix e no cartão, e quanto sobra para o Trato.
4. **Pagamento (Stripe):** 30% adiantado, resto no fim, valor retido, liberação só ao encerrar ou após 7 dias sem problema, pagamento por etapas, aditivo com pagamento próprio.
5. **Idempotência e webhooks assinados:** reenvio não cobra duas vezes.
6. **Disputa:** congela o valor, profissional responde em 48 h, decisão em até 5 dias úteis (liberar, reembolso total, parcial ou nova visita).
7. **Garantia e retrabalho:** prazo por categoria, profissional tem 7 dias para atender.
8. **Rotinas automáticas:** liberação por prazo, expiração de pedido, lembretes.
9. **Testes** para cada regra de dinheiro. Dinheiro sem teste não entra.
10. Em teste, usar **Stripe modo teste**. **[PRECISA DE OK]** para qualquer chamada real.

**Pronto quando:** todos os testes passam e dá para simular um serviço do início ao fim só pela API.

### FASE 5 — App do Cliente (Flutter)

Siga as telas do PDF e a seção 5 do escopo. Fases marcadas **MVP** primeiro.

1. Onboarding (3 telas), escolha "Quero contratar / Quero trabalhar", cadastro em 2 passos, login (e-mail/CPF/telefone, Google, Apple, biometria), confirmação por SMS.
2. Início, categorias, perguntas guiadas, **novo pedido** (descrição, fotos, prazo, faixa de preço).
3. Comparar orçamentos (máx. 5), contratar com contrato digital.
4. Pagar (Pix e cartão; 30% adiantado) com valor retido e recibo.
5. Acompanhar: linha do tempo, profissional a caminho, **código de início**, fotos, confirmação.
6. **Aditivos:** aprovar ou recusar cobrança extra e ver a **nota dos materiais**.
7. Avaliar, garantia ativa, pedir retrabalho, **relatar problema (disputa)**.
8. Chat por pedido, notificações, perfil, central de ajuda, privacidade (LGPD: exportar e excluir conta).
9. SOS e compartilhar atendimento.

**Pronto quando:** cada tela confere com o protótipo e o fluxo completo funciona em Android e iOS.

### FASE 6 — App do Profissional (Flutter)

Seção 6 do escopo.

1. Cadastro, **verificação** (documento e selfie), status em análise/aprovado/recusado.
2. Pedidos abertos com filtros, alertas por categoria e região, recusar com motivo.
3. **Calculadora de orçamento:** deslocamento, horas, material, total, **taxa**, líquido. Etapas, sinal de material, validade e garantia.
4. Agenda, navegação até o cliente, **check-in** (foto, local, código) e **check-out** (foto final, código).
5. **Enviar a notinha dos materiais** ao cliente e criar **aditivo com preço**.
6. Carteira: retido, a liberar, liberado, extrato, saque por Pix só para chave do mesmo CPF/CNPJ.
7. Responder disputa em 48 h, atender retrabalho, perfil público, avaliações.
8. Modo offline parcial para fotos e check-in (V1, se couber no MVP combinado).

**Pronto quando:** um profissional de teste consegue ser aprovado, orçar, executar, receber e sacar.

### FASE 7 — Painel administrativo (web)

O escopo diz que **sem painel a garantia não funciona**. Seção 7 e seções 22 e 24.

1. Fila de verificação de profissionais.
2. Fila de disputas com visão completa do caso e decisão.
3. Pagamentos e conciliação com o parceiro; repasses e saques.
4. Usuários, pedidos, suporte, categorias e preços.
5. **Configurações** (taxa, prazos, limites) com validação, histórico e reversão.
6. **Auditoria** imutável.
7. Níveis de acesso por função (analista, mediador, financeiro, suporte, gestor, administrador).

**Pronto quando:** uma disputa de teste é decidida pelo painel e o dinheiro se move certo.

### FASE 8 — Segurança, LGPD e conformidade

1. Verificar identidade, mascarar telefone, liberar endereço só após contratar.
2. Antifraude básico (limite para contas novas, 3-D Secure, alerta de mudança de conta bancária).
3. LGPD: consentimentos, exportar e excluir dados, retenção limitada de documentos.
4. Regras de lojas (Apple e Google): exclusão de conta, denúncia de conteúdo.
5. Rodar o verificador de segurança do Supabase e uma varredura de segredos em todo o repositório.
6. Listar no `PENDENCIAS.md` o que **precisa de advogado e contador** (custódia do dinheiro, nota fiscal, vínculo). **Você não decide isso.**

**Pronto quando:** checklist de segurança sem item crítico aberto.

### FASE 9 — Testes finais, build e entrega

1. Testes automáticos de ponta a ponta nos fluxos principais.
2. Teste de tela em vários tamanhos e nos dois sistemas.
3. **[PRECISA DE OK]** Build de teste (Android e iOS).
4. **[PRECISA DE OK]** Subir versão de teste para os primeiros usuários (piloto em uma cidade).
5. Escrever `docs/COMO-RODAR.md` e `docs/ENTREGA.md` (o que está pronto, o que falta, riscos).
6. **[PRECISA DE OK]** Commit final e push.

**Pronto quando:** o João consegue instalar o app de teste e fazer um serviço completo.

---

## 7. O que NÃO fazer

- Não inventar regra de negócio. Se o escopo não diz, **pergunte**.
- Não colocar senha, chave ou token no código ou no chat.
- Não mexer em dinheiro real, banco real ou repositório sem OK.
- Não mudar o design por achar "mais bonito".
- Não trocar a stack (Python, Flutter, Supabase) sem pedir.
- Não fazer tudo de uma vez. Uma fase, uma tarefa.
- Não marcar como pronto sem rodar a verificação.
- Não esconder erro nem risco.

---

## 8. Riscos que você deve sempre lembrar o João

1. **Taxa baixa com cartão parcelado:** o custo do meio de pagamento pode comer a margem. Por isso a taxa base é 7,5% e o cálculo do Stripe é obrigatório.
2. **Guardar dinheiro de terceiros** pode exigir parceiro regulado (o Stripe cobre isso, mas **confirmar com advogado**).
3. **Escopo grande:** o escopo tem 88 páginas. Por isso o plano é por fases, começando pelo **MVP**.
4. **Fundo de garantia** ainda não tem origem do dinheiro definida. Não prometa cobertura no app até isso fechar.
5. **Evasão:** cliente e profissional podem combinar por fora. Por isso os benefícios (garantia, seguro, histórico) só valem dentro do app.

---

## 9. Comece agora

1. Responda em uma frase: "Li o contexto.md".
2. Faça a **Fase 0**.
3. Entregue `TAREFAS.md` e espere o OK dele antes da Fase 1.
