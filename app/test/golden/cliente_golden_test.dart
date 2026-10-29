import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/cliente/casca_cliente_tela.dart';
import 'package:trato/telas/cliente/dados_exemplo.dart';
import 'package:trato/telas/cliente/perfil_profissional_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Telas 8 (Início), 9 (Buscar) e 10 (Perfil do profissional) do PDF em celular pequeno,
/// protótipo e tablet. Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'inicio': const CascaClienteTela(),
    'buscar': const CascaClienteTela(abaInicial: 1),
    'perfil_profissional': PerfilProfissionalTela(profissional: profissionais.first),
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

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('cliente_${tela}_$nome.png'));
      });
    }
  }
}
