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

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final midia = MediaQuery.of(context);

    return MediaQuery(
      data: midia.copyWith(textScaler: midia.textScaler.clamp(maxScaleFactor: 1)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            EspacosTrato.x4,
            EspacosTrato.x1,
            EspacosTrato.x4,
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
                      color: (escuro ? Colors.black : c.petroleo).withValues(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: EspacosTrato.x2,
                          vertical: EspacosTrato.x2 - 2,
                        ),
                        child: Row(
                          children: [
                            for (var i = 0; i < abas.length; i++)
                              Expanded(
                                child: _ItemAbaFlutuante(
                                  aba: abas[i],
                                  selecionada: i == indiceAtual,
                                  aoTocar: () => aoSelecionar(i),
                                ),
                              ),
                          ],
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

class _ItemAbaFlutuante extends StatelessWidget {
  const _ItemAbaFlutuante({
    required this.aba,
    required this.selecionada,
    required this.aoTocar,
  });

  final AbaTrato aba;
  final bool selecionada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corAtiva = c.texto;
    final corInativa = c.textoSecundario;
    final estilo = TipografiaTrato.legenda.copyWith(
      color: selecionada ? corAtiva : corInativa,
      fontWeight: selecionada ? FontWeight.w700 : FontWeight.w500,
      fontVariations: selecionada ? const [FontVariation('wght', 700)] : null,
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
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x1,
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
