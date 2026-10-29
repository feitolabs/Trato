import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/auth/confirmar_celular_tela.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/auth/recuperar_senha_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';

/// Telas 4 a 7 do protótipo (login, criar conta, confirmar celular, recuperar senha)
/// em celular pequeno, protótipo e tablet. Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'login': const LoginTela(),
    'criar_conta': const CriarContaTela(),
    'confirmar_celular': const ConfirmarCelularTela(celular: '(31) 98765-4417'),
    'recuperar_senha': const RecuperarSenhaTela(),
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

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('auth_${tela}_$nome.png'));
      });
    }
  }
}
