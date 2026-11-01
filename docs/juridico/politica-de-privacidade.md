# Política de privacidade do Trato

**Versão:** 1.0 · **Vigência:** 31/10/2026
**Controlador dos dados:** Feito Labs Tecnologia Ltda., Belo Horizonte/MG.
**Encarregado pelo tratamento de dados (DPO):** Encarregado de Proteção de Dados Feito Labs — `privacidade@trato.app.br`.

Esta política explica, em linguagem simples e conforme a **Lei Geral de Proteção de Dados (Lei nº 13.709/2018 — LGPD)**, quais dados pessoais coletamos no aplicativo **Trato**, por que precisamos deles, com quem são compartilhados e como você exerce seus direitos.

---

## 1. Quais dados coletamos e para quê

| Dado | De quem | Para que usamos | Base legal (LGPD) |
| :--- | :--- | :--- | :--- |
| **Nome completo, CPF e data de nascimento** | Clientes e profissionais | Identificar as partes do contrato, confirmar maioridade (18+), emitir cobranças/repasses e prevenir fraude. | Execução de contrato (art. 7º, V), cumprimento de obrigação legal (art. 7º, II) e prevenção à fraude (art. 11, II, g). |
| **Celular e e-mail** | Clientes e profissionais | Acesso à conta, confirmação de segurança e avisos sobre o andamento dos pedidos. | Execução de contrato (art. 7º, V). |
| **Avisos por WhatsApp ou notificações promocionais** | Quem optar por receber | Enviar comunicações opcionais pelo WhatsApp ou avisos sobre novidades do Trato. | Consentimento (art. 7º, I) — pode ser desligado a qualquer momento em *Perfil → Meus dados*. |
| **Endereço do serviço (rua, número, bairro, cidade, CEP)** | Clientes | Encontrar profissionais da região (que veem apenas o bairro antes da contratação) e permitir que o profissional contratado chegue ao local após o pagamento. | Execução de contrato (art. 7º, V). |
| **Fotos do documento de identidade e selfie de verificação** | Profissionais | Conferir a identidade de quem vai prestar serviços nas residências dos clientes e atribuir o selo de verificação. | Prevenção à fraude e segurança do titular e de terceiros (art. 7º, IX e art. 11, II, g), mediante ciência e aceite na tela de verificação. |
| **Localização do aparelho (GPS)** | Clientes (ao buscar) e profissionais (no check-in) | Mostrar profissionais próximos e registrar a prova de chegada do profissional no endereço do pedido. Nunca rastreamos localização em segundo plano fora do uso ativo. | Execução de contrato (art. 7º, V) e prevenção à fraude. |
| **Fotos do pedido, de check-in/check-out, de notas de material e de portfólio** | Clientes e profissionais | Formar o orçamento, comprovar a execução do serviço, registrar materiais e analisar eventuais disputas. Metadados de localização (EXIF) são removidos das fotos antes do envio. | Execução de contrato (art. 7º, V) e exercício regular de direitos (art. 7º, VI). |
| **Mensagens trocadas no chat do pedido** | Clientes e profissionais | Permitir a combinação do serviço e servir de prova caso haja divergência ou disputa. | Execução de contrato (art. 7º, V) e exercício regular de direitos (art. 7º, VI). |
| **Dados de pagamento e repasse** | Clientes e profissionais | Processar cobranças por Pix ou cartão e transferir valores aos profissionais. Os dados completos de cartão são tratados diretamente pelo parceiro de pagamento; o Trato recebe apenas identificadores e status da transação. | Execução de contrato (art. 7º, V) e obrigação legal/regulatória (art. 7º, II). |
| **Registros técnicos de acesso (IP, data e hora, identificadores de sessão)** | Todos os usuários | Segurança da plataforma e cumprimento do Marco Civil da Internet (Lei nº 12.965/2014). | Obrigação legal (art. 7º, II) e legítimo interesse de segurança (art. 7º, IX). |

---

## 2. O que o outro lado do pedido vê (e o que não vê)

Protegemos seus dados durante toda a negociação:

