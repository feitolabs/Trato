import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/app.dart';
import 'package:trato_admin/dados/api_fake.dart';

import 'ajuda.dart';

void main() {
  testWidgets('lista a fila e mostra o detalhe com CPF e arquivos mascarados', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    expect(find.text('Carlos Pereira'), findsWidgets);
    expect(find.text('***.***.***-45'), findsOneWidget);
    expect(find.text('Escondido'), findsNWidgets(3));
  });

  testWidgets('revelar documento exige motivo e avisa da auditoria', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    await tester.tap(find.text('Revelar').first);
    await tester.pumpAndSettle();
    expect(find.text('Será registrado na auditoria.'), findsWidgets);
    await confirmarMotivo(tester, 'Revelar', motivo: 'curto');
    expect(find.text('Explique o motivo.'), findsOneWidget);
    await confirmarMotivo(tester, 'Revelar');
    expect(find.text('Aberto nesta sessão'), findsOneWidget);
  });

  testWidgets('recusar pede motivo e atualiza o status', (tester) async {
    await abrirPainel(tester, papel: 'cadastro');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Recusar'));
    await tester.pumpAndSettle();
    await confirmarMotivo(tester, 'Recusar');
    expect(find.text('Recusada'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Recusar'), findsNothing);
  });

  testWidgets('segurança vê a fila mas não aprova nem abre documentos', (tester) async {
    await abrirPainel(tester, papel: 'seguranca');
    expect(find.text('Carlos Pereira'), findsWidgets);
    expect(find.text('Aprovar'), findsNothing);
    expect(find.text('Revelar'), findsNothing);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'cadastro', api: ApiFake(vazio: true));
    expect(find.text('Nenhum cadastro esperando análise.'), findsOneWidget);
  });

  testWidgets('estado de erro com tentar de novo', (tester) async {
    await abrirPainel(tester, papel: 'cadastro', api: ApiFake(erro: true));
    expect(find.text('Não foi possível falar com o servidor.'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('estado carregando', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(PainelApp(api: ApiFake(atraso: const Duration(seconds: 1))));
    await entrar(tester, 'cadastro', esperar: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Carlos Pereira'), findsWidgets);
  });
}
