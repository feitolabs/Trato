import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/onboarding/ilustracoes_profissional.dart';
import 'package:trato/tema/tema.dart';

void main() {
  group('F50b · IlustracaoOnboardingProfissional', () {
    for (var pagina = 0; pagina < 4; pagina++) {
      testWidgets('renderiza pagina $pagina sem erro, em quadrado e com Semantics', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            home: Scaffold(
              body: Center(
                child: IlustracaoOnboardingProfissional(pagina: pagina),
              ),
            ),
          ),
        );

        final ilustracao = find.byType(IlustracaoOnboardingProfissional);
        expect(ilustracao, findsOneWidget);
        expect(tester.getSize(ilustracao), const Size.square(220));
        expect(
          find.descendant(of: ilustracao, matching: find.byType(CustomPaint)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: ilustracao, matching: find.byType(Text)),
          findsNothing,
        );
        final semantics = tester.widget<Semantics>(
          find.descendant(of: ilustracao, matching: find.byType(Semantics)),
        );
        expect(semantics.properties.label, startsWith('Ilustração:'));
      });
    }

    testWidgets('respeita tamanho customizado', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: IlustracaoOnboardingProfissional(pagina: 2, tamanho: 160),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(IlustracaoOnboardingProfissional)),
        const Size.square(160),
      );
    });

    for (final invalida in [-1, 4, 99]) {
      testWidgets('pagina fora do intervalo ($invalida) retorna SizedBox.shrink sem quebrar',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            home: Scaffold(
              body: Center(
                child: IlustracaoOnboardingProfissional(pagina: invalida),
              ),
            ),
          ),
        );

        final ilustracao = find.byType(IlustracaoOnboardingProfissional);
        expect(ilustracao, findsOneWidget);
        expect(tester.getSize(ilustracao), Size.zero);
        expect(
          find.descendant(of: ilustracao, matching: find.byType(CustomPaint)),
          findsNothing,
        );
      });
    }
  });
}
