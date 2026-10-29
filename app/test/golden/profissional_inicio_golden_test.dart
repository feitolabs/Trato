import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/profissional_inicio/casca_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/detalhe_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Telas 23 (início, dentro da casca com a barra) e 24 (detalhe do pedido) do protótipo
/// em celular pequeno, protótipo e tablet. Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'inicio': const CascaProfissionalTela(),
    'detalhe_pedido': const DetalhePedidoTela(),
  };

  for (final MapEntry(key: tela, value: widget) in telas.entries) {
    for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
      testWidgets('$tela — $nome', (tester) async {
        tester.view.physicalSize = tamanho;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            debugShowCheckedModeBanner: false,
            builder: (context, filho) => EscalaFonteLimitada(child: filho!),
            home: widget,
          ),
        );

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('profissional_${tela}_$nome.png'),
        );
      });
    }
  }
}
