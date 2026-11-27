import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import 'textos_dos_termos.dart';

/// Termos 6.1, junto dos preços mostrados ao cliente.
class NotaPrecoComTributos extends StatelessWidget {
  const NotaPrecoComTributos({super.key});

  @override
  Widget build(BuildContext context) => Text(
        textoPrecoComTributos,
        key: const Key('nota-tributos'),
        style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
      );
}
