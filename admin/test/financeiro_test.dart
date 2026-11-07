import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Future<void> abrirAba(
  WidgetTester tester,
  String aba, {
  String papel = 'financeiro',
  ApiFake? api,
  double largura = 1400,
}) async {
  await abrirPainel(tester, papel: papel, api: api, largura: largura, altura: 900);
  // No celular, Pagamentos fica no "Mais" da barra inferior.
  if (find.byKey(const ValueKey('menu-pagamentos')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('menu-mais')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('menu-pagamentos')).last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(aba).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(aba).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Pagamentos tem as abas do financeiro', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'pagamentos');
    for (final aba in ['Extrato', 'Alertas', 'Contestações', 'Conciliação do dia', 'Avisos do provedor', 'Fechamento do mês']) {
      expect(find.text(aba), findsWidgets, reason: aba);
    }
    expect(find.textContaining('Somente leitura'), findsOneWidget); // o extrato continua sendo a primeira
  });

  testWidgets('alertas mostram pagamento parado e consultar no provedor orienta sem marcar pago', (tester) async {
    await abrirAba(tester, 'Alertas');
    expect(find.text('Pagamentos sem confirmação'), findsOneWidget);
    expect(find.text('Cliente avisou que pagou'), findsOneWidget);
    expect(find.text('Repasses que falharam'), findsOneWidget);
    expect(find.textContaining('Conta encerrada no banco.'), findsOneWidget);
    expect(find.textContaining('1 contestação de cartão em aberto'), findsOneWidget);

    await tester.tap(find.text('Consultar no provedor'));
    await tester.pumpAndSettle();

    expect(find.text('O provedor já recebeu.'), findsOneWidget);
  });

  testWidgets('contestações em aberto vêm primeiro, com prazo e o que fazer', (tester) async {
    await abrirAba(tester, 'Contestações');
    expect(find.text('Mandar provas'), findsOneWidget);
    expect(find.textContaining('faltam 144 h'), findsOneWidget);
    expect(find.text('Perdida'), findsNothing); // fora do filtro "Em aberto"

    await tester.tap(find.textContaining('Todas'));
    await tester.pumpAndSettle();

    expect(find.text('Perdida'), findsOneWidget);
    expect(find.text('Repasse já liberado'), findsOneWidget);
  });

  testWidgets('conciliação do dia mostra só as diferenças e deixa ver tudo', (tester) async {
    await abrirAba(tester, 'Conciliação do dia');
    expect(find.textContaining('Não confere.', findRichText: true), findsOneWidget);
    expect(find.text('Só no provedor'), findsOneWidget);
    expect(find.text('Confere'), findsNothing);
    expect(find.text('R\$ 43,00'), findsOneWidget); // custo do provedor no dia

    await tester.tap(find.text('Ver tudo do dia'));
    await tester.pumpAndSettle();

    expect(find.text('Confere'), findsOneWidget);
  });

  testWidgets('avisos do provedor marcam o que está em revisão', (tester) async {
    await abrirAba(tester, 'Avisos do provedor');
    expect(find.text('Repasse recusado pelo banco'), findsOneWidget);
    expect(find.text('Em revisão'), findsOneWidget);
    expect(find.text('Pagamento confirmado'), findsOneWidget);
  });

  testWidgets('fechar o mês pede motivo, avisa que não desfaz e trava', (tester) async {
    await abrirAba(tester, 'Fechamento do mês');
    expect(find.textContaining('Mês aberto.', findRichText: true), findsOneWidget);
    expect(find.text('Totais de setembro de 2026'), findsOneWidget);
    expect(find.text('R\$ 12.845,00'), findsOneWidget);

    await tester.tap(find.text('Fechar o mês'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não dá para desfazer'), findsOneWidget);
    await confirmarMotivo(tester, 'Fechar o mês');

    expect(find.textContaining('Mês fechado.', findRichText: true), findsOneWidget);
    expect(find.text('Fechar o mês'), findsNothing);
    expect(find.text('Baixar CSV para o contador'), findsOneWidget);
  });

  testWidgets('estado vazio dos alertas', (tester) async {
    await abrirAba(tester, 'Alertas', api: ApiFake(vazio: true));
    expect(find.text('Nada travado no dinheiro.'), findsOneWidget);
  });

  for (final aba in ['Alertas', 'Contestações', 'Conciliação do dia', 'Avisos do provedor', 'Fechamento do mês']) {
    testWidgets('$aba no celular (390 px) não estoura o layout', (tester) async {
      await abrirAba(tester, aba, largura: 390);
      expect(tester.takeException(), isNull);
    });
  }
}
