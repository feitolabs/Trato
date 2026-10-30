# Política de Privacidade — Trato

> **RASCUNHO PARA REVISÃO JURÍDICA. Não é texto final.** Quem escreveu não é advogado.
> Não publicar antes de revisão de advogado de dados (LGPD). Bases legais e prazos abaixo são **propostas**,
> não decisões. Normas citadas não foram reconferidas.
> Os pontos `[A DEFINIR: ...]` dependem do João (P1, P2, P6, P7, P10) ou do jurídico.
> Relacionados: `termos-de-uso.md`, `politica-de-pagamentos.md`, `docs/advogado-e-contador.md` (itens 7, 12, 13), `docs/modelo-de-dados.md`.
> Versão: `[A DEFINIR]`. Data: `[A DEFINIR]`.

## 1. Quem trata seus dados

**Controlador:** Feito Labs `[A DEFINIR: razão social, CNPJ, endereço]`.
**Encarregado (DPO):** `[A DEFINIR: nome e e-mail]`.

## 2. Resumo simples

- Coletamos o mínimo para conectar cliente e profissional, processar o pagamento e resolver problemas.
- Seu endereço completo só aparece ao profissional **depois** da contratação.
- Documento e selfie do profissional são dados sensíveis. Só pedimos conforme o risco da categoria, por empresa especializada.
- Você pode pedir acesso, correção, exclusão e revisão de decisões automatizadas.

## 3. Quadro de dados: o que, para quê e por quê

| Dado | Quem | Finalidade | Base legal (proposta) | Retenção (proposta) |
|---|---|---|---|---|
| Nome, e-mail, celular, senha (hash) | Todos | Criar e proteger a conta; confirmar o celular por SMS | Execução de contrato | Enquanto a conta existir + `[A DEFINIR]` |
| Data de nascimento | Todos | Conferir idade mínima | Obrigação legal / execução de contrato `[A DEFINIR: JURÍDICO]` | `[A DEFINIR]` |
| Bairro / CEP aproximado | Cliente | Achar profissionais da região | Execução de contrato | Enquanto a conta existir |
| Endereço completo | Cliente | Realizar o serviço contratado (visível ao profissional só após contratar) | Execução de contrato | `[A DEFINIR]` após o serviço |
| Pedido, fotos, orçamentos, chat | Todos | Registrar escopo, preço e aditivos; resolver disputa | Execução de contrato; exercício regular de direitos | `[A DEFINIR: prazo de guarda do histórico]` |
| Check-in e check-out (horário e local da chegada) | Profissional | Provar presença no serviço | Execução de contrato; legítimo interesse `[A DEFINIR: JURÍDICO]` | `[A DEFINIR]` |
| Dados de pagamento | Todos | Processar o pagamento pelo parceiro | Execução de contrato; obrigação legal | O parceiro guarda o que a lei exige. O Trato guarda só ids e status `[A DEFINIR: confirmar com o parceiro — P7]` |
| CPF / CNPJ, dados bancários do recebimento | Profissional | Cadastro no parceiro; recebimento; obrigações fiscais | Execução de contrato; obrigação legal | `[A DEFINIR: CONTADOR]` |
| Documento e selfie (verificação) | Profissional | Confirmar identidade | Ver seção 5 | Ver seção 5 |
| Antecedentes criminais | Profissional (só categorias de risco alto) | Reduzir risco em categorias específicas | Ver seção 5 | Ver seção 5 |
| Avaliações | Todos | Reputação ligada a serviço concluído | Legítimo interesse; execução de contrato | Enquanto o serviço existir no histórico |
| Registros de acesso (IP, data e hora) | Todos | Segurança; obrigação do Marco Civil `[A DEFINIR: Adv. dados confirma prazo]` | Obrigação legal | `[A DEFINIR: ex.: 6 meses, a confirmar]` |
| Dados de uso e do aparelho | Todos | Segurança, fraude, melhoria do app | Legítimo interesse `[A DEFINIR]` | `[A DEFINIR]` |

## 4. Com quem compartilhamos

