import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/main.dart';
import 'package:trato/telas/auth/criar_conta_tela.dart';
import 'package:trato/telas/auth/login_tela.dart';
import 'package:trato/telas/onboarding/escolha_perfil_tela.dart';
import 'package:trato/telas/onboarding/onboarding_tela.dart';

void main() {
  testWidgets('splash: toque leva ao onboarding', (tester) async {
    await tester.pumpWidget(const TratoApp());

    expect(find.text('FEITO LABS APRESENTA'), findsOneWidget);
    expect(find.text('Toque para começar'), findsOneWidget);
    await tester.tap(find.text('Toque para começar'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingTela), findsOneWidget);
    expect(find.text('1 DE 3'), findsOneWidget);
  });

  group('onboarding', () {
    Future<void> abrir(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingTela()));
    }

    testWidgets('Próximo avança as 3 páginas e na última abre a escolha de perfil', (tester) async {
      await abrir(tester);

      expect(find.text('Descreva o problema,\nreceba orçamentos'), findsOneWidget);
      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();
      expect(find.text('2 DE 3'), findsOneWidget);
      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();
      expect(find.text('3 DE 3'), findsOneWidget);

      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();

      expect(find.byType(EscolhaPerfilTela), findsOneWidget);
    });

    testWidgets('arrastar troca de página', (tester) async {
      await abrir(tester);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('2 DE 3'), findsOneWidget);
    });

    testWidgets('Pular vai direto para a escolha de perfil', (tester) async {
      await abrir(tester);

      await tester.tap(find.text('Pular'));
      await tester.pumpAndSettle();

      expect(find.byType(EscolhaPerfilTela), findsOneWidget);
    });

    testWidgets('Já tenho conta abre o login', (tester) async {
      await abrir(tester);

      await tester.tap(find.text('Já tenho conta'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginTela), findsOneWidget);
    });
  });

  group('escolha de perfil', () {
    testWidgets('começa em cliente e o botão acompanha a escolha', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EscolhaPerfilTela()));

      expect(find.text('Criar conta de cliente'), findsOneWidget);

      await tester.tap(find.text('Quero trabalhar'));
      await tester.pump();

      expect(find.text('Criar conta de profissional'), findsOneWidget);
      expect(find.text('Criar conta de cliente'), findsNothing);
    });

    testWidgets('botão abre o cadastro do perfil escolhido', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EscolhaPerfilTela()));

      await tester.tap(find.text('Quero trabalhar'));
      await tester.pump();
      await tester.tap(find.text('Criar conta de profissional'));
      await tester.pumpAndSettle();

      expect(find.byType(CriarContaTela), findsOneWidget);
    });
  });
}
