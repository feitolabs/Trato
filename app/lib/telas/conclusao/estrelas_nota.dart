import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Cinco estrelas tocáveis (0 a 5). Estrela cheia = nota; tocar na nota atual não zera.
class EstrelasNota extends StatelessWidget {
  const EstrelasNota({
    super.key,
    required this.rotulo,
    required this.nota,
    required this.aoMudar,
    this.tamanho = 32,
  });

  /// Critério avaliado; também é o rótulo de acessibilidade.
  final String rotulo;
  final int nota;
  final ValueChanged<int> aoMudar;
  final double tamanho;

  static const total = 5;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= total; i++)
          Semantics(
            button: true,
            selected: i <= nota,
            label: '$rotulo, $i ${i == 1 ? 'estrela' : 'estrelas'}',
            excludeSemantics: true,
            child: InkResponse(
              key: Key('estrela_${rotulo}_$i'),
              onTap: () => aoMudar(i),
              radius: tamanho * 0.7,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  i <= nota ? Icons.star : Icons.star_border,
                  size: tamanho - 4,
                  color: CoresTrato.petroleo,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
