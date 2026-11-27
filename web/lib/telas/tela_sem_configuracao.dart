import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Aparece no lugar do site quando o build saiu sem configuração. Evita falha silenciosa.
class TelaSemConfiguracao extends StatelessWidget {
  const TelaSemConfiguracao({super.key, required this.problemas});

  /// Só nomes de variáveis e o motivo, nunca valores.
  final List<String> problemas;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trato',
      debugShowCheckedModeBanner: false,
      theme: TemaTrato.claro,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(EspacosTrato.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 40, color: CoresTrato.vermelhoTexto),
                const SizedBox(height: EspacosTrato.x3),
                Text(
                  'Site sem configuração',
                  textAlign: TextAlign.center,
                  style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo),
                ),
                const SizedBox(height: EspacosTrato.x3),
                for (final problema in problemas)
                  Text(
                    problema,
                    textAlign: TextAlign.center,
                    style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
