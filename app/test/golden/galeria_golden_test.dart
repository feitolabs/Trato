import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/galeria/galeria_componentes.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Galeria inteira (rolagem desligada pela altura) em celular e celular pequeno.
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {'celular': Size(390, 1900), 'celular_pequeno': Size(320, 2000)};

  for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
    testWidgets('galeria — $nome', (tester) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: TemaTrato.claro,
          debugShowCheckedModeBanner: false,
          home: const GaleriaComponentes(),
        ),
      );

      await expectLater(find.byType(MaterialApp), matchesGoldenFile('galeria_$nome.png'));
    });
  }
}
