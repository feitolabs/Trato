# Trato — etapas e pendências

Atualizado em 30/10/2026. Este é o documento único para você (João) saber onde o projeto está, o que falta e o que só você pode decidir ou fazer.

Legenda: ✅ pronto · 🟡 pronto só com dados de teste · ⏳ pendente · 🔒 precisa do seu OK ou de algo seu

---

## 1. Onde o projeto está

| Área | Estado |
|---|---|
| Repositório GitHub (`feitolabs/Trato`) | ✅ ligado. `main` e `develop` enviados. O `develop` do GitHub **está atrasado**: as correções de segurança e várias frentes recentes só existem na sua máquina (ver 3.4) |
| Documentos de regra (V2, decisões D1 a D16) | ✅ registrados em `harness/DECISOES.md` |
| Design (tema, componentes, responsivo) | ✅ |
| Telas do cliente | 🟡 prontas, com dados de exemplo; parte ligada à API |
| Telas do profissional | 🟡 prontas; cadastro e verificação ainda sem rota no backend |
| Telas comuns (notificações, mensagens, LGPD, ajuda, busca) | 🟡 prontas, sem protótipo no PDF para várias |
| Painel admin web (`admin/`) | 🟡 pronto; cliente HTTP da API admin escrito, nunca rodou contra o backend de verdade |
| Backend (regras de dinheiro, estados, disputa, rotinas) | ✅ testado (1054 testes) |
| Backend persistindo no Postgres | ✅ (ledger, disputas, garantias, eventos) |
| Segurança (revisão + correções) | ✅ 1 crítico e 8 altos corrigidos; ver 4 |
| Banco Supabase | ✅ 49 tabelas, RLS em todas, alerta de segurança zerado |
| Login real (e-mail, Google, Apple) | 🟡 código pronto; falta configurar no Supabase 🔒 |
| Pagamento (Stripe) | 🟡 fluxo de Aberto a Concluído funciona em modo teste com provedor simulado; nunca falou com o Stripe de verdade 🔒 |
| CI no GitHub | ⏳ escrito, nunca rodou na nuvem |
| Build Android / iOS | ⏳ guias prontos (`docs/BUILD.md`); nenhum build feito |

---

## 2. Etapas do MVP

### Etapa A — Fundação ✅
Harness, gitflow, ambiente, design, tema, componentes, responsivo.

### Etapa B — Banco ✅
Migrations F3.2 a F3.8 e as três de correção aplicadas no Supabase. Dados iniciais aplicados: Belo Horizonte/MG (fechada), 3 categorias, 4 contas de sistema do ledger.
Falta o seed da taxa e dos prazos (ver 3.1).

### Etapa C — Backend ✅ (falta ligar ao mundo real)
Regras, API, persistência Postgres, API admin, notificações, agendador, segurança e LGPD, simulação de margem, pagamento em modo teste.

### Etapa D — Apps ✅ no código, 🟡 nos dados
App do cliente e do profissional, painel admin, câmera e GPS atrás de interfaces, fidelidade visual conferida com o PDF.

### Etapa E — Ligação com serviços reais ⏳🔒
Depende de chaves e contas suas: Supabase (login, service_role), Stripe de teste, Google e Apple, provedor de e-mail e de push.

### Etapa F — Testes reais ⏳
Login real com dois usuários, pagamento no Stripe em modo teste, app em aparelho Android, iOS via CI na nuvem.

### Etapa G — Piloto fechado ⏳🔒
Cidade aberta, profissionais verificados, provedor de pagamento contratado, jurídico fechado, atendimento humano definido.

---

## 3. O que está pendente

### 3.1 Só você pode fazer 🔒

1. **Criar o primeiro administrador** no painel do Supabase (usuário de Auth) e uma segunda pessoa para a aprovação dupla da configuração (por exemplo, financeiro). Depois me passar o `uuid` do administrador (não o e-mail nem a senha).
2. **Colocar as chaves no seu `.env`** (nunca no chat): `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_URL`, segredo do JWT, `STRIPE_SECRET_KEY` (teste), `STRIPE_WEBHOOK_SECRET`. A lista exata está em `.env.example`.
3. **Configurar login no Supabase:** ativar e-mail, Google e Apple. Passo a passo em `docs/login-configuracao.md`. Google exige client IDs no Google Cloud. Apple exige conta Apple Developer.
4. **Conta Stripe** em modo teste e um endereço público para o webhook (ou o Stripe CLI para teste local).
5. **Aprovar os seeds restantes** (taxa e prazos): `docs/seeds.md`, seed 2. Precisa do passo 1 e do valor da taxa (ver 5, pergunta 1).
6. **Abrir a cidade do piloto** quando decidir (`ativa = true` em Belo Horizonte).
7. **Contas para notificações**, quando quiser ligar: Firebase (push Android/iOS), e-mail (SMTP ou API).
8. **Mac ou CI na nuvem** com conta Apple Developer, para build e teste de iOS.

