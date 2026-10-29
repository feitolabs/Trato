# Checklist de lançamento — os 7 bloqueios da V2

> Fonte: Auditoria e Escopo V2, seção 7 (29/10/2026), vale por D13. "Antes do primeiro pagamento real, resolver estes
> pontos em uma fonte de verdade e assinar responsáveis e datas." **Esta é essa fonte de verdade (rascunho).**
> Não é parecer jurídico. Donos abaixo são os **sugeridos pela V2**; nomes e datas: `[A DEFINIR: João]` (P19).
> Status em 29/10/2026, segundo `harness/PENDENCIAS.md`, `docs/v2-impacto.md` e os documentos desta rodada.
> Legenda: 🔴 aberto · 🟡 em andamento (rascunho existe) · 🟢 resolvido.

## Resumo

| # | Bloqueio | Dono (V2) | Responsável / data | Status |
|---|---|---|---|---|
| 1 | Fluxo financeiro | Financeiro + jurídico + parceiro | `[A DEFINIR]` | 🟡 |
| 2 | Preço e margem | Negócio + financeiro | `[A DEFINIR]` | 🟡 |
| 3 | Regra única de serviço | Produto + jurídico + operações | `[A DEFINIR]` | 🟡 |
| 4 | Responsabilidade e promessa | Jurídico | `[A DEFINIR]` | 🟡 |
| 5 | Dados e verificação | Privacidade + segurança | `[A DEFINIR]` | 🟡 |
| 6 | Atendimento | Operações + jurídico | `[A DEFINIR]` | 🔴 |
| 7 | Escopo geográfico | Operações + crescimento | `[A DEFINIR]` | 🔴 |

**Nenhum pagamento real até todos ficarem 🟢.** Hoje nenhum está.

---

## 1. Fluxo financeiro

**Definição exigida (V2):** parceiro contratado; titularidade/contas; split; liquidação; fundos insuficientes; reembolso; chargeback; prazo; suporte e conciliação. Não chamar de custódia protegida sem base contratual e regulatória.

| Já existe | O que falta |
|---|---|
| D15: caminho A (ledger só espelha o parceiro; sem saldo próprio nem saque) | **Proposta escrita de 2 provedores** (P16): usar `docs/pedido-de-proposta-provedores.md` |
| Comparação pública dos provedores: `docs/provedores-pagamento.md` | Escolher o parceiro e **assinar contrato** |
| Rascunho `docs/juridico/politica-de-pagamentos.md` | Confirmar por contrato: retenção/split, saldo negativo, chargeback, reembolso, KYC (P7) |
| Backend "pago só após o provedor" (V2.2) | Parecer do Adv. pagamentos sobre split ≠ custódia e enquadramento (itens 1 e 11 de `docs/advogado-e-contador.md`) |
| | Conciliação diária com o relatório do parceiro (tarefa V2.5) |
| | Refazer a F3.5 para o caminho A antes de aplicar no banco |

## 2. Preço e margem

**Definição exigida:** take rate inicial, mínimo se houver, método aceito, parcelamento, quem absorve custo, simulação por ticket/canal. Retirar do texto as decisões antigas conflitantes.

| Já existe | O que falta |
|---|---|
| Simulador: `docs/simulacao-margem.md` (com **estimativas**) | João decide **P2**: taxa única do piloto e mínimo em R$ |
| Tabela progressiva (D2) em espera | João decide **P3**: quem paga o custo do método e do parcelamento; pedido mínimo |
| Tarifas públicas coletadas em `docs/provedores-pagamento.md` | Trocar as estimativas pelas **tarifas da proposta** |
| | Confirmar que a margem é positiva nos tickets baixos e nos métodos oferecidos (a simulação mostra margem negativa no cartão em ticket baixo) |
| | Remover do texto de tela e de docs os "5%" e a menção à tabela de 3 faixas (P5) |

## 3. Regra única de serviço

**Definição exigida:** aceite, prazo para pagar, falta, remarcação, cancelamento, confirmação automática, disputa que congela repasse e retrabalho; distinção entre política da plataforma e direito legal.

| Já existe | O que falta |
|---|---|
| Rascunho `docs/juridico/politica-de-cancelamento-e-disputa.md` (janela separada do prazo legal; sem renúncia automática) | João decide **P1/P17**: janela (7 dias, ou 48 h + 7) e demais prazos |
| Prazos em tabela de configuração | Adv. consumidor revisa: arrependimento, serviço iniciado, garantia legal (itens 5 e 6) |
| Máquina de estados (F4.1) | Parceiro confirma se aceita pausar o repasse em disputa (P7) |
| | Textos de tela alinhados à política (V2.1 ajudou; revisar Conclusão e Relatar problema) |
| | Aprovação conjunta de Produto, jurídico e Operações; versão e data de vigência |

