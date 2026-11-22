import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'modelos.dart';

/// "Cai na sua conta em dd/mm" com o toque em "Por quê?". A data vem da API; o texto da
/// explicação não cita número de horas ou dias (o prazo é da configuração e pode mudar).
class RegraLiberacao extends StatelessWidget {
  const RegraLiberacao({super.key, required this.libera, this.chave});

  final DateTime? libera;

  /// Chave do texto principal (as telas já usam `regra-liberacao`).
  final Key? chave;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(textoRegraLiberacao(libera), key: chave, style: secundario),
        const SizedBox(width: EspacosTrato.x2),
        BotaoLink(
          key: const Key('regra-liberacao-por-que'),
          texto: 'Por quê?',
          aoTocar: () => showDialog<void>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Por que esse prazo?'),
              content: const Text(textoPorQueLiberacao, key: Key('texto-por-que-liberacao')),
              actions: [
                TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Entendi')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
