import 'package:flutter/material.dart';

import '../../tema/tema.dart';

/// Campo de texto de várias linhas com rótulo em cima ("Conte como foi", "Descreva").
/// Igual ao CampoTrato, só que cresce em altura.
class CampoLongo extends StatelessWidget {
  const CampoLongo({
    super.key,
    required this.rotulo,
    this.controlador,
    this.dica,
    this.linhas = 4,
    this.aoMudar,
  });

  final String rotulo;
  final TextEditingController? controlador;
  final String? dica;
  final int linhas;
  final ValueChanged<String>? aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x2),
        TextField(
          controller: controlador,
          onChanged: aoMudar,
          minLines: linhas,
          maxLines: linhas + 2,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: TipografiaTrato.corpo,
          decoration: InputDecoration(hintText: dica),
        ),
      ],
    );
  }
}
