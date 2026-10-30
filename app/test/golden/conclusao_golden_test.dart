import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/conclusao/avaliacao_tela.dart';
import 'package:trato/telas/conclusao/conclusao_tela.dart';
import 'package:trato/telas/conclusao/dados_exemplo.dart';
import 'package:trato/telas/conclusao/garantia_tela.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Telas 18 a 21 do protótipo em celular pequeno, protótipo e tablet.
/// Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'conclusao': const ConclusaoTela(),
    'avaliacao': const AvaliacaoTela(notasIniciais: [5, 5, 4, 5, 0]),
    'relatar_problema': const RelatarProblemaTela(
      motivoInicial: 'O problema voltou ou não foi resolvido',
      descricaoInicial: 'A pia voltou a vazar dois dias depois do conserto.',
    ),
    'garantia': GarantiaTela(dados: dadosGarantiaExemplo),
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
          matchesGoldenFile('conclusao_${tela}_$nome.png'),
        );
      });
    }
  }
}
