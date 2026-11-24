import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Separa o texto de categorias do profissional ("Elétrica, Hidráulica, Pintura") em nomes.
List<String> nomesDeCategorias(String texto) => [
      for (final n in texto.split(','))
        if (n.trim().isNotEmpty) n.trim(),
    ];

/// Para leitor de tela: "Elétrica, Hidráulica, Pintura e mais 4 categorias".
String descricaoDeCategorias(String texto, {int max = 3}) {
  final todos = nomesDeCategorias(texto);
  if (todos.length <= max) return todos.join(', ');
  final resto = todos.length - max;
  return '${todos.take(max).join(', ')} e mais $resto ${resto == 1 ? 'categoria' : 'categorias'}';
}

/// Até [max] categorias em chips e um "+N" com o resto: a lista inteira não toma o cartão.
class ChipsCategorias extends StatelessWidget {
  const ChipsCategorias({super.key, required this.categorias, this.max = 3});

  /// Texto com as categorias separadas por vírgula.
  final String categorias;
  final int max;

  @override
  Widget build(BuildContext context) {
    final todos = nomesDeCategorias(categorias);
    if (todos.isEmpty) return const SizedBox.shrink();
    final c = context.cores;
    final resto = todos.length - max;
    Widget chip(String texto, {Key? key}) => Container(
          key: key,
          padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x2, vertical: 2),
          decoration: BoxDecoration(
            color: c.azulSuave,
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
          ),
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TipografiaTrato.legenda.copyWith(color: c.petroleo),
          ),
        );
    return Semantics(
      label: 'Categorias: ${descricaoDeCategorias(categorias, max: max)}',
      excludeSemantics: true,
      child: Wrap(
        spacing: EspacosTrato.x1,
        runSpacing: EspacosTrato.x1,
        children: [
          for (final n in todos.take(max))
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: chip(n),
            ),
          if (resto > 0)
            chip('+$resto', key: const ValueKey('mais-categorias')),
        ],
      ),
    );
  }
}