- **CPF, documento de identidade, selfie, telefone e e-mail** **nunca** aparecem no perfil público nem nas listas de pedidos ou orçamentos.
- **Antes do pagamento confirmado:** os profissionais da região veem apenas o título do pedido, a descrição, o **bairro** e as fotos do serviço. O endereço completo (rua, número e complemento) fica oculto.
- **No chat antes da contratação:** telefones, e-mails e links externos são **mascarados automaticamente**.
- **Depois do pagamento confirmado:** apenas o profissional contratado passa a ver o endereço completo do serviço para poder comparecer no horário agendado.

---

## 3. Com quem compartilhamos seus dados

Não vendemos seus dados pessoais. Compartilhamos apenas o estritamente necessário com:

1. **A outra parte do pedido** (cliente ou profissional contratado), dentro dos limites explicados na seção 2.
2. **Parceiro de pagamento e liquidação financeira** (**Stripe Brasil Soluções de Pagamento Ltda.**), para processar Pix, cartão, retenção vinculada ao pedido, estornos e repasses aos profissionais.
3. **Provedores de infraestrutura em nuvem, autenticação e armazenamento seguro** (**Supabase Inc.** e infraestrutura **Amazon Web Services — AWS**), que operam sob contrato de confidencialidade e segurança da informação.
4. **Autoridades públicas, judiciais ou administrativas**, quando houver obrigação legal ou ordem competente.

Caso algum provedor de nuvem processe dados fora do Brasil, garantimos que a transferência internacional ocorra apenas para países ou operadores que assegurem grau de proteção compatível com a LGPD (art. 33).

---

## 4. Como protegemos seus dados

- Comunicações criptografadas em trânsito (HTTPS/TLS).
- Controle de acesso por linha no banco de dados (*Row-Level Security*): cada usuário só acessa os próprios pedidos, contratos e mensagens.
- Fotos de documentos de verificação guardadas em armazenamento privado, sem link público, acessíveis apenas por URLs temporárias assinadas e com registro de auditoria de quem consultou e por quê.
- Remoção automática de metadados de localização (EXIF) das fotos capturadas no aplicativo antes do envio.

---

## 5. Por quanto tempo guardamos seus dados

Guardamos os dados pelo tempo necessário para cumprir as finalidades desta política e as exigências legais:

- **Conta ativa:** enquanto você mantiver sua conta no Trato.
- **Documentos de verificação recusados ou substituídos:** até **90 dias** após a decisão para fins de auditoria antifraude, sendo eliminados em seguida.
- **Registros de conexão e acesso à aplicação:** pelo mínimo de **6 meses**, conforme o art. 15 do Marco Civil da Internet (Lei nº 12.965/2014).
- **Contratos, notas, histórico financeiro (ledger), mensagens e provas de pedidos pagos:** por **5 anos** após a conclusão do serviço, para cumprimento de obrigações fiscais, contábeis e exercício regular de defesa em processos administrativos ou judiciais (prazos do Código de Defesa do Consumidor e do Código Civil).

Quando você pede a **exclusão da conta**, seus dados pessoais de perfil são desativados e anonimizados imediatamente, mantendo-se apenas os registros financeiros e contratuais cujo armazenamento é exigido por lei, bloqueados para qualquer outro uso.

---

## 6. Seus direitos como titular (art. 18 da LGPD)

Você pode, a qualquer momento e sem custo:

- **Confirmar e acessar** os dados que temos sobre você;
- **Corrigir** dados incompletos, inexatos ou desatualizados;
- **Exportar uma cópia** dos seus dados (*portabilidade*);
- **Rever e desligar consentimentos** opcionais (como avisos promocionais e WhatsApp);
- **Solicitar a exclusão da sua conta** e dos dados tratados com base em consentimento ou desnecessários.

### Como exercer no próprio aplicativo

Vá em **Perfil → Meus dados (LGPD)**. Nessa tela você consulta e altera seus consentimentos, solicita a **exportação dos seus dados** e pode pedir a **exclusão da sua conta** com confirmação em duas etapas.

Se preferir, fale diretamente com nosso Encarregado de Dados (DPO) pelo e-mail `privacidade@trato.app.br`. Respondemos às solicitações dentro dos prazos previstos na LGPD (até 15 dias para relatórios completos, conforme o art. 19, II).

---

## 7. Atualizações desta política

Sempre que esta Política de Privacidade passar por mudanças relevantes, avisaremos você no aplicativo e atualizaremos a data de vigência no topo deste documento.
