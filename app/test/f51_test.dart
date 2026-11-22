import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';
import 'package:trato/telas/onboarding/ilustracoes_cliente.dart';
import 'package:trato/telas/onboarding/ilustracoes_profissional.dart';
import 'package:trato/telas/onboarding/tour_perfil_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/fontes.dart';

Future<void> _abrir(WidgetTester tester, Widget tela, Size tamanho) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('F51 · ilustrações do tour por perfil', () {
    testWidgets(
        'cliente mostra IlustracaoOnboardingCliente (0..3) sem overflow nem scroll em 320x568',
        (tester) async {
      await _abrir(
        tester,
        TourPerfilTela(perfil: PerfilUso.cliente, aoConcluir: () {}),
        const Size(320, 568),
      );

      for (var i = 0; i < 4; i++) {
        final il = tester.widget<IlustracaoOnboardingCliente>(
          find.byType(IlustracaoOnboardingCliente),
        );
        expect(il.pagina, i);
        expect(find.byType(IlustracaoOnboardingProfissional), findsNothing);
        expect(tester.takeException(), isNull);
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(PaginaTourVisual),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scroll.position.maxScrollExtent, 0.0, reason: 'Página cliente $i gerou scroll');
        if (i < 3) {
          await tester.tap(find.text('Avançar'));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets(
        'profissional mostra IlustracaoOnboardingProfissional (0..3) sem overflow nem scroll em 320x568',
        (tester) async {
      await _abrir(
        tester,
        TourPerfilTela(perfil: PerfilUso.profissional, aoConcluir: () {}),
        const Size(320, 568),
      );

      for (var i = 0; i < 4; i++) {
        final il = tester.widget<IlustracaoOnboardingProfissional>(
          find.byType(IlustracaoOnboardingProfissional),
        );
        expect(il.pagina, i);
        expect(find.byType(IlustracaoOnboardingCliente), findsNothing);
        expect(tester.takeException(), isNull);
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(PaginaTourVisual),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scroll.position.maxScrollExtent, 0.0, reason: 'Página profissional $i gerou scroll');
        if (i < 3) {
          await tester.tap(find.text('Avançar'));
          await tester.pumpAndSettle();
        }
      }
    });
  });
}
