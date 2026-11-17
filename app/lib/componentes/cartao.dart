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
      padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
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
      child:
          aoTocar == null
          ? conteudo
          : MergeSemantics(
              child: InkWell(onTap: aoTocar, borderRadius: raio, child: conteudo),
            ),
    );
  }
}

/// Linha "rótulo à esquerda, valor alinhado à direita" usada em cartões de detalhes.
class LinhaDetalheCartao extends StatelessWidget {
  const LinhaDetalheCartao({
    super.key,
    required this.rotulo,
    required this.valor,
    this.estiloRotulo,
    this.estiloValor,
  });

  final String rotulo;
  final String valor;
  final TextStyle? estiloRotulo;
  final TextStyle? estiloValor;

  @override
  Widget build(BuildContext context) {
    final estiloR = estiloRotulo ??
        TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario);
    final estiloV = estiloValor ?? TipografiaTrato.corpoForte;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: Text(rotulo, style: estiloR)),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                flex: 3,
                child: Text(valor, textAlign: TextAlign.end, style: estiloV),
              ),
            ],
          );
        }
        final larguraDisponivel =
            (constraints.maxWidth - EspacosTrato.x3).clamp(0.0, double.infinity);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(rotulo, style: estiloR)),
            const SizedBox(width: EspacosTrato.x3),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: larguraDisponivel * 0.6),
              child: Text(valor, textAlign: TextAlign.end, style: estiloV),
            ),
          ],
        );
      },
    );
  }
}