### 3.2 Código que ainda dá para fazer (sessões de IA)

1. Ligar de verdade ao backend as telas que ainda estão em demonstração: lista de orçamentos do pedido, cobrança, mensagens, notificações, perfil (`/me`), pedidos abertos do profissional, resumo de taxa e líquido, garantia. Lista completa em `docs/STATUS-MVP.md`.
2. Passar o token do login ao cliente HTTP do app (`SessaoTrato`), para a API reconhecer o usuário.
3. Pontos de entrada das telas prontas sem botão: aditivo, nota de materiais, responder disputa, atender retrabalho, busca nova.
4. Rotas de upload de foto e documento (URL assinada) e revalidação de EXIF no backend.
5. Cadastro e verificação do profissional: rotas no backend.
6. Seed 2 (taxa e prazos): só falta o administrador e o valor.
7. Achados da revisão de segurança que ficaram fora das correções: ver `docs/fix-dinheiro.md`, `docs/fix-acesso.md`, `docs/fix-app.md` e os itens "baixos" de `docs/revisao-seguranca.md`.
8. Fazer o painel admin conversar com a API admin de verdade (hoje só testado com cliente simulado).

### 3.3 Testes que só dá para fazer depois das suas chaves

- Dois usuários reais no Supabase tentando ler os dados um do outro (valida as policies de verdade; hoje só testadas em Postgres local).
- Pagamento no Stripe em modo teste, com webhook de verdade e o reenvio de evento.
- A condição de corrida de pagamentos duplicados contra o Postgres real.
- O `EXCLUDE` das faixas de taxa (precisa de `btree_gist`, que existe no Supabase).
- O app em aparelho Android real (câmera, GPS, permissões, offline).
- O workflow do GitHub Actions rodando na nuvem.

### 3.4 Git e GitHub

- **Push do `develop` pendente.** Foi enviado uma vez (até o commit `c5b1c9d`). Depois disso entraram as correções de segurança, o painel, notificações, segurança e LGPD, seeds, fidelidade visual, entre outras. Só sobe com o seu OK.
- `main` ainda está no commit antigo. Só avança em release (tag `vX.Y.Z`).
- O workflow `verificar.yml` roda a cada push. Confira a aba **Actions** depois do próximo push.
- O PDF `Trato Feito Auditoria e Escopo V2.pdf` está fora do git. Diga se quer versionar.

### 3.5 Jurídico, financeiro e negócio (não é código)

1. Advogado revisa os rascunhos de `docs/juridico/` (termos de uso, privacidade, cancelamento e disputa, pagamentos) e `docs/advogado-e-contador.md`.
2. Contador: nota fiscal da taxa, enquadramento tributário.
3. Proposta escrita de **2 provedores de pagamento** (modelo em `docs/pedido-de-proposta-provedores.md`; comparação em `docs/provedores-pagamento.md`).
4. Decreto nº 13.135/2026 do SAC: o advogado confirma o enquadramento e os prazos. A V2 diz que entra em vigor em 02/11/2026.
5. Atendimento humano: canais, cobertura, registro de protocolo.
6. Recrutar profissionais verificados em Belo Horizonte antes de divulgar ao cliente.
7. Checklist dos 7 bloqueios da V2: `docs/checklist-lancamento.md`.

---

## 4. Revisão de segurança (resumo)

Relatório: `docs/revisao-seguranca.md`.

| Gravidade | Total | Estado |
|---|---|---|
| Crítico | 1 | ✅ corrigido (ledger e disputas persistem no Postgres) |
| Alto | 8 | ✅ corrigidos (A1 a A8) |
| Médio | 14 | ✅ M1 a M14 tratados; ver `docs/fix-*.md` para o que sobrou |
| Baixo | 8 | 🟡 triviais corrigidos; o resto está listado |

