# Decisões — Indique e Ganhe Tratinhos e Serviço Recorrente

Aprovado pelo João em 23/11/2026:
- **Indique e Ganhe Tratinhos:** Opção A aprovada (300 Tratinhos / R$ 3 por cliente, máx. 3/mês; 150 Tratinhos por profissional, máx. 5/mês, custo R$ 0 no caixa; 1º serviço >= R$ 60 pago via Stripe + 7 dias sem disputa).
- **Cancelamento na recorrência:** Opção A aprovada (regra padrão do piloto, sem multa extra; sem confirmação/pagamento até 12–24h antes a visita cai e libera a agenda automaticamente).
- **Frequências na v1:** Semanal, quinzenal e mensal.

---

# Proposta Consolidada — Indique e Ganhe Tratinhos & Serviço Recorrente

*Data: 23/11/2026 | Autor: Marketing (com consulta direta a Cliente e Profissional)*
*Base: regras vigentes do Trato (piloto 100% gratuito; 1 Tratinho = R$ 0,01; orçamento mensal global de desconto = R$ 300; teto R$ 5/mês e R$ 10/dia por cliente; validade 90 dias; profissional gasta 100 Tratinhos por exclusividade de 48h, máx. 3).*

---

## 1. Proposta fechada — Indique e Ganhe Tratinhos

### Fluxo (sem atrito e transparente)
- **Código pessoal único por conta** (ex.: `JOAO4K`), compartilhado via **link direto que já preenche o código automaticamente** (com campo opcional "Tem código?" no cadastro/antes do 1º pedido como fallback, bloqueado após o 1º pedido).
- **Profissional → Cliente antigo:** o link de indicação do profissional abre **direto o perfil público dele** (nunca a busca geral), aplicando o código de indicação automaticamente.
- **Rastreio visível nos dois lados:** barra simples de 3 etapas sem expor dados privados do indicado (só primeiro nome + inicial): `Cadastrou → 1º serviço feito → Libera em dd/mm`.

### Valores e limites (protegendo o caixa de R$ 300/mês)
- **Cliente indica Cliente:** **300 Tratinhos (R$ 3,00)** para quem indica + **300 Tratinhos (R$ 3,00)** para o indicado.
  - *Por quê:* cabe dentro do teto de uso de R$ 5/mês (junto com os 50 Tratinhos da avaliação) sem parecer pegadinha. Custo máximo de R$ 6 por novo cliente pagante concluído (com R$ 300/mês, suporta até 50 indicações convertidas/mês).
  - *Limite:* até **3 indicações recompensadas por mês** por cliente (validade de 90 dias permite usar o excedente nos meses seguintes).
- **Profissional indica Cliente:** **150 Tratinhos** para o profissional (**custo R$ 0 no caixa**, vale 1,5 exclusividade de 48h) + **300 Tratinhos (R$ 3,00)** para o cliente.
- **Profissional indica Profissional (outras áreas):** **150 Tratinhos** para quem indica + **100 Tratinhos** para o indicado (**custo R$ 0 no caixa**; indicado já ganha sua 1ª exclusividade de 48h).
  - *Limite para profissional:* até **5 indicações recompensadas por mês**.
- **Proteção de caixa:** se o teto global de R$ 300/mês for atingido, o app avisa antes do checkout: *"O limite mensal de descontos do Trato foi atingido. Seus Tratinhos continuam guardados até a validade e voltam em 01/MM."*

### Regras antifraude obrigatórias (backend)
1. **1 código por conta (irrevogável)**, vinculável apenas antes do 1º pedido criado.
2. **Bloqueio de auto-indicação e colisão:** rejeitar mesmo CPF/CNPJ, mesmo telefone verificado, mesmo e-mail, mesmo cartão/conta Stripe ou mesmo endereço de atendimento entre indicador e indicado; bloquear indicação cruzada (`A → B` e `B → A`).
3. **Gatilho real:** só libera após o 1º serviço do indicado ser **pago via Stripe no app, concluído com código de conclusão, sem disputa aberta**, com **valor mínimo de R$ 60** (evita serviço fictício barato para farmar R$ 6) e **prazo de segurança de 7 dias** após a conclusão.
4. **Profissional → Cliente:** o indicado precisa ter conta nova (CPF/telefone inéditos) e pagamento real via Stripe.

### Copy pronta para WhatsApp
- **Cliente → Amigo:**
  > Usei o Trato pra contratar serviço em casa e gostei: profissional verificado e pagamento protegido. Entrando pelo meu link e fechando seu 1º serviço, nós dois ganhamos R$ 3 em Tratinhos de desconto: [link] (código: XXXX)
- **Profissional → Cliente antigo (link do perfil):**
  > Agora também atendo pelo Trato — sem taxa, agenda organizada e pagamento protegido. Pelo meu link você chama direto comigo e ganha R$ 3 de desconto no 1º serviço: [link-perfil] (código: XXXX)
- **Profissional → Colega de outra área:**
  > Tô usando o Trato pra pegar serviço sem pagar taxa nem pagar por orçamento. Entrando pelo meu link e fechando seu 1º serviço, você ganha 100 Tratinhos (1 exclusividade de 48h) e eu ganho 150: [link] (código: XXXX)

