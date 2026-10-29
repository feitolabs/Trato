import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(find.text('Painel da equipe'), findsOneWidget);
    });

    testWidgets('entra, mostra o papel e sai', (tester) async {
      await abrirPainel(tester, papel: 'financeiro');
      expect(find.text('Financeiro'), findsWidgets);
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(find.text('Painel da equipe'), findsOneWidget);
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

    testWidgets('no tablet o menu vira gaveta', (tester) async {
      await abrirPainel(tester, papel: 'administrador', largura: 800, altura: 900);
      expect(_tem('disputas'), isFalse);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(_tem('disputas'), isTrue);
      await irPara(tester, 'disputas');
      expect(find.text('Disputas'), findsWidgets);
    });
  });
}
