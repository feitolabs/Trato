import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Preenche o endereço obrigatório do pedido presencial (rua, número, bairro e CEP).
Future<void> preencherEnderecoDoPedido(WidgetTester tester) async {
  const campos = {
    'campo-cep': '35500-000',
    'campo-rua': 'Rua das Flores',
    'campo-numero': '10',
    'campo-bairro': 'Centro',
  };
  for (final e in campos.entries) {
    final campo = find.descendant(
      of: find.byKey(ValueKey(e.key)),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(campo);
    await tester.enterText(campo, e.value);
  }
  await tester.pump();
}
