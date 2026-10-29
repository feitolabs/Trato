import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/main.dart';

/// Compara a splash com a imagem de referência em 3 tamanhos (celular pequeno,
/// celular padrão do protótipo e tablet). Atualizar: flutter test --update-goldens
Future<void> _carregarFonte(String familia, String arquivo) async {
  final bytes = File('assets/fontes/$arquivo').readAsBytesSync();
  final loader = FontLoader(familia)..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _carregarFonte('Archivo', 'Archivo.ttf');
    await _carregarFonte('Figtree', 'Figtree.ttf');
  });

  const tamanhos = {
    'celular_pequeno': Size(320, 568),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };

  for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
    testWidgets('splash — $nome', (tester) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const TratoApp());

      await expectLater(find.byType(TratoApp), matchesGoldenFile('splash_$nome.png'));
    });
  }
}
