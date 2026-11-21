# Resumo do produto — Trato

> Atualizado em 20/11/2026 (D2). A seção "Estado atual" no fim traz o que está no ar. O texto do protótipo (30/10) segue abaixo, com as regras de dinheiro corrigidas pelas decisões D16 (30/10) e do João (18/11 a 20/11).

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

## Dinheiro (versão atual, 20/11/2026)

- Orçamento grátis. Decisão D16 (30/10): **sem os 30% adiantados** (confirmar no código; ver `PENDENCIAS.md`, Dúvidas).
- Pagamento por **etapas** é opção.
- Liberação ao profissional: cliente confirma em **48 h**; depois, **7 dias** de janela de reclamação (D16); disputa congela o valor.
- **Sem taxa do Trato para ninguém** (decisão do João, 18/11/2026; substitui a taxa progressiva de 7,5%). O Trato absorve o custo do Stripe no Pix e no cartão à vista; o custo de parcelamento é repassado ao cliente.
- **Tratinhos** (moedas): o cliente ganha ao avaliar (liberado 7 dias depois, se não houver disputa) e usa como desconto; o desconto é pago pela empresa, com orçamento de R$ 300/mês, R$ 10/dia e R$ 5 por cliente/mês; 1 Tratinho = 1 centavo. Pix com validade igual à reserva do desconto. Decisões em `docs/decisoes-moedas-e-exclusividade.md`.
- **Exclusividade de 48 h** (Etapa B): o profissional pode usar Tratinhos para ter exclusividade sobre um pedido por 48 h; a moeda do profissional nunca vira desconto.
- **Aditivo** com preço só vale se o cliente aprovar. **Nota dos materiais** enviada ao cliente.
- Problema = **disputa**: valor congelado, profissional responde em 48 h, decisão em até 5 dias úteis.
- Sem garantia financiada pelo Trato nem fundo ou seguro no MVP (D13): o app fala em "suporte e análise de problemas".

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

## Estado atual (20/11/2026)

**Infraestrutura (no ar)**
- **Backend (API Python):** Fly.io, app `trato`, região gru (São Paulo), 2 máquinas, **release v37** (`flyctl releases -a trato`). Histórico de 20/11: v30 moedas/orçamento; v31 exclusividade 48 h; v32 CPF opcional; v33 F7/B5/F8; v34 B6; v35 B7/B8; v36 B9/B10; v37 B11 (ledger idempotente e teto por lançamento). Saúde: `GET https://trato.fly.dev/saude` = 200.
- **Agendador: desligado** (`TRATO_AGENDADOR_EMBUTIDO="false"`): reservas de Tratinhos não expiram e bônus não são liberados; risco baixo enquanto há poucas moedas emitidas, mas não serve para piloto com dinheiro real. Decisão do João: manter desligado por ora.
- **Painel administrativo (Flutter web):** Vercel, projeto `trato-admin`, https://trato-admin-delta.vercel.app, com "Definir nova senha" e "Esqueci a senha" (`5dbc8c1`). O plano Hobby da Vercel não vale para uso comercial.
- **Banco:** Supabase "Trato". Aplicadas em 18 a 20/11: moedas (gamificação, desconto, orçamento, reservas), ranking, exclusividade (schema e funções) e CPF opcional. Preparada e **não aplicada**: `20261118150000_remove_faixas_taxa.sql`.
- **Domínio:** `tratofeitolabs.com.br` registrado no Registro.br, ainda sem DNS e sem versão web do app (plano de 20/11 com o Mestre).

**Produto**
- App cliente e profissional (Flutter, versões até 0.1.30 em `builds/`), 100% gratuito, com Tratinhos, exclusividade de 48 h, "Estou a caminho", extrato em PDF, favoritos ("Profissionais de confiança") e perfil público do profissional sem login (`GET /v1/publico/profissionais/{id}`).
- Busca com **ranking**: média ponderada (bayesiana) e nota composta (volume, verificação e disponibilidade), pesos configuráveis no painel (`ranking_config`).
- Painel admin: verificação, disputas, financeiro e fechamento, operação, moedas (tela de Tratinhos e alerta de 80% do orçamento), ranking, configurações e auditoria.

**Código local, sem push nem deploy** (branch `develop`, 10 commits à frente de `origin/develop` = `3977e3d`): B12 `0beda5e` (corrida, disputa, IDOR, `desconto_cupom_centavos`), B13 `c5f0b41` (limite por usuário do cupom, reservas do mês, bônus no fuso de São Paulo), B14 `27a5351` (SEG-1, SEG-2, SEG-4), F21 `6269a7b`, F22 `d5339aa`, F23 `8a58de9`, F24 `cdc7e28` (correções do app), A4 `6163cbb` (painel) e os testes QA3 a QA5. O backend no ar (v37) tem a B11 e **não** tem a B12 a B14. Falta OK do João para push e deploy.

**Pendências principais:** ver `PENDENCIAS.md` ("Estado em 20/11/2026").
