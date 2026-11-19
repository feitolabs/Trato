import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/telas/pagamento/dados_exemplo.dart' as expag;

void main() {
  testWidgets('interruptor de moedas mostra o desconto que o backend calculou', (tester) async {
    final repo = RepositorioPagamentoFake();
    final inicial = expag.DadosExemplo.pagamento.copiarCom(moedasSaldo: 5000);
    final pedidos = <bool>[];
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PagamentoTela(
        dados: inicial,
        aoAlternarMoedas: (usar, cupom) {
          pedidos.add(usar);
          return repo.recalcular('p1', cupom: cupom, usarMoedas: usar);
        },
      ),
    ));
    expect(find.text('Você tem 5000 moedas do Trato'), findsOneWidget);
    await tester.tap(find.byKey(const Key('interruptor-moedas')));
    await tester.pumpAndSettle();
    expect(pedidos, [true]);
    expect(find.textContaining('Usando 5000 moedas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('interruptor-moedas')));
    await tester.pumpAndSettle();
    expect(pedidos, [true, false]);
    expect(find.text('Você tem 5000 moedas do Trato'), findsOneWidget);
  });

  testWidgets('sem saldo de moedas o cartão nem aparece', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PagamentoTela(
        dados: expag.DadosExemplo.pagamento,
        aoAlternarMoedas: (usar, cupom) async => expag.DadosExemplo.pagamento,
      ),
    ));
    expect(find.byKey(const Key('interruptor-moedas')), findsNothing);
  });
}
