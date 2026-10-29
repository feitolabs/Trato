import 'dart:io';

import 'package:flutter/services.dart';

/// Carrega as fontes reais do app e os ícones Material nos testes
/// (por padrão o Flutter usa uma fonte de blocos e ícones viram quadrados).
Future<void> carregarFontesTrato() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final fontes = [
    ('Archivo', 'assets/fontes/Archivo.ttf'),
    ('Figtree', 'assets/fontes/Figtree.ttf'),
    ('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf'),
  ];
  for (final (familia, caminho) in fontes) {
    final arquivo = File(caminho);
    if (!arquivo.existsSync()) continue;
    final bytes = arquivo.readAsBytesSync();
    final loader = FontLoader(familia)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}
