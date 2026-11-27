import 'dart:ui';

import 'package:flutter/material.dart';

import '../tema/tema.dart';
import 'barra_abas.dart';

/// Barra de navegação inferior flutuante em cápsula (estilo iOS / Uber).
/// Usa [CoresTemaTrato] para adaptar-se automaticamente ao modo claro e ao modo escuro.
class BarraAbasFlutuante extends StatelessWidget {
  const BarraAbasFlutuante({
    super.key,
    required this.abas,
    required this.indiceAtual,
    required this.aoSelecionar,
  });

  final List<AbaTrato> abas;
  final int indiceAtual;
  final ValueChanged<int> aoSelecionar;

  /// Altura aproximada ocupada pela cápsula + margem, para reservar espaço no scroll.
  static const alturaReservada = 88.0;

  /// Folga inferior real para listas e botões. Dentro do corpo de um Scaffold com extendBody, o
  /// `padding.bottom` é a altura real da cápsula (já com o inset de gestos/3 botões) e o
  /// `viewPadding.bottom` vem zerado; fora dele vale [alturaReservada] + inset do sistema.
  static double folgaInferior(BuildContext context) {
    final midia = MediaQuery.of(context);
    final fora = alturaReservada + midia.viewPadding.bottom;
    return midia.padding.bottom > fora ? midia.padding.bottom : fora;
  }

  /// Quanto reduzir para o rótulo mais largo caber em [largura]. Mede em negrito (a aba
  /// escolhida), para o tamanho não mudar quando a pessoa troca de aba.
  double _escalaDosRotulos(BuildContext context, double largura) {
    var maior = 0.0;
    for (final aba in abas) {
      final medida = TextPainter(
        text: TextSpan(
          text: aba.rotulo,
          style: DefaultTextStyle.of(context).style.merge(_estiloDoRotulo(selecionada: true)),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1),
        maxLines: 1,
      )..layout();
      if (medida.width > maior) maior = medida.width;
      medida.dispose();
    }
    return maior <= largura || largura <= 0 ? 1 : largura / maior;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final midia = MediaQuery.of(context);
    // Em tela estreita as margens encolhem para os rótulos continuarem legíveis.
    final estreita = midia.size.width < 360;
    final folgaDoItem = estreita ? EspacosTrato.x1 / 2 : EspacosTrato.x1;

    return MediaQuery(
      data: midia.copyWith(textScaler: midia.textScaler.clamp(maxScaleFactor: 1)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            estreita ? EspacosTrato.x2 : EspacosTrato.x4,
            EspacosTrato.x1,
            estreita ? EspacosTrato.x2 : EspacosTrato.x4,
            EspacosTrato.x3,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: (escuro ? CoresTrato.sombra : c.petroleo).withValues(
                        alpha: escuro ? 0.42 : 0.14,
                      ),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.superficie.withValues(alpha: escuro ? 0.86 : 0.90),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: c.borda.withValues(alpha: escuro ? 0.75 : 0.9),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: estreita ? EspacosTrato.x1 : EspacosTrato.x2,
                          vertical: EspacosTrato.x2 - 2,
                        ),
                        child: LayoutBuilder(
                          builder: (context, limites) {
                            // Uma escala só para os cinco rótulos: encolher cada um por conta
                            // própria deixa tamanhos desiguais em tela estreita.
                            final escala = _escalaDosRotulos(
                              context,
                              limites.maxWidth / abas.length - folgaDoItem * 2,
                            );
                            return Row(
                              children: [
                                for (var i = 0; i < abas.length; i++)
                                  Expanded(
                                    child: _ItemAbaFlutuante(
                                      aba: abas[i],
                                      selecionada: i == indiceAtual,
                                      escala: escala,
                                      folga: folgaDoItem,
                                      aoTocar: () => aoSelecionar(i),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _estiloDoRotulo({required bool selecionada}) => TipografiaTrato.legenda.copyWith(
      fontWeight: selecionada ? FontWeight.w700 : FontWeight.w500,
      fontVariations: selecionada ? const [FontVariation('wght', 700)] : null,
    );

class _ItemAbaFlutuante extends StatelessWidget {
  const _ItemAbaFlutuante({
    required this.aba,
    required this.selecionada,
    required this.escala,
    required this.folga,
    required this.aoTocar,
  });

  final AbaTrato aba;
  final bool selecionada;
  final double escala;
  final double folga;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corAtiva = c.texto;
    final corInativa = c.textoSecundario;
    final base = _estiloDoRotulo(selecionada: selecionada);
    final estilo = base.copyWith(
      color: selecionada ? corAtiva : corInativa,
      fontSize: base.fontSize! * escala,
      letterSpacing: base.letterSpacing == null ? null : base.letterSpacing! * escala,
    );
    final icone = Icon(
      aba.icone,
      size: 22,
      color: selecionada ? corAtiva : corInativa,
    );
    final widgetIcone = aba.badge > 0
        ? Badge.count(
            count: aba.badge,
            maxCount: 99,
            backgroundColor: c.laranja,
            textColor: CoresTrato.petroleo,
            child: icone,
          )
        : icone;

    return Semantics(
      selected: selecionada,
      button: true,
      label: aba.badge > 0 ? '${aba.rotulo}, ${aba.badge} não lidas' : aba.rotulo,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: aoTocar,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: folga,
              vertical: EspacosTrato.x2 - 2,
            ),
            decoration: BoxDecoration(
              color: selecionada ? c.azulSuave : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                widgetIcone,
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(aba.rotulo, style: estilo, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
