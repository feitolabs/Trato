import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_fake.dart';

import 'ajuda.dart';

void main() {
  testWidgets('lista a trilha numerada com nome do ator e descrição legível', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    await irPara(tester, 'auditoria');
    expect(find.text('nº 2'), findsOneWidget);
    expect(find.textContaining('Mediador'), findsWidgets);
    expect(find.textContaining('decidiu a disputa de PED-10455 · Pintura de sala'), findsOneWidget);
    expect(find.textContaining('Motivo: “Valores do piloto”'), findsOneWidget);
    // o código técnico não aparece na lista; fica no detalhe expansível
    expect(find.text('config.publicada'), findsNothing);
    await tester.tap(find.text('Ver detalhe técnico').last);
    await tester.pumpAndSettle();
    expect(find.text('config.publicada'), findsOneWidget);
  });

  testWidgets('filtra por ação', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    await irPara(tester, 'auditoria');
    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disputas').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('decidiu a disputa'), findsOneWidget);
    expect(find.textContaining('publicou a versão'), findsNothing);
  });

  testWidgets('filtro por quem sem resultado mostra vazio com orientação', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    await irPara(tester, 'auditoria');
    await tester.enterText(find.widgetWithText(TextField, 'Quem'), 'ninguem');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Nenhum registro com esse filtro'), findsOneWidget);
  });

  testWidgets('cadeia íntegra', (tester) async {
    await abrirPainel(tester, papel: 'juridico');
    await irPara(tester, 'auditoria');
    await tester.tap(find.text('Verificar cadeia de hash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cadeia íntegra.'), findsOneWidget);
  });

  testWidgets('cadeia quebrada avisa o número do registro', (tester) async {
    await abrirPainel(tester, papel: 'seguranca', api: ApiFake(cadeiaQuebradaEm: 2));
    await irPara(tester, 'auditoria');
    await tester.tap(find.text('Verificar cadeia de hash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cadeia de hash quebrada a partir do registro nº 2'), findsOneWidget);
    expect(find.textContaining('Avise a equipe técnica'), findsOneWidget);
  });

  testWidgets('ações do painel viram linhas na auditoria', (tester) async {
    await abrirPainel(tester, papel: 'administrador');
    await irPara(tester, 'auditoria');
    expect(find.textContaining('entrou no painel'), findsOneWidget);
  });

  testWidgets('exportar CSV pede motivo e também é registrado', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    await irPara(tester, 'auditoria');
    await tester.tap(find.text('Exportar CSV'));
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Exportar CSV');
    await tester.pumpAndSettle();
    expect(find.textContaining('exportou a trilha de auditoria'), findsOneWidget);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'seguranca', api: ApiFake(vazio: true));
    await irPara(tester, 'auditoria');
    expect(find.text('Nenhum registro com esse filtro'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrirPainel(tester, papel: 'seguranca', api: ApiFake(erro: true));
    await irPara(tester, 'auditoria');
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