- **Profissional ou cliente do serviço:** só o necessário para a execução.
- **Parceiro de pagamento** `[A DEFINIR: P7/P16 — nome do provedor]`: pagamento, divisão e repasse.
- **Fornecedor de verificação de identidade** `[A DEFINIR: P10]`.
- **Provedor de SMS** `[A DEFINIR: P11]`: apenas celular e código.
- **Infraestrutura** (banco de dados e hospedagem): `[A DEFINIR: local dos dados e eventual transferência internacional]`.
- **Autoridades**, por ordem legal ou obrigação legal.
- **Não vendemos dados.**

## 5. Biometria e dados sensíveis

5.1. A **selfie e a biometria facial** ligadas a uma pessoa são **dado pessoal sensível** (LGPD, segundo a ANPD citada pela Auditoria V2; fonte não reconferida).

5.2. Princípios do Trato: pedir só quando o risco da categoria justificar; usar empresa especializada; **guardar apenas o resultado mínimo** (aprovado, reprovado, data, nível); **evitar cópia** de documento e imagem.

5.3. Base legal: `[A DEFINIR: Adv. dados — consentimento específico e destacado, ou outra hipótese do art. 11 da LGPD para prevenção à fraude e segurança]`. O profissional pode recusar, mas sem a verificação não atende às categorias que a exigem.

5.4. Retenção: `[A DEFINIR: prazo para imagens (ideal: eliminar logo após a verificação) e para o resultado]`.

5.5. Antecedentes criminais: só em categorias de risco alto `[A DEFINIR: P15]`, preferindo certidão apresentada pelo próprio profissional, com consentimento. `[A DEFINIR: Adv. dados — RIPD antes de qualquer coleta.]`

5.6. Quem acessa: só equipe de cadastro, com cada leitura registrada em auditoria.

5.7. Nenhum documento ou selfie é coletado antes de o fornecedor, a base legal, a retenção e o RIPD estarem definidos.

## 6. Decisões automatizadas e revisão humana

6.1. O Trato usa regras automáticas para segurança (por exemplo, bloquear tentativas suspeitas de login e pagamento).

6.2. **Suspensão de conta, decisão de fraude contestada e decisão de disputa passam por analista humano**, com justificativa e canal de resposta. Não há ranking nem nota automática punitiva no piloto.

6.3. Você pode pedir **revisão** de decisão automatizada que afete seus interesses, no canal do encarregado. `[A DEFINIR: prazo de resposta e quem revisa.]`

## 7. Seus direitos (LGPD)

Você pode pedir, a qualquer momento:
- confirmação de que tratamos seus dados e **acesso** a eles;
- **correção** de dados incompletos ou errados;
- **anonimização, bloqueio ou eliminação** de dados desnecessários ou tratados fora da lei;
- **portabilidade** `[A DEFINIR]`;
- **eliminação** dos dados tratados com consentimento, ressalvadas as guardas obrigatórias;
- informação sobre com quem compartilhamos;
- **retirada do consentimento**, quando for a base legal;
- **revisão** de decisão automatizada.

Como pedir: tela Privacidade do app (exportar e excluir conta) ou o e-mail do encarregado. `[A DEFINIR: prazo de resposta.]`
Quando a exclusão conflita com guarda obrigatória (fiscal, disputa em curso), explicamos o que fica e por quê.

## 8. Segurança

Criptografia em trânsito, controle de acesso por perfil, trilha de auditoria imutável, endereço protegido até a contratação, documentos em armazenamento privado. Em incidente com risco relevante, avisamos a ANPD e os titulares `[A DEFINIR: prazo, ex.: 3 dias úteis, a confirmar com Adv. dados]`.

## 9. Crianças e adolescentes

O Trato é para maiores de 18 anos `[A DEFINIR: JURÍDICO — ECA Digital e verificação de idade]`.

## 10. Cookies e rastreadores

`[A DEFINIR: o app não usa publicidade de terceiros no piloto? Confirmar antes de publicar.]`

## 11. Mudanças nesta política

Versionada. Mudança relevante é avisada no app. `[A DEFINIR]`

## 12. Contato

Encarregado: `[A DEFINIR]`. Canal geral: `[A DEFINIR]`. Reclamações também podem ser feitas à ANPD.

---

### Anexo — nota interna (apagar na versão final)

- Pendências de dados: N10 (retenção de documentos), P10 (fornecedor), P11 (SMS), P7 (parceiro).
- RIPD de biometria e antecedentes ainda **não existe**.
- Mapa de dados completo: `docs/modelo-de-dados.md`.
