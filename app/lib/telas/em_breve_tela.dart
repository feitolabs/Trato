import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Destino provisório de fluxos ainda não construídos (login, cadastro...).
/// Sai de cena conforme as tarefas da Fase 5 forem entrando.
class EmBreveTela extends StatelessWidget {
  const EmBreveTela({super.key, required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ConteudoResponsivo(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: TipografiaTrato.tituloGrande),
              const SizedBox(height: EspacosTrato.x2),
              Text('Esta tela chega nas próximas etapas.', style: TipografiaTrato.corpo),
            ],
          ),
        ),
      ),
    );
  }
}