## 4. Responsabilidade e promessa

**Definição exigida:** papel do marketplace, relação de consumo, responsabilidade por profissional, limites da garantia e texto comercial. Não confiar em cláusula genérica de isenção.

| Já existe | O que falta |
|---|---|
| Rascunho `docs/juridico/termos-de-uso.md` | Adv. consumidor: papel do Trato, responsabilidade pela cadeia de fornecimento, regresso (item 3) |
| Textos proibidos barrados no app pelo `harness/verificar` (D13) | Adv. trabalhista: níveis, avaliações, recusa, risco de vínculo (item 4) |
| Sem garantia financiada pelo Trato (D13/P8) | Contrato do profissional (autonomia, aceite, sem exclusividade) |
| | João confirma os textos de onboarding (P14) sem promessas proibidas |
| | Texto comercial final (promessa de lançamento da V2, seção 8) revisado |

## 5. Dados e verificação

**Definição exigida:** mapa de dados, propósito/base legal, fornecedor, acesso, prazo de retenção, exclusão, incidentes, direitos e revisão humana.

| Já existe | O que falta |
|---|---|
| Mapa de dados: `docs/modelo-de-dados.md` | João escolhe o **fornecedor de verificação** (P10), proporcional ao risco da categoria |
| Rascunho `docs/juridico/politica-de-privacidade.md` (quadro de finalidade, base e retenção) | Adv. dados: bases legais, **RIPD** de biometria e antecedentes, prazos de retenção (N10, itens 7 e 12) |
| RLS e endereço só após contratação; auditoria imutável | Nomear o **encarregado (DPO)** e o plano de incidente |
| Nenhuma coleta de documento ou selfie em produção | Fluxo de revisão humana de decisão automatizada (item 13) |
| | Fornecedor de SMS (P11) e transferência internacional de dados, se houver |
| | Aplicar o plano de segurança do banco (`docs/seguranca-banco.md`) antes de dados reais |

## 6. Atendimento

**Definição exigida:** canais, cobertura, urgência, capacidade, registro de protocolo, cancelamento no canal adequado e indicadores exigidos conforme enquadramento.

| Já existe | O que falta |
|---|---|
| Tela de central de ajuda; painel admin com fila de casos (em andamento em outra sessão) | Definir canais, dias e horários e **capacidade** da equipe no piloto |
| Textos sem promessa de atendimento contínuo (D13) | Registro de protocolo e prazo de resposta |
| | **Sinalizar ao advogado:** o Decreto 13.135/2026 (SAC), citado na V2 com entrada em vigor indicada para 2/11/2026, fala em atendimento humano e em dados dos modelos de atendimento à Senacon. O texto **não foi reconferido** aqui. Perguntar: o Trato se enquadra? Que obrigações e prazos? (P18, item 14) |
| | Canal para cancelamento e para o titular de dados |
| | Indicadores a medir (tempo de resposta e de resolução) |

## 7. Escopo geográfico

**Definição exigida:** cidade, bairros, categorias e quantidade de profissionais verificados antes do marketing ao cliente.

| Já existe | O que falta |
|---|---|
| Protótipo usa BH/Savassi | João confirma a **cidade** (P6/P15) e os **bairros** |
| Tabelas `cidades` e `categorias` vazias | Escolher **2 ou 3 categorias de baixo risco** (sem obra estrutural, gás ou atividade regulada) |
| | Definir **quantos profissionais verificados** são necessários antes de abrir a demanda |
| | Recrutamento inicial e entrevistas dos dois lados |
| | Carregar só a cidade e as categorias do piloto (precisa de OK para escrever no banco) |

---

## Ordem sugerida

1. P16: enviar o pedido de proposta (João) → alimenta os bloqueios 1 e 2.
2. P15/P6: cidade e categorias → bloqueio 7 e escopo da verificação (5).
3. P1/P2/P3/P17: decisões do João → bloqueios 2 e 3.
4. Contratar o Adv. pagamentos primeiro, depois consumidor, dados e trabalhista (`docs/advogado-e-contador.md`).
5. Revisar os 4 rascunhos em `docs/juridico/` com os advogados.
6. P19: preencher donos e datas aqui e marcar 🟢 só com evidência (contrato, parecer, política aprovada).

## Critério de "pronto para o primeiro pagamento real"

- [ ] Contrato com o parceiro assinado e fluxo confirmado por escrito
- [ ] Margem positiva na simulação com tarifas reais
- [ ] Política de cancelamento e disputa aprovada por jurídico e parceiro
- [ ] Termos, privacidade e política de pagamentos revisados e versionados
- [ ] RIPD, DPO e retenção definidos
- [ ] Atendimento operando e enquadramento no decreto do SAC respondido
- [ ] Cidade, categorias e profissionais verificados suficientes
- [ ] Donos e datas assinados (P19)
