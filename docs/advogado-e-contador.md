# Lista para advogado e contador (F8.6)

> **O agente não decide nada disto.** Cada item é uma pergunta para um profissional habilitado.
> Até a resposta chegar, o código usa o valor provisório indicado e o app não promete o que está em aberto.
> Nada aqui é parecer jurídico. As normas citadas vêm do escopo (seções 8.3, 10, 19 e 20) e das
> pendências; o próprio escopo marca vários prazos como "a confirmar" e pede leitura do texto vigente
> no Planalto antes de qualquer decisão. **Não reconferi nenhuma norma.**

Fontes: `harness/PENDENCIAS.md`, `docs/modelo-de-dados.md` (seção 11), escopo seções 3.6, 8.3, 10, 19 e 20.
Quem responde: **Adv. pagamentos** (advogado de meios de pagamento), **Adv. consumidor**, **Adv. trabalhista**,
**Adv. dados** (LGPD), **Contador**.

## Resumo

| # | Tema | Quem | Bloqueia |
|---|---|---|---|
| 1 | Custódia do valor retido | Adv. pagamentos | Pagamento retido, carteira, F4.4 |
| 2 | Nota fiscal e tributação da taxa | Contador | Recibo, extrato, repasse |
| 3 | Responsabilidade solidária e direito de regresso | Adv. consumidor | Termos, disputa |
| 4 | Risco de vínculo empregatício | Adv. trabalhista | Níveis, ranking, penalidades |
| 5 | Janela de 7 dias (D3) × arrependimento e garantia legal | Adv. consumidor | Prazos de liberação e disputa |
| 6 | Cancelamento de serviço já iniciado | Adv. consumidor | Regra de reembolso |
| 7 | Antecedentes criminais e biometria | Adv. dados | Verificação do profissional |
| 8 | Fundo de garantia e reserva do profissional | Adv. pagamentos e seguros | Textos, garantia |
| 9 | Termos de uso, privacidade e contrato do profissional | Adv. consumidor e dados | Cadastro e aceite |
| 10 | Outros itens do checklist do escopo (20.2) | Vários | Antes do piloto |
| 11 | **V2:** split ≠ custódia e enquadramento no Banco Central | Adv. pagamentos | Caminho A/B (V2.4), F3.5 |
| 12 | **V2:** biometria como dado sensível (ANPD) | Adv. dados | Verificação (F6.1) |
| 13 | **V2:** revisão de decisão automatizada | Adv. dados | Antifraude, bloqueios, disputa |
| 14 | **V2:** Decreto 13.135/2026 (SAC) | Adv. consumidor | Atendimento, lançamento |

---

## 1. Custódia do valor retido
- **Pergunta:** reter dinheiro de terceiros até a conclusão e dividir o pagamento (split) exige que o Trato seja instituição de pagamento autorizada, ou o Stripe Connect cobre isso?
- **Por que importa:** o produto inteiro é "dinheiro retido até o serviço acabar". Sem resposta, a Feito Labs pode estar exercendo atividade regulada. O escopo diz que o enquadramento exato exige advogado especialista em meios de pagamento.
- **Depende de:** P7 (Stripe Connect com Pix e retenção; conta já existe?); tabelas `pagamentos`, `contas_ledger`, `lancamentos`, `repasses`, `saques`; telas de Pagamento e Carteira; tarefa F4.4. Também: obrigações de KYC/antilavagem (Lei 9.613/1998, segundo o escopo) e se o saldo negativo após estorno (N7) é permitido.
- **Enquanto isso:** o desenho (F3.1) prevê o parceiro de pagamento como custodiante, como recomenda o escopo. Nenhuma chamada real ao Stripe sem OK do João.

