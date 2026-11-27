import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/app.dart';
import 'package:trato_admin/telas/shell.dart' show ListaMenu;
import 'apoio/api_fake.dart';

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

/// A lista rolável do menu (lateral ou a da folha "Mais").
Finder rolagemDoMenu() => find.descendant(of: find.byType(ListaMenu), matching: find.byType(Scrollable)).first;

/// No menu "Mais" do celular, rola até a seção (a lista é maior que a tela) e toca nela.
Future<void> tocarNoMais(WidgetTester tester, String id) async {
  final item = find.byKey(ValueKey('menu-$id'));
  final rolagem = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(item, 120, scrollable: rolagem);
  await tester.pumpAndSettle();
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}

Future<void> irPara(WidgetTester tester, String id) async {
  final item = find.byKey(ValueKey('menu-$id'));
  // Menu lateral maior que a janela: rola a própria lista do menu até o item.
  if (find.byType(ListaMenu).evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(item, 120, scrollable: rolagemDoMenu());
    await tester.pumpAndSettle();
  }
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// Preenche o modal de ação sensível e confirma. O botão só habilita com motivo de 10+ caracteres.
Future<void> confirmarMotivo(WidgetTester tester, String botao, {String motivo = 'Motivo de teste válido'}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Motivo'), motivo);
  await tester.pump();
  final modal = find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet);
  await tester.tap(find.descendant(of: modal, matching: find.text(botao)));
  await tester.pumpAndSettle();
}

/// Rola até [alvo] a lista principal da tela (a última ListView; as listas são lazy,
/// então o alvo pode não existir ainda e ensureVisible não basta).
Future<void> rolarListaAte(WidgetTester tester, Finder alvo) async {
  final lista = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(alvo, 300, scrollable: lista);
  await tester.pumpAndSettle();
}
