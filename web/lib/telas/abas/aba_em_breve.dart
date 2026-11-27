import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Placeholder honesto: esta função ainda não tem rota no backend (o app mobile também não
/// liga isso à API hoje — ver `app/lib/dados/repositorios_trato.dart`). Melhor mostrar isso
/// claramente do que fingir dado real.
class AbaEmBreve extends StatelessWidget {
  const AbaEmBreve({super.key, required this.titulo, required this.explicacao});

  final String titulo;
  final String explicacao;

  @override
  Widget build(BuildContext context) {
    return ConteudoResponsivo(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: EspacosTrato.x4),
          Text(titulo, style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo)),
          const SizedBox(height: EspacosTrato.x8),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction_rounded, size: 40, color: CoresTrato.textoDica),
                const SizedBox(height: EspacosTrato.x3),
                Text(
                  'Ainda não ligado ao backend',
                  style: TipografiaTrato.titulo.copyWith(color: CoresTrato.petroleo),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  explicacao,
                  textAlign: TextAlign.center,
                  style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
