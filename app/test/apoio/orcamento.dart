// Preenche o que o orçamento novo exige e não vem escolhido (Termos 5.2).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/componentes.dart';

Finder campoDoOrcamento(String rotulo) => find.descendant(
      of: find.widgetWithText(CampoTrato, rotulo),
      matching: find.byType(TextField),
    );

Future<void> completarOrcamento(
  WidgetTester t, {
  String validade = '3',
  String? naoIncluido = 'Pintura',
}) async {
  Future<void> escrever(String rotulo, String texto) async {
    await t.ensureVisible(campoDoOrcamento(rotulo));
    await t.enterText(campoDoOrcamento(rotulo), texto);
    await t.pump();
  }

  await escrever('Validade do orçamento', validade);
  if (naoIncluido != null) await escrever('O que não está incluído', naoIncluido);
}
