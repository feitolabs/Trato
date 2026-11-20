import 'package:flutter/material.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'convite.dart';

class ItemResumoSucesso {
  const ItemResumoSucesso(this.rotulo, this.valor);

  final String rotulo;
  final String valor;
}

/// Tela de confirmação/sucesso ao concluir uma ação importante (orçamento, pedido, check-out,
/// avaliação, disputa etc.), com próximo passo claro e saída limpa para a aba inicial.
class SucessoAcaoTela extends StatelessWidget {
  const SucessoAcaoTela({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.aoVoltarInicio,
    this.detalhes = const [],
    this.textoBotaoPrimario = 'Voltar ao início',
    this.aoTocarPrimario,
    this.textoBotaoSecundario,
    this.aoTocarSecundario,
    this.aoIndicar,
    this.acaoExtra,
    this.compartilhar = compartilharNoAparelho,
    this.icone = Icons.check_circle_rounded,
  });

  final String titulo;
  final String subtitulo;
  final List<ItemResumoSucesso> detalhes;
  final String textoBotaoPrimario;
  final VoidCallback aoVoltarInicio;
  final VoidCallback? aoTocarPrimario;
  final String? textoBotaoSecundario;
  final VoidCallback? aoTocarSecundario;
  final VoidCallback? aoIndicar;

  /// Botão extra opcional acima de "Indicar o Trato" (ex.: "Salvar como de confiança").
  final Widget? acaoExtra;

  /// Compartilhamento do convite (troca nos testes).
  final CompartilharTexto compartilhar;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final sair = aoTocarPrimario ?? aoVoltarInicio;
    final secundario = aoTocarSecundario ?? (aoTocarPrimario != null ? aoVoltarInicio : null);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) aoVoltarInicio();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x8),
                    child: ConteudoResponsivo(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: const BoxDecoration(
                              color: CoresTrato.verdeSuave,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icone, size: 48, color: CoresTrato.verdeTexto),
                          ),
                          const SizedBox(height: EspacosTrato.x5),
                          Text(
                            titulo,
                            style: TipografiaTrato.tituloGrande,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: EspacosTrato.x3),
                          Text(
                            subtitulo,
                            style: TipografiaTrato.corpo.copyWith(
                              color: CoresTrato.textoSecundario,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (detalhes.isNotEmpty) ...[
                            const SizedBox(height: EspacosTrato.x6),
                            CartaoTrato(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < detalhes.length; i++) ...[
                                    if (i > 0) const SizedBox(height: EspacosTrato.x2),
                                    LinhaDetalheCartao(
                                      rotulo: detalhes[i].rotulo,
                                      valor: detalhes[i].valor,
                                      estiloRotulo: TipografiaTrato.corpoPequeno.copyWith(
                                        color: CoresTrato.textoSecundario,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                color: CoresTrato.superficie,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                    child: ConteudoResponsivo(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BotaoPrimario(texto: textoBotaoPrimario, aoTocar: sair),
                          if (textoBotaoSecundario != null && secundario != null) ...[
                            const SizedBox(height: EspacosTrato.x2),
                            BotaoSecundario(
                              texto: textoBotaoSecundario!,
                              aoTocar: secundario,
                            ),
                          ],
                          const SizedBox(height: EspacosTrato.x1),
                          if (acaoExtra != null) acaoExtra!,
                          BotaoLink(
                            texto: 'Indicar o Trato',
                            aoTocar: () async {
                              if (aoIndicar != null) {
                                aoIndicar!();
                                return;
                              }
                              await indicarOTrato(context, compartilhar: compartilhar);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