Não verificado na revisão: o Supabase real, o painel contra o backend e a corrida real com Postgres.

---

## 5. Perguntas que ainda precisam da sua resposta

1. **Qual é o valor da taxa do piloto?** Regra única (V2), em % e com mínimo em R$. Sugestão minha: 7,5% com mínimo de R$ 10, ajustável pela simulação em `docs/simulacao-margem.md`. Hoje o seed está sem valor.
2. **P10: qual fornecedor para a verificação de identidade** (documento e selfie)? Sem sugestão; peça junto com a proposta de pagamento. A V2 pede verificação proporcional ao risco e que o fornecedor minimize cópias.
3. **Quem será o segundo aprovador da configuração** (financeiro ou jurídico)? A aprovação dupla exige duas pessoas diferentes.
4. **Quando abrir a cidade do piloto?** Hoje Belo Horizonte está fechada.
5. **Eletricista entra no piloto?** Deixei de fora porque elétrica de quadro é atividade de risco (a V2 pede baixo risco). Se quiser, vira categoria nova com perguntas próprias e triagem.
6. **Garantia e retrabalho:** hoje 30 dias para todas as categorias (padrão do escopo). Quer outro prazo por categoria?
7. **Qual provedor de e-mail e de push** quer usar nas notificações? Hoje ficam desligadas.
8. **Quer versionar o PDF da V2** no repositório?
9. **Posso enviar o `develop` ao GitHub agora?** (ver 3.4)
10. **O texto de retenção de dados** na verificação (selfie e documento) precisa de prazo definido pelo jurídico. Fica como `[A DEFINIR]` até lá.

Já respondidas e registradas (D16): P1 (48 h para confirmar + 7 dias de reclamação), P2 (regra única, valor ainda aberto), P3, P4, P5, P6, P7 (Stripe), P8, P9, P11 (sem SMS no piloto), P12 a P14.

---

## 6. Decisões já tomadas (referência rápida)

| # | Decisão |
|---|---|
| D13 | A Auditoria V2 vale. Sem "escrow", "garantia total" e parecidos. "Pago" só após o provedor confirmar. |
| D14 | Login por e-mail, Google e Apple. WhatsApp fica para a V1. |
| D15 | Caminho A: o Trato não guarda saldo nem faz saque. O ledger só espelha o provedor. A Carteira é extrato. |
| D16 | Stripe como provedor. Regra única de taxa. Liberação 48 h + 7 dias. Belo Horizonte e 3 categorias. Sem SMS no piloto. |

---

## 7. Próximos passos sugeridos (ordem)

1. Criar o administrador no Supabase e passar o `uuid`.
2. Dizer o valor da taxa. Eu preparo o pedido de OK do seed 2 e aplico.
3. Colocar as chaves no `.env`.
4. Configurar Google e Apple no Supabase.
5. Autorizar o push do `develop`.
6. Eu rodo o teste real com dois usuários e o primeiro pagamento no Stripe em modo teste.
7. Em paralelo, você pede as propostas dos provedores e manda os rascunhos para o advogado.
8. Fechar a ligação das telas que ainda estão em demonstração (3.2).
9. Build Android e iOS, piloto fechado.

---

## 8. Onde achar cada coisa

| Assunto | Arquivo |
|---|---|
| Status tela por tela | `docs/STATUS-MVP.md` |
| Decisões | `harness/DECISOES.md` |
| Pendências antigas | `harness/PENDENCIAS.md` |
| Tarefas e progresso | `harness/TAREFAS.md`, `harness/PROGRESSO.md` |
| Banco e segurança | `docs/seguranca-banco.md`, `docs/modelo-de-dados.md` |
| Seeds | `docs/seeds.md` |
| Revisão de segurança | `docs/revisao-seguranca.md` |
| Correções | `docs/fix-dinheiro.md`, `docs/fix-acesso.md`, `docs/fix-app.md` |
| Login | `docs/login-configuracao.md` |
| Build e entrega | `docs/BUILD.md`, `docs/ENTREGA.md`, `docs/COMO-RODAR.md` |
| Provedores e jurídico | `docs/provedores-pagamento.md`, `docs/pedido-de-proposta-provedores.md`, `docs/juridico/`, `docs/checklist-lancamento.md` |
| Painel admin | `docs/painel-admin.md`, `docs/api-admin.md` |
| Margem | `docs/simulacao-margem.md` |
