# Telas do profissional (F6.1, F6.5, F6.7) e lado do cliente do aditivo/nota (F5.9)

Todas as telas recebem um **serviço por interface** (com fake `Servico…Fake` para teste/demonstração) e
**callbacks**. Nenhuma conhece a rede. Nenhuma calcula dinheiro: valores em centavos inteiros; o líquido do
aditivo vem do `ServicoOrcamento` (já existente). Estados: carregando, vazio, erro com "Tentar de novo"
(`PaginaCarregavel`) e, nos formulários, "enviando" e "falha ao enviar" com mensagem simples.
Peças comuns: `app/lib/telas/profissional_apoio/apoio.dart`.

## Fonte do design

O protótipo (PDF) **não foi conferido página a página** nesta entrega. Todas as telas abaixo seguem o padrão
visual das telas vizinhas (tokens de `app/lib/tema/`, componentes de `app/lib/componentes/`). Tratar todas como
**"sem protótipo"** até o João/design conferir. Exceção parcial: o cartão de aditivo do cliente reaproveita o
texto e o estado (`EstadoAditivo`) que já existem em `telas/pedidos/pecas.dart` (`CartaoAditivo`).

## Lista de telas e o que ligar em `rotas.dart`

| Tela | Arquivo | Serviço (interface) | Callbacks a ligar |
|---|---|---|---|
| Cadastro do profissional (F6.1) | `profissional_cadastro/cadastro_profissional_tela.dart` | `ServicoCadastroProfissional` | `aoAdicionarFoto` (`Future<String?>`: câmera/galeria → referência), `aoConcluir` (ir para Verificação) |
| Verificação (F6.1) | `verificacao/verificacao_tela.dart` | `ServicoVerificacao` | `aoCapturarDocumento`, `aoCapturarSelfie` (`Future<String?>`), `aoConcluir` |
| Enviar nota dos materiais (F6.5) | `nota_material/enviar_nota_tela.dart` | `ServicoNotaMaterial` | `aoCapturarFoto`, `aoEnviada`; parâmetros `pedidoId`, `tituloPedido` |
| Criar aditivo (F6.5) | `aditivo/criar_aditivo_tela.dart` | `ServicoAditivo` + `ServicoOrcamento` (líquido) | `aoCriado`; `pedidoId`, `tituloPedido` |
| Ver nota dos materiais (cliente, F5.9) | `nota_material/ver_nota_tela.dart` | `ServicoNotaMaterial` | só `pedidoId` |
| Aprovar/recusar aditivo (cliente, F5.9) | `aditivo/responder_aditivo_tela.dart` | `ServicoAditivo` | `aoResponder(bool aprovou)`; `aditivoId` |
| Responder disputa (F6.7) | `disputa_profissional/responder_disputa_tela.dart` | `ServicoDisputaProfissional` | `aoAdicionarEvidencia`, `aoRespondida(TipoRespostaDisputa)`; `disputaId` |
| Atender retrabalho (F6.7) | `disputa_profissional/atender_retrabalho_tela.dart` | `ServicoDisputaProfissional` | `aoAgendado(String horario)`; `disputaId` |
| Perfil público do profissional | `perfil_publico/perfil_publico_tela.dart` | `ServicoPerfilPublico` | `aoVerAvaliacoes`, `aoEditarCadastro` |
| Avaliações recebidas | `perfil_publico/avaliacoes_recebidas_tela.dart` | `ServicoPerfilPublico` | nenhum |

Sugestão de pontos de entrada (a decidir por quem é dono de `rotas.dart`):
- Cadastro → Verificação: depois do cadastro do profissional (substitui o desvio atual para a casca).
- Enviar nota / Criar aditivo: botões no detalhe do pedido em execução do profissional.
- Ver nota / Responder aditivo: no pedido em execução do cliente (`CartaoAditivo` já mostra o aditivo; ele pode
  abrir `ResponderAditivoTela` ou continuar com os botões inline).
- Responder disputa / Atender retrabalho: notificação ou item na lista de pedidos do profissional.
- Perfil público / Avaliações: aba Perfil da casca do profissional (hoje "em breve").

## Serviços reais que faltam (backend)

Cada interface está no arquivo de modelos da pasta (`cadastro.dart`, `verificacao.dart`, `nota_material.dart`,
`aditivo.dart`, `disputa.dart`, `perfil_publico.dart`). As implementações reais chamam a API; os fakes são
provisórios. Fotos: o app devolve só uma referência (String); o envio ao bucket (`verificacao`, `pedido-midias`)
é de quem implementar o serviço.

## Cuidados de texto (V2, D13 a D15)

- Verificação: "confere se o documento é seu; não garante a qualidade de nenhum serviço". Sem "profissional
  seguro" nem "verificado plus". Finalidade, retenção e quem vê (LGPD) vêm do serviço (`TextoLgpd`); o texto de
  exemplo tem o prazo marcado como **a definir com o jurídico** (ver `docs/advogado-e-contador.md`).
- Aditivo: "só vale se o cliente aprovar no app". O app nunca mostra o aditivo como "pago".
- Disputa: usa "valor congelado até a decisão" (igual ao Relatar problema). Sem "escrow" nem "garantia total".
- Taxa mostrada no aditivo (`Taxa do Trato (7,5%)`) é só o que o backend devolveu.

## Testes

- `app/test/telas_profissional_test.dart`: estados (carregando/erro/vazio), fluxos de cada tela, validações, e
  todas as telas em 320 dp com fonte 2.0 (limitada a 1.3 pelo app) sem estouro.
- `app/test/golden/telas_profissional_golden_test.dart`: 14 variantes × 3 tamanhos (320, 390, 768).
  Atualizar: `flutter test --update-goldens test/golden/telas_profissional_golden_test.dart`.
- Goldens de carregando e de erro dos formulários não existem (só `avaliacoes_erro`); os estados estão cobertos
  nos testes de widget.
