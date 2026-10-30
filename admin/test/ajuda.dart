import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/app.dart';
import 'package:trato_admin/dados/api_fake.dart';

/// Abre o painel numa janela [largura] x [altura] e entra com o papel [papel].
Future<void> abrirPainel(
  WidgetTester tester, {
  String papel = 'administrador',
  ApiFake? api,
  double largura = 1400,
  double altura = 1000,
  String? secao,
}) async {
  tester.view.physicalSize = Size(largura, altura);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(PainelApp(api: api ?? ApiFake()));
  await entrar(tester, papel);
  if (secao != null) await irPara(tester, secao);
}

Future<void> abrirPainelSemEntrar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(PainelApp(api: ApiFake()));
}

Future<void> entrar(WidgetTester tester, String papel, {bool esperar = true}) async {
  await tester.enterText(find.widgetWithText(TextField, 'E-mail da equipe'), '$papel@teste.local');
  await tester.enterText(find.widgetWithText(TextField, 'Senha'), 'senha-de-teste');
  await tester.tap(find.text('Entrar'));
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> irPara(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('menu-$id')));
  await tester.pumpAndSettle();
}

/// Preenche o diálogo de motivo e confirma.
Future<void> confirmarMotivo(WidgetTester tester, String botao, {String motivo = 'Motivo de teste válido'}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Motivo (obrigatório)'), motivo);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, botao));
  await tester.pumpAndSettle();
}

/// Rola até [alvo] a lista principal da tela (a última ListView; as listas são lazy,
/// então o alvo pode não existir ainda e ensureVisible não basta).
Future<void> rolarListaAte(WidgetTester tester, Finder alvo) async {
  final lista = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(alvo, 300, scrollable: lista);
  await tester.pumpAndSettle();
}
