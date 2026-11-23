import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';

import 'apoio/exemplos/auth/servico_auth_fake.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> abrir(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: tela));
    await tester.pumpAndSettle();
  }

  for (final caso in <(String, Widget Function(ServicoAuthFake))>[
    ('EscolhaPerfilTela', (s) => EscolhaPerfilTela(servico: s)),
    ('CriarContaTela', (s) => CriarContaTela(servico: s)),
  ]) {
    testWidgets(
        '${caso.$1}: "Já tem conta? Entrar" abre LoginTela em 320x568 sem overflow',
        (tester) async {
      final servico = ServicoAuthFake();
      await abrir(tester, caso.$2(servico));

      expect(find.text('Já tem conta? '), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Entrar'));
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      final login = tester.widget<LoginTela>(find.byType(LoginTela));
      expect(login.servico, same(servico));
    });
  }
}
