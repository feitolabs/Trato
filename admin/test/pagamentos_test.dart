import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_fake.dart';

import 'ajuda.dart';

void main() {
  testWidgets('mostra extrato espelho, resumo e aviso de somente leitura', (tester) async {
    await abrirPainel(tester, papel: 'financeiro');
    expect(find.textContaining('Somente leitura'), findsOneWidget);
    expect(find.text('Confirmado pelo provedor'), findsWidgets);
    expect(find.text('Aguardando confirmação'), findsWidgets);
    expect(find.text('Divergente'), findsOneWidget);
    expect(find.text('R\$ 12.845,00'), findsOneWidget);
    expect(find.text('-R\$ 120,00'), findsOneWidget);
  });

  testWidgets('não há botão que mexa em dinheiro (D15)', (tester) async {
    await abrirPainel(tester, papel: 'financeiro');
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNWidgets(1)); // só "Sair"
    for (final proibido in ['Sacar', 'Saque', 'Transferir', 'Repassar', 'Saldo']) {
      expect(find.textContaining(proibido), findsNothing, reason: proibido);
    }
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', api: ApiFake(vazio: true));
    expect(find.text('Nenhum lançamento no extrato.'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', api: ApiFake(erro: true));
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
