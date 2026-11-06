import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/app.dart';
import 'apoio/api_fake.dart';
import 'package:trato_admin/nucleo/papeis.dart';

import 'ajuda.dart';

bool _tem(String id) => find.byKey(ValueKey('menu-$id')).evaluate().isNotEmpty;

void main() {
  group('login', () {
    testWidgets('campos vazios mostram aviso', (tester) async {
      await abrirPainelSemEntrar(tester);
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      expect(find.text('Preencha e-mail e senha.'), findsOneWidget);
    });

    testWidgets('senha curta é recusada', (tester) async {
      await abrirPainelSemEntrar(tester);
      await tester.enterText(find.widgetWithText(TextField, 'E-mail da equipe'), 'financeiro@teste.local');
      await tester.enterText(find.widgetWithText(TextField, 'Senha'), 'curta');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
    });

    testWidgets('conta sem papel na equipe não entra', (tester) async {
      await abrirPainel(tester, papel: 'cliente');
      expect(find.text('Esta conta não tem papel na equipe.'), findsOneWidget);
      expect(find.text('PAINEL ADMIN'), findsOneWidget);
    });

    testWidgets('entra, mostra o papel e sai', (tester) async {
      await abrirPainel(tester, papel: 'financeiro');
      expect(find.text('Financeiro'), findsWidgets);
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(find.text('PAINEL ADMIN'), findsOneWidget);
    });
  });

  group('controle por papel', () {
    Future<void> confere(
      WidgetTester tester,
      String papel,
      Set<String> visiveis,
    ) async {
      await abrirPainel(tester, papel: papel);
      const todos = ['verificacao', 'disputas', 'pagamentos', 'busca', 'config', 'auditoria'];
      for (final id in todos) {
        expect(_tem(id), visiveis.contains(id), reason: '$papel / $id');
      }
    }

    testWidgets('cadastro', (t) => confere(t, 'cadastro', {'verificacao', 'busca'}));
    testWidgets('mediador', (t) => confere(t, 'mediador', {'disputas', 'busca'}));
    testWidgets('financeiro', (t) => confere(t, 'financeiro', {'pagamentos', 'busca', 'config'}));
    testWidgets('juridico', (t) => confere(t, 'juridico', {'config', 'auditoria'}));
    testWidgets('atendente_n1', (t) => confere(t, 'atendente_n1', {'busca'}));
    testWidgets(
      'administrador',
      (t) => confere(t, 'administrador', {'verificacao', 'disputas', 'pagamentos', 'busca', 'config', 'auditoria'}),
    );

    test('matriz: só admin aprova configuração e só quem decide disputa tem a permissão', () {
      final aprovam = Papel.values.where((p) => p.pode(Permissao.configAprovar));
      expect(aprovam, [Papel.administrador]);
      final decidem = Papel.values.where((p) => p.pode(Permissao.disputasDecidir)).toSet();
      expect(decidem, {Papel.mediador, Papel.liderSuporte, Papel.administrador});
      expect(Papel.doCodigo('lider_suporte'), Papel.liderSuporte);
      expect(Papel.doCodigo('inexistente'), isNull);
    });

    test('nenhum papel tem permissão de saque ou saldo: pagamentos só leitura', () {
      expect(Permissao.values.map((p) => p.name).where((n) => n.contains('saque') || n.contains('saldo')), isEmpty);
    });

    testWidgets('a partir de 1024 o menu lateral é fixo, agrupado e com rodapé', (tester) async {
      await abrirPainel(tester, papel: 'administrador', largura: 1280, altura: 900);
      for (final grupo in ['OPERAÇÃO', 'FINANCEIRO', 'CRESCIMENTO', 'ADMINISTRAÇÃO']) {
        expect(find.text(grupo), findsOneWidget, reason: grupo);
      }
      expect(find.text('Risco e antifraude'), findsOneWidget);
      expect(find.text('Notificações push'), findsOneWidget);
      expect(find.text('Sair'), findsOneWidget);
      expect(find.text('Administrador'), findsWidgets); // papel no rodapé
    });

    testWidgets('de 768 a 1023 o menu fica recolhido, só com ícones', (tester) async {
      await abrirPainel(tester, papel: 'administrador', largura: 900, altura: 900);
      expect(_tem('disputas'), isTrue);
      expect(find.text('OPERAÇÃO'), findsNothing);
      await irPara(tester, 'disputas');
      expect(find.text('Disputas'), findsWidgets);
    });

    testWidgets('abaixo de 768 vira barra inferior com cinco módulos e "Mais"', (tester) async {
      await abrirPainel(tester, papel: 'administrador', largura: 400, altura: 900);
      for (final id in ['verificacao', 'disputas', 'busca', 'risco', 'dashboard', 'mais']) {
        expect(_tem(id), isTrue, reason: id);
      }
      expect(_tem('equipe'), isFalse);
      await tester.tap(find.byKey(const ValueKey('menu-mais')));
      await tester.pumpAndSettle();
      expect(_tem('equipe'), isTrue);
      expect(find.text('Sair'), findsOneWidget);
    });

    testWidgets('ambiente de teste mostra a faixa fixa', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(PainelApp(api: ApiFake(), ambienteTeste: true));
      await entrar(tester, 'administrador');
      expect(find.textContaining('AMBIENTE DE TESTE'), findsOneWidget);
    });
  });
}
