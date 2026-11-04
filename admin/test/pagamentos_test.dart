import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'apoio/api_fake.dart';

import 'ajuda.dart';

void main() {
  testWidgets('mostra extrato espelho, cards e aviso de somente leitura', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'pagamentos');
    expect(find.textContaining('Somente leitura'), findsOneWidget);
    for (final card in ['Confirmado', 'Reembolsado', 'Em andamento', 'Divergências']) {
      expect(find.text(card), findsWidgets, reason: card);
    }
    expect(find.text('R\$ 12.845,00'), findsOneWidget);
    expect(find.text('412 cobranças'), findsOneWidget);
    // colunas do extrato (RF-PAG-03 e RF-PAG-05)
    for (final coluna in ['Data', 'Tipo', 'Pedido', 'ID no provedor', 'Status', 'Valor', 'Taxa Trato', 'Líquido profissional']) {
      expect(find.text(coluna), findsWidgets, reason: coluna);
    }
    expect(find.text('PED-10490'), findsOneWidget);
    expect(find.text('-R\$ 120,00'), findsOneWidget);
  });

  testWidgets('divergência só é conciliada com motivo registrado', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'pagamentos');
    await tester.tap(find.text('Conciliar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nenhum valor é movimentado'), findsOneWidget);
    await confirmarMotivo(tester, 'Conciliar');
    expect(find.text('Conciliar'), findsNothing);
    expect(find.text('Divergência conciliada.'), findsOneWidget);
  });

  testWidgets('não há botão que mexa em dinheiro (D15)', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', secao: 'pagamentos');
    for (final proibido in ['Sacar', 'Saque', 'Transferir', 'Repassar', 'Saldo', 'Criar cobrança']) {
      expect(find.textContaining(proibido), findsNothing, reason: proibido);
    }
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', api: ApiFake(vazio: true), secao: 'pagamentos');
    expect(find.text('Nenhum lançamento no extrato.'), findsOneWidget);
  });

  testWidgets('estado de erro', (tester) async {
    await abrirPainel(tester, papel: 'financeiro', api: ApiFake(erro: true), secao: 'pagamentos');
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