### Prioridade, custo e métrica
- **Prioridade:** Alta (alavanca direta de aquisição orgânica no piloto).
- **Custo estimado:** até R$ 300/mês (dentro do orçamento já aprovado; R$ 0 extra para indicações de profissionais).
- **Como medir:** taxa de convites compartilhados após avaliação; % de indicados que concluem o 1º serviço; custo efetivo por cliente adquirido (CAC em Tratinhos) e taxa de bloqueios antifraude.

---

## 2. Proposta fechada — Serviço Recorrente / Retorno Programado

### Onde nasce e frequências
- **Onde nasce:** (1) na **tela pós-avaliação** quando o serviço é bem avaliado (4–5 estrelas): botão *"Agendar retorno com [Nome]"*; (2) em **Favoritos / "Chamar de novo"** e no histórico/chat de cliente já atendido. Qualquer lado pode propor; o outro aceita em 1 toque. **Nunca no 1º pedido** (sem confiança prévia).
- **Frequências (v1):** **Semanal, Quinzenal e Mensal** (cobre diarista, jardineiro, piscina, manutenção). Opcional v1.1: bimestral/semestral (ar-condicionado, caixa d'água).

### Pagamento, confirmação, pular visita e cancelamento
- **Sem cobrança automática no cartão.** Modelo: **pré-agendamento recorrente + lembrete em 1 toque para confirmar e pagar 48h antes da visita**.
  1. **48h antes:** push ao cliente (*"Visita com [Nome] em [dia/hora] por R$ X. [Confirmar e pagar] / [Pular esta visita]"*).
  2. **Confirmou e pagou:** dinheiro entra em custódia normal (Stripe) e o profissional recebe *"Visita confirmada e paga"*.
  3. **Não confirmou até 24h antes:** lembrete final; sem confirmação/pagamento até o limite (ex.: 12h antes), a visita **não é confirmada** e a agenda do profissional é **liberada automaticamente**, sem punição para ninguém.
- **Pular 1 visita / feriado:** 1 toque para qualquer lado, sem multa e sem cancelar a série.
- **Cancelar a recorrência:** 1 toque para qualquer lado, a qualquer momento, sem falar com suporte.

### Regras de proteção dos dois lados
- **Para o cliente:** zero cobrança surpresa; cancelar ou pular em 1 toque; **trava de aprovação de preço** (nenhum reajuste é cobrado sem aceite explícito).
- **Para o profissional:** só sai de casa com visita **confirmada e paga** (elimina bolo); pode **reajustar o valor antes da próxima visita** sem cancelar a série (cliente recebe *"Novo valor R$ Y a partir de dd/mm — Aceitar / Cancelar recorrência"*); horário liberado automaticamente se o cliente não confirmar no prazo.

### Prioridade, custo e métrica
- **Prioridade:** Média-alta (motor de retenção e recompra sem custo de mídia).
- **Custo estimado:** R$ 0 de verba de marketing (apenas desenvolvimento).
- **Como medir:** % de serviços bem avaliados que viram recorrência; taxa de confirmação no 2º e 3º ciclo; taxa de visitas puladas vs. cancelamentos da série.

---

## 3. Principais alertas levantados por Cliente e Profissional
- **Cliente:**
  1. Ter que digitar código faz desistir (o link precisa aplicar sozinho).
  2. Prometer bônus maior que o teto de R$ 5/mês parece pegadinha; o amigo também precisa ganhar.
  3. Medo de juntar Tratinhos e dar de cara com "orçamento mensal esgotado" na hora de pagar.
  4. Rejeita cobrança automática no cartão (medo de viajar ou do profissional desmarcar) e só ativa recorrência depois de testar o profissional.
- **Profissional:**
  1. Só indica cliente antigo se o link abrir **direto o perfil dele** (nunca a busca geral).
  2. Não indica colega da mesma área (cria concorrente no bairro) — só de áreas complementares.
  3. Menos de 100 Tratinhos não anima (não paga 1 exclusividade de 48h).
  4. Precisa de linha de status clara da indicação para confiar que o app não enrola.
  5. Quer pagamento confirmado 24h–48h antes (para não levar bolo) e reajuste simples sem precisar recriar a série.

---

## 4. Decisões que precisam do OK do João (3 perguntas)
1. **Valores e trava do Indique e Ganhe:** aprova **300 Tratinhos (R$ 3) para cada cliente** (limite 3/mês), **150 Tratinhos para profissional indicador** (limite 5/mês, custo R$ 0) e **valor mínimo de R$ 60** no 1º serviço para liberar o bônus?
2. **Cancelamento de última hora na recorrência já paga:** se o cliente confirmar e pagar, mas cancelar com menos de 24h, mantém a regra padrão atual de cancelamento do piloto ou aplica retenção parcial para proteger a agenda do profissional?
3. **Escopo de frequências na v1:** lançamos a recorrência apenas com **semanal, quinzenal e mensal** (mais enxuto) ou já incluímos **bimestral/semestral**?

*Nota: valores de bônus (300/150 Tratinhos), mínimo de R$ 60 e limites mensais são estimativas de Marketing baseadas nas regras atuais e nas respostas das personas; não li o código do backend nem validei restrições técnicas do Stripe.*
