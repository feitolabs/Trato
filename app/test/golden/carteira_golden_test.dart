import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/carteira/carteira_tela.dart';
import 'package:trato/telas/carteira/dados_exemplo.dart';
import 'package:trato/telas/carteira/modelos.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Tela 27 (Carteira) em celular pequeno, protótipo e tablet; estados completo, vazio e erro.
/// Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 1100),
    'tablet': Size(768, 1024),
  };
  const variantes = <String, DadosCarteira>{
    'completo': DadosExemploCarteira.completo,
    'vazio': DadosExemploCarteira.vazio,
    'erro': DadosExemploCarteira.comErro,
  };

  for (final MapEntry(key: variante, value: dados) in variantes.entries) {
    for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
      testWidgets('carteira $variante — $nome', (tester) async {
        tester.view.physicalSize = tamanho;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            debugShowCheckedModeBanner: false,
            builder: (context, filho) => EscalaFonteLimitada(child: filho!),
            home:
                CarteiraTela(dados: dados, aoSacarPix: () {}, aoVerTudo: () {}),
          ),
        );
        await tester.pump();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('carteira_${variante}_$nome.png'),
        );
      });
    }
  }
}
