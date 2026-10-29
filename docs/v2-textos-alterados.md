# Textos alterados — D13 (Auditoria V2)

Textos trocados por linguagem neutra. Só texto de tela (`lib/`); linhas de `test/` acompanham a mudança.

| Arquivo | Antes | Depois |
|---|---|---|
| `app/lib/telas/onboarding/onboarding_tela.dart` | 'O pagamento fica retido até a conclusão. Você confirma o serviço e o valor é liberado.' | 'O pagamento é processado por parceiro e acompanhado no app. Você confirma o serviço ao final.' |
| `app/lib/telas/onboarding/onboarding_tela.dart` | 'Abra uma disputa e o valor fica congelado até a decisão. Serviços com garantia ativa.' | 'Abra uma disputa e o caso passa por suporte e análise de problemas. O prazo de garantia do serviço vem no orçamento.' |
| `app/lib/telas/pagamento/pagamento_tela.dart` | 'Você paga agora e o profissional vê que o pagamento está garantido.' | 'Você paga e o app mostra "Aguardando confirmação do pagamento" até o parceiro confirmar.' |
| `app/lib/telas/pagamento/pagamento_tela.dart` | 'O pagamento fica retido, nas condições do arranjo com nosso parceiro de '         'pagamento, até a conclusão.' | 'O pagamento é processado por parceiro e acompanhado no app.' |
| `app/lib/telas/pagamento/pagamento_tela.dart` | 'Você confirma o serviço e o valor é liberado. Se algo der errado, abra uma '         'disputa e o valor fica congelado até a decisão.' | 'Você confirma o serviço ao final. Se algo der errado, abra uma disputa: '         'o caso passa por suporte e análise de problemas.' |
| `app/lib/telas/pagamento/pagamento_tela.dart` | 'Seu dinheiro fica protegido' | 'Como funciona o pagamento' |
| `app/lib/telas/cliente/inicio_tela.dart` | 'O pagamento fica retido até a conclusão.' | 'O pagamento é processado por parceiro e acompanhado no app.' |
| `app/lib/telas/onboarding/escolha_perfil_tela.dart` | 'Peça orçamentos e pague com o valor retido até a conclusão.' | 'Peça orçamentos e acompanhe o pagamento pelo app.' |
| `app/lib/telas/pedidos/pedido_execucao_tela.dart` | 'Pagamento retido até a conclusão' | 'Pagamento acompanhado no app' |
| `app/lib/telas/pedidos/dados_exemplo.dart` | 'Em execução · pagamento retido' | 'Em execução · pagamento acompanhado' |
| `app/lib/telas/pedidos/dados_exemplo.dart` | 'Disputa aberta · valor congelado' | 'Disputa aberta · em análise' |
| `app/lib/galeria/galeria_componentes.dart` | 'Em execução · pagamento retido' | 'Em execução · pagamento acompanhado' |
| `app/lib/galeria/galeria_componentes.dart` | 'Disputa aberta · valor congelado' | 'Disputa aberta · em análise' |
| `app/lib/componentes/chip_status.dart` | "Em execução · pagamento retido" | "Em execução · pagamento acompanhado" |
| `app/lib/componentes/chip_status.dart` | "Disputa aberta · valor congelado" | "Disputa aberta · em análise" |
| `app/lib/telas/conclusao/relatar_problema_tela.dart` | 'Valor congelado até a decisão. ' | 'Caso em análise. ' |
| `app/lib/telas/conclusao/relatar_problema_tela.dart` | '${formatarReais(valorCentavos)} ficam retidos enquanto o problema é resolvido.' | 'O suporte analisa o problema do serviço de ${formatarReais(valorCentavos)} e avisa a decisão.' |
| `app/lib/telas/conclusao/relatar_problema_tela.dart` | nossa equipe de mediação decide | nosso suporte analisa o caso e decide |
| `app/lib/telas/conclusao/dados_exemplo.dart` | 'Liberação automática em 48 horas, salvo disputa aberta. ' | 'Confirmação automática em 48 horas, salvo disputa aberta. ' |
| `app/test/conclusao_test.dart` | 'Liberação automática em 48 horas' | 'Confirmação automática em 48 horas' |
| `app/lib/telas/conclusao/conclusao_tela.dart` | 'Total retido' | 'Total do serviço' |
| `app/lib/telas/conclusao/avaliacao_tela.dart` | 'Pagamento liberado · ${formatarReais(dados.valorLiberadoCentavos)}' | 'Aguardando confirmação do pagamento · ${formatarReais(dados.valorLiberadoCentavos)}' |
| `app/lib/telas/conclusao/garantia_tela.dart` | 'Se não atender, outro profissional assume.' | 'Se não houver atendimento, o suporte analisa o caso.' |
| `app/lib/telas/splash_tela.dart` | 'Serviço feito, dinheiro liberado.' | 'Serviço combinado, tudo no app.' |
| `app/test/widget_test.dart` | 'Serviço feito, dinheiro liberado.' | 'Serviço combinado, tudo no app.' |
| `app/lib/telas/profissional/calculadora_orcamento_tela.dart` | 'A taxa só é cobrada quando o pagamento for liberado. ' | 'A taxa é cobrada após a confirmação do pagamento pelo parceiro. ' |
| `app/lib/telas/carteira/carteira_tela.dart` | rotulo: 'Retido', | rotulo: 'Em andamento', |
| `app/lib/telas/carteira/carteira_tela.dart` | rotulo: 'A liberar', | rotulo: 'Aguardando confirmação', |
| `app/lib/telas/carteira/carteira_tela.dart` | liberado ? 'Liberado' : 'A liberar' | liberado ? 'Confirmado' : 'Aguardando confirmação' |
| `app/lib/telas/carteira/dados_exemplo.dart` | 'Automático em até 48 h' | 'Após confirmação do parceiro' |
| `app/lib/telas/carteira/dados_exemplo.dart` | 'Nada a liberar' | 'Nada aguardando confirmação' |
| `app/test/carteira_test.dart` | find.text('Liberado') | find.text('Confirmado') |
| `app/test/carteira_test.dart` | find.text('A liberar') | find.text('Aguardando confirmação') |
| `app/test/profissional_inicio_test.dart` | find.text('Retido') | find.text('Em andamento') |
| `app/lib/telas/profissional_inicio/inicio_profissional_tela.dart` | rotulo: 'Retido' | rotulo: 'Em andamento' |
| `app/test/pagamento_perfil_test.dart` | 'Seu dinheiro fica protegido' | 'Como funciona o pagamento' |
| `app/test/pedidos_test.dart` | 'Pagamento retido até a conclusão' | 'Pagamento acompanhado no app' |
| `app/test/pedidos_test.dart` | 'Disputa aberta · valor congelado' | 'Disputa aberta · em análise' |
| `app/lib/telas/onboarding/onboarding_tela.dart` | Seu dinheiro fica protegido (título pág. 2) | Pagamento por parceiro, acompanhado no app |
| `app/lib/telas/onboarding/onboarding_tela.dart` | Se algo der errado, você tem garantia (título pág. 3) | Se algo der errado, há suporte |

## Outras mudanças

- `app/lib/telas/pedidos/recursos_mvp.dart`: nova constante `kSosHabilitado = false`. O botão SOS da tela de execução só aparece se for `true` (código mantido). Testes em `app/test/pedidos_test.dart`.
- Calculadora: o rótulo "Taxa Trato (x%)" já vem do serviço (`Dinheiro.formatarBps(taxaBps)`); nada fixo na tela. Sem mudança.
- Estado de pagamento: o app não mostra "Pago/Pagamento confirmado"; a avaliação passou a dizer "Aguardando confirmação do pagamento".
- Goldens regenerados só dos arquivos afetados por texto/SOS.

## Fora do escopo desta tarefa (ver follow-up)

- Nomes internos como `retidoCentavos`, `totalRetidoCentavos`, `valorCongeladoCentavos` e comentários de código seguem com "retido/congelado" (não aparecem na tela).
- Textos de cancelamento ("Reembolso integral até 24 horas antes") e opções de disputa ("Reembolso parcial/total") ficam: são regras do orçamento/escolha do cliente, não promessa do Trato.