## 2. Nota fiscal e tributação da taxa
- **Pergunta:** como a Feito Labs emite nota fiscal da taxa do Trato e qual o enquadramento tributário (ISS, reforma tributária)? Há obrigações acessórias sobre repasses (ex.: DIMP) e informe de rendimentos aos profissionais?
- **Por que importa:** cada serviço gera receita de taxa; errar o enquadramento vira passivo fiscal. O recibo e o extrato do app precisam dizer o que é taxa e o que é repasse.
- **Depende de:** tabela `contratos` (`taxa_trato_centavos`), conta `receita_trato` do ledger, `repasses`; telas Recibo e Carteira (extrato); D2 e P2 (taxa progressiva); P3 (quem paga a taxa e o custo do Stripe); N4 (taxa incide sobre material?).
- **Enquanto isso:** nenhuma regra fiscal é implementada; o tema fica aberto.

## 3. Responsabilidade solidária e direito de regresso
- **Pergunta:** o Trato responde perante o consumidor pela cadeia de fornecimento (CDC, arts. 7º, 14, 25 e 51, I, a confirmar)? Como redigir o direito de regresso contra o profissional sem afastar essa responsabilidade?
- **Por que importa:** o escopo (seção 19) aponta como conflito a cláusula de "limites de responsabilidade" prevista na 8.3: cláusula que isenta o fornecedor é nula. A decisão de disputa e o reembolso dependem de quem arca com o quê.
- **Depende de:** termos de uso e contrato do profissional (item 9); tabelas `disputas` (`decisao`, `valor_reembolso_centavos`), `retrabalhos` (`custo_centavos`); regra F4.7; saldo negativo do profissional (N7).
- **Provisório:** o app não afirma isenção de responsabilidade em nenhum texto.

## 4. Risco de vínculo empregatício
- **Pergunta:** quais mecanismos do Trato (níveis, ranking, metas, penalidade por recusa, treinamento obrigatório, controle de preço ou horário) sugerem subordinação (CLT art. 3º; Tema 1291 do STF; Convenção 193 da OIT)?
- **Por que importa:** o escopo (seções 8.3, 19 e 20) classifica como risco médio e pede revisão trabalhista antes do lançamento. Também manda que recusar pedido com motivo válido nunca reduza o score.
- **Depende de:** níveis do profissional (`perfis_profissional.nivel_verificacao`), notas e ranking (N15, ainda não modelados), `categoria_perguntas`/preço livre no orçamento, penalidades em disputas, contrato do profissional.
- **Enquanto isso (ajuste já aplicado no escopo):** preço livre do profissional, recusa com motivo sem penalidade e sem exclusividade. Score e ranking não estão modelados (N15) até o parecer.

## 5. Janela de 7 dias (D3) × direito de arrependimento e garantia legal
- **Pergunta:** o "cliente tem até 7 dias para reclamar (ou ir à Justiça)" da decisão D3 e a liberação do saldo em 7 dias (D6) são compatíveis com o direito de desistência de 7 dias (CDC art. 49), com os prazos de reclamação por vício (30/90 dias, a confirmar no art. 26) e com a nulidade de cláusulas que reduzam direitos?
- **Por que importa:** o escopo (seção 19) marcou como conflito o limite de 72 horas para abrir disputa. O prazo curto só pode valer para congelar o repasse; o direito de reclamar segue os prazos legais. Liberar o dinheiro ao profissional não pode encerrar o direito do consumidor.
- **Depende de:** P1 (48 h × 7 dias); N17; chaves de configuração `janela_chargeback_dias`, `prazo_liberacao_dias`, `prazo_congelar_disputa_horas`; `pagamentos.janela_chargeback_ate`; textos das telas Conclusão, Carteira e Relatar problema; F4.7 e F4.9.
- **Enquanto isso:** os prazos ficam em tabela de configuração, não no código, e podem mudar sem nova versão do app.

## 6. Cancelamento de serviço já iniciado
- **Pergunta:** qual a regra para o cliente que desiste dentro de 7 dias quando o serviço já começou a pedido dele, e pode o Trato reter deslocamento e tempo gasto?
- **Por que importa:** a regra de cancelamento do escopo (seção 3.2) retém deslocamento conforme a antecedência. O escopo diz que isso conflita com o art. 49 e que a regra para serviço iniciado deve ser definida com advogado.
- **Depende de:** parâmetros de cancelamento (`prazo_cancelamento_reembolso_integral_horas`), item `deslocamento` em `orcamento_itens`, `agendamentos.status`, `presencas` (prova de que o profissional chegou); tela de cancelamento com a regra visível antes de confirmar.
- **Enquanto isso:** a regra detalhada de serviço iniciado não é implementada; o escopo (3.2) só define reembolso integral com mais de 24 h de antecedência.

