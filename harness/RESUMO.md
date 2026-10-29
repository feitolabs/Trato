# Resumo do produto — Trato

## O que é

Marketplace de serviços presenciais (elétrica, hidráulica, pintura, montagem, limpeza,
ar-condicionado, chaveiro, diarista…). O cliente descreve o problema, recebe **até 5
orçamentos** de profissionais verificados em **até 48 h** e paga pelo app. O dinheiro fica
**retido** com o parceiro de pagamento (Stripe) e só é liberado quando o serviço termina.

Lema: **"Serviço feito, dinheiro liberado."** Diferencial: garantia de execução, não vitrine.

## Quem usa

| Perfil | O que faz | Abas do app |
|---|---|---|
| **Cliente** | Pede orçamento, compara, contrata, paga, acompanha, confirma, avalia, abre disputa, pede retrabalho | Início · Buscar · Pedidos · Mensagens · Perfil |
| **Profissional** | Se verifica, recebe pedidos, orça (calculadora com taxa e líquido), faz check-in/check-out, envia nota de material, cria aditivo, saca pela carteira | Início · Pedidos · Agenda · Carteira · Perfil |
| **Equipe Trato** (painel web) | Aprova profissionais, decide disputas, concilia pagamentos, configura taxa e prazos, suporte, auditoria | Painel administrativo |

## Ciclo do pedido (10 estados)

Aberto → Orçamento aceito → Pago e retido → Agendado → Em andamento → Em confirmação → Concluído.
Saídas: **Cancelado**, **Em disputa**, **Retrabalho**.

## Dinheiro (versão atual, com as observações)

- Orçamento grátis. Ao aceitar, o cliente paga **30% adiantado**; ao encerrar, paga o resto.
- Pagamento por **etapas** é opção.
- Liberação ao profissional **só ao encerrar** (ou automática após o prazo sem problema).
- Taxa Trato: **progressiva, base 7,5%, mínima configurável** (tabela no banco).
- Mostrar o custo do Stripe (Pix e cartão) e quanto sobra para o Trato.
- **Aditivo** com preço só vale se o cliente aprovar. **Nota dos materiais** enviada ao cliente.
- Problema = **disputa**: valor congelado, profissional responde em 48 h, decisão em até 5 dias úteis.

## Fases do produto

| Fase | O que entra |
|---|---|
| **MVP** (piloto, 1 cidade) | Cadastro/login, verificação do profissional, pedido com perguntas guiadas, até 5 orçamentos, contrato digital, Pix e cartão com valor retido, 30% adiantado, aditivos, check-in/código de início/check-out, linha do tempo, chat, avaliação, garantia e retrabalho, disputa, carteira e saque Pix, notificações, LGPD (exportar/excluir), painel admin (verificação, disputas, financeiro, configurações, auditoria) |
| **V1** (até 3 meses) | Contraproposta, profissional a caminho no mapa, gorjeta, contatos de confiança, chamada mascarada, pedido urgente, mapa de profissionais, níveis, modo offline parcial, cupons, nota fiscal, modelos de orçamento |
| **V2** | Vídeo/áudio no pedido, recorrência, empresa/condomínio, carteira do cliente, antecipação, equipe e ajudantes, planos e impulsionamento |

## Telas do protótipo (27)

Splash · Onboarding (1 de 3) · Escolha de perfil · Login · Cadastro passo 1 · Confirmar celular ·
Recuperar senha · Início do cliente · Buscar · Perfil do profissional · Novo pedido (passo 2 de 3) ·
Orçamentos recebidos · Detalhe do orçamento · Pagamento · Seus pedidos · Pedido em execução
(com aditivo e linha do tempo) · Chat · Conclusão (código) · Avaliação · Relatar problema ·
Garantia · Perfil do cliente · Início do profissional · Detalhe do pedido (profissional) ·
Calculadora de orçamento · Check-in · Carteira.
