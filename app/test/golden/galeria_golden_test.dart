import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/galeria/galeria_componentes.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Galeria inteira (altura grande para não rolar) em vários tamanhos e com fonte grande.
void main() {
  setUpAll(carregarFontesTrato);

  const casos = {
    'celular': (Size(390, 1900), 1.0),
    'celular_pequeno': (Size(320, 2000), 1.0),
    'celular_pequeno_fonte_grande': (Size(320, 2400), Responsivo.escalaFonteMaxima),
    'tablet': (Size(768, 1900), 1.0),
  };

  for (final MapEntry(key: nome, value: (tamanho, escala)) in casos.entries) {
    testWidgets('galeria — $nome', (tester) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = escala;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          debugShowCheckedModeBanner: false,
          builder: (context, filho) => EscalaFonteLimitada(child: filho!),
          home: const GaleriaComponentes(),
        ),
      );

      await expectLater(find.byType(MaterialApp), matchesGoldenFile('galeria_$nome.png'));
    });
  }
}