## 7. Antecedentes criminais e biometria
- **Pergunta:** qual a base legal, o relatório de impacto (RIPD) e o **prazo de retenção** de documento, selfie, biometria facial e certidão de antecedentes (dados sensíveis, LGPD)? Onde guardar e quem pode ver?
- **Por que importa:** o escopo exige finalidade específica, consentimento e acesso restrito, e lista o RIPD de biometria e antecedentes como faltante. O prazo de retenção é a pendência N10.
- **Depende de:** P10 (fornecedor de verificação); tabelas `verificacoes` (`consentimento_lgpd_em`), `verificacao_documentos` (`excluir_em`, `validade_em`) e o bucket privado de documentos; RLS "só equipe de cadastro"; telas de cadastro e status da análise (Fase 6); auditoria de cada leitura.
- **Enquanto isso:** `excluir_em` fica sem prazo (N10). O escopo prefere a certidão apresentada pelo próprio profissional, com consentimento.

## 8. Fundo de garantia e reserva do profissional
- **Pergunta:** de onde vem o dinheiro do fundo de garantia (parte da taxa, fundo próprio ou seguro de parceiro) e a Feito Labs pode oferecer essa cobertura sem ser seguradora? A reserva opcional de ~3% do profissional é permitida?
- **Por que importa:** o escopo diz que exige análise jurídica e atuarial antes de ser prometida ao mercado. O contexto do projeto manda não prometer cobertura de danos até fechar.
- **Depende de:** P8; N6; `retrabalhos.custo_centavos` (quem paga o outro profissional); sem conta de fundo no ledger; textos da tela Garantia.
- **Enquanto isso:** só a garantia de retrabalho do escopo; o app não promete cobertura de danos (P8).

## 9. Termos de uso, política de privacidade e contrato do profissional
- **Pergunta:** qual a redação final dos termos de uso (intermediação, não empregadora), da política de privacidade e do contrato do profissional (autonomia de preço, aceite e recusa sem penalidade, sem exclusividade)?
- **Por que importa:** o aceite precisa ser versionado e provável. As regras do console de configuração também exigem aceite do usuário por versão para termos e política.
- **Depende de:** `usuarios.aceite_termos_versao` e `aceite_termos_em`; `contratos` (`hash_documento`, `aceite_ip`); itens 3, 4, 5 e 6; telas de cadastro, Privacidade (exportar e excluir conta) e Contrato digital.
- **Enquanto isso:** os textos jurídicos ficam como marcadores; a redação final é do jurídico.

## 10. Outros itens do checklist do escopo (20.2)
Não foram pedidos um a um, mas dependem de profissional e estão no escopo. Registrados para não se perderem:

| Item | Quem | Depende de |
|---|---|---|
| Idade mínima de 18 anos, com verificação além da autodeclaração (ECA Digital) | Adv. dados | `usuarios_privados.data_nascimento`; cadastro |
| Encarregado (DPO) nomeado e divulgado; plano de resposta a incidentes com aviso à ANPD e aos titulares em 3 dias úteis | Adv. dados | papel `dpo` em `equipe`; `auditoria` |
| Guarda de registros de acesso (6 meses, a confirmar) e fluxo de ordem judicial | Adv. dados | `auditoria`; logs |
| Enquadramento no decreto do SAC (vale a partir de 2/11/2026, segundo o escopo): atendimento humano 8h às 20h | Adv. consumidor | Central de ajuda; fora do banco |
| Revisão humana de bloqueios, rebaixamento de nível e decisões de antifraude | Adv. dados | Painel (Fase 7) |
| Preço total, taxa de parcelamento e número de parcelas visíveis antes do pagamento | Adv. consumidor | `pagamentos.parcelas`, `acrescimo_cliente_centavos`; P3; tela de Pagamento |

---

