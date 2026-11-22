import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Pontinhos de página. A página atual vira uma pílula (onboarding) ou um ponto claro (splash).
class IndicadorPaginas extends StatelessWidget {
  const IndicadorPaginas({
    super.key,
    required this.total,
    required this.atual,
    this.corAtiva,
    this.corInativa,
    this.pilula = true,
  });

  final int total;
  final int atual;
  final Color? corAtiva;
  final Color? corInativa;

  /// `true`: a página atual fica alongada (28x10). `false`: todos os pontos são iguais (10x10).
  final bool pilula;

  static const _altura = 12.0;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final ativa = corAtiva ?? c.petroleo;
    final inativa = corInativa ?? c.textoSecundario;
    return Semantics(
      label: 'Página ${atual + 1} de $total',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Padding(
              padding: EdgeInsets.only(right: i == total - 1 ? 0 : EspacosTrato.x3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: pilula && i == atual ? 32 : _altura,
                height: _altura,
                decoration: BoxDecoration(
                  color: i == atual ? ativa : inativa,
                  borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
