import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_fake.dart';

import 'ajuda.dart';

void main() {
  testWidgets('lista a trilha com motivo e hash', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    await irPara(tester, 'auditoria');
    expect(find.text('config.publicada'), findsWidgets);
    expect(find.textContaining('Motivo: Valores do piloto'), findsOneWidget);
    expect(find.textContaining('hash a0001f3'), findsOneWidget);
  });

  testWidgets('filtra por ação', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    await irPara(tester, 'auditoria');
    await tester.enterText(find.widgetWithText(TextField, 'Ação (ex.: disputa.decidida)'), 'disputa');
    await tester.tap(find.text('Filtrar'));
    await tester.pumpAndSettle();
    expect(find.text('disputa.decidida'), findsOneWidget);
    expect(find.text('config.publicada'), findsNothing);
  });

  testWidgets('filtro sem resultado mostra vazio', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    await irPara(tester, 'auditoria');
    await tester.enterText(find.widgetWithText(TextField, 'Quem (id)'), 'ninguem');
    await tester.tap(find.text('Filtrar'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum registro com esse filtro.'), findsOneWidget);
  });

  testWidgets('cadeia íntegra', (tester) async {
    await abrirPainel(tester, papel: 'juridico');
    await irPara(tester, 'auditoria');
    await tester.tap(find.text('Verificar cadeia de hash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cadeia íntegra'), findsOneWidget);
  });

  testWidgets('cadeia quebrada avisa o primeiro registro', (tester) async {
    await abrirPainel(tester, papel: 'seguranca', api: ApiFake(cadeiaQuebradaEm: 2));
    await irPara(tester, 'auditoria');
    await tester.tap(find.text('Verificar cadeia de hash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cadeia quebrada a partir do registro 2'), findsOneWidget);
  });

  testWidgets('ações do painel viram linhas na auditoria', (tester) async {
    await abrirPainel(tester, papel: 'administrador');
    await irPara(tester, 'auditoria');
    expect(find.text('equipe.login'), findsOneWidget);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'seguranca', api: ApiFake(vazio: true));
    await irPara(tester, 'auditoria');
    expect(find.text('Nenhum registro com esse filtro.'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrirPainel(tester, papel: 'seguranca', api: ApiFake(erro: true));
    await irPara(tester, 'auditoria');
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