## Próximo passo sugerido
Contratar o **Adv. pagamentos** primeiro (itens 1, 8 e 11): a resposta define se o desenho de dinheiro (F4.4 e F4.6)
pode seguir como está. Os itens 5 e 6 mudam só números e textos de configuração; os itens 3, 4 e 9 mudam os termos.

---

## Pontos novos da V2 (Auditoria e Escopo V2, 29/10/2026)

> A V2 vale (D13), mas diz que não substitui parecer jurídico. Fontes citadas por ela (BCB, ANPD, Ministério da Justiça) **não foram reconferidas aqui**. Análise de impacto: `docs/v2-impacto.md`.

### 11. Split não é custódia; enquadramento no Banco Central
- **Pergunta:** dividir o pagamento (split) entre profissional e Trato, com retenção até a conclusão, exige autorização do Banco Central? O Trato é marketplace, subcredenciador ou outra figura? O parceiro cobre a liquidação centralizada? Quem responde por saldo negativo, chargeback e reembolso?
- **Por que importa:** a V2 diz que "split" não é sinônimo de custódia nem de proteção contra chargeback, e proíbe criar saldo ou custódia própria sem confirmação contratual e técnica do parceiro. O modelo atual tem ledger, repasses e saques (F3.5). Também proíbe chamar de "escrow" sem base contratual e regulatória.
- **Depende de:** P7 e P16; caminho A (ledger espelho) ou B (manter); tabelas `contas_ledger`, `lancamentos`, `repasses`, `saques`, `chaves_pix`; Carteira; F4.4.
- **Enquanto isso:** F3.5 não é aplicada; o app não mostra "pago" antes do provedor e não usa "escrow", "dinheiro protegido" nem "reembolso automático".

### 12. Biometria como dado pessoal sensível (ANPD)
- **Pergunta:** a selfie e a biometria facial do profissional são dado sensível. Qual a necessidade, a base legal, os controles e a retenção? Dá para usar só o resultado do fornecedor, sem guardar a imagem? Antecedentes só em categorias de risco alto?
- **Por que importa:** a V2 trata biometria como exceção de alto risco e pede verificação **proporcional ao risco da categoria**, com resultado mínimo guardado e sem cópia de documentos. Isso reforça o item 7.
- **Depende de:** P10 e P15; `verificacoes`, `verificacao_documentos` (`excluir_em`), `perfis_profissional.nivel_verificacao` (`verificado_plus` fica desligado); bucket privado; RIPD.
- **Enquanto isso:** nenhum documento ou selfie é coletado em produção; `excluir_em` segue sem prazo (N10).

### 13. Revisão de decisão automatizada
- **Pergunta:** quais decisões do Trato são automatizadas e afetam interesses do titular (bloqueio, suspensão, antifraude, liberação ou congelamento de repasse, nível de verificação)? Como oferecer o direito de pedir revisão (LGPD, segundo a ANPD citada pela V2) e quem revisa?
- **Por que importa:** a V2 exige revisão humana para suspensão, fraude contestada e decisão de disputa, com justificativa e canal de resposta. Score e ranking automáticos estão fora do MVP.
- **Depende de:** `auditoria`; `disputas` (decisão por analista com justificativa); painel admin (V2.6); antifraude (F8.2); política única (P17).
- **Enquanto isso:** nenhuma decisão punitiva é automática; análise humana nas filas.

### 14. Decreto 13.135/2026 (SAC)
- **Pergunta:** o Trato se enquadra no decreto (entrada em vigor indicada para 2/11/2026)? Quais obrigações: atendimento humano, canais, protocolo, indicadores e entrega de dados dos modelos de atendimento à Senacon? Prazos?
- **Por que importa:** a V2 pede confirmar o enquadramento antes do lançamento. Prometer "atendimento 24/7" está proibido (D13).
- **Depende de:** P18; central de ajuda; operação do piloto. Complementa a linha do SAC do item 10 (que usa data e horário vindos do escopo antigo; **valem os da V2 após o advogado confirmar**).
- **Enquanto isso:** nenhuma promessa de horário ou de resposta imediata nos textos.
