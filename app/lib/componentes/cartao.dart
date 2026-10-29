import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Cartão claro com borda. Com [aoTocar], mostra a seta ">" à direita
/// (como os pedidos em "Seus pedidos").
class CartaoTrato extends StatelessWidget {
  const CartaoTrato({super.key, required this.child, this.aoTocar, this.escuro = false});

  final Widget child;
  final VoidCallback? aoTocar;

  /// Variante petróleo (ex.: "Descreva o problema", resumo da calculadora).
  final bool escuro;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raioGrande);
    final conteudo = Padding(
      padding: const EdgeInsets.all(EspacosTrato.x5),
      child: aoTocar == null
          ? child
          : Row(
              children: [
                Expanded(child: child),
                const SizedBox(width: EspacosTrato.x3),
                const Icon(Icons.chevron_right, color: CoresTrato.petroleo),
              ],
            ),
    );

    return Card(
      color: escuro ? CoresTrato.petroleo : null,
      shape: escuro ? RoundedRectangleBorder(borderRadius: raio) : null,
      clipBehavior: Clip.antiAlias,
      child: aoTocar == null
          ? conteudo
          : InkWell(onTap: aoTocar, borderRadius: raio, child: conteudo),
    );
  }
}
