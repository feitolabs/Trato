# Spec: CNPJ do profissional (MEI ou outro CNPJ ativo), sem carência

Decisão do João (24/11/2026, revisada): o profissional precisa ter CNPJ para enviar orçamento e receber. O motivo é jurídico: o Trato é intermediário e não responde pelos profissionais, que são empresas próprias e não trabalham para o Trato. Por isso a proposta anterior de "carência de 30 dias com CPF" foi **descartada**: ela deixaria o Trato intermediando pessoa física, que é o risco que a regra quer evitar.

## Regra
1. Cadastro, navegação e preenchimento do perfil continuam livres.
2. **Enviar orçamento e receber** só com CNPJ validado (ativo). Sem exceção de prazo.
3. **Aceitar qualquer CNPJ ativo** (MEI, EI, ME, LTDA...), não só MEI: o que importa é ser pessoa jurídica própria. Mudança no Backend: hoje só aceita "optante MEI"; passar a aceitar CNPJ ativo e guardar o tipo (MEI ou outro) para exibir o selo.
4. Quem só tem CPF recebe um caminho curto: botão "Abrir meu MEI (grátis)" com passo a passo (Portal do Empreendedor, gov.br, cerca de 10 minutos, sem custo) e volta para informar o CNPJ. Pode concluir o cadastro antes e só precisa do CNPJ na hora de orçar.
5. Valor de serviço já concluído e pago nunca fica preso por falta de CNPJ.

## Outros pontos que sustentam o resguardo (a confirmar com o jurídico)
- **Termos do profissional:** declara ser pessoa jurídica própria, prestador independente, sem vínculo empregatício, sem exclusividade, define seus preços e horários; o Trato intermedia e retém o pagamento. Redação revisada por advogado.
- **Não criar subordinação no produto:** sem escala imposta, sem metas, sem punição por recusar pedido, sem preço fixado pelo Trato.
- **Conferir cadastro:** razão social/nome do titular compatível com o profissional verificado (também resolve o problema de alguém usar CNPJ de outra pessoa) e canal de contestação no admin.
- Verificar se a atividade (CNAE) do CNPJ combina com a categoria de serviço [hipótese; a BrasilAPI devolve o CNAE].

## Backend / App (próximas rodadas, depois da migration aprovada)
- Backend: aceitar CNPJ ativo de qualquer tipo, guardar `tipo_cnpj` (migration pede OK do João), conferência de titularidade, ligar `TRATO_MEI_OBRIGATORIO` só depois disso e das ressalvas da Segurança.
- Flutter: tela do CNPJ com status, selo e o botão "Abrir meu MEI (grátis)"; aviso claro ao tentar orçar sem CNPJ; liberar a rota do CNPJ para profissional em análise.

## Não sou advogado
Isto é desenho de produto. Quem confirma se o CNPJ basta para afastar responsabilidade, e a redação dos Termos, é o jurídico.
