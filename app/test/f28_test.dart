import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

Future<void> _menu(WidgetTester tester, {required bool jaAvaliou}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => RotasTrato.acoesPedidoProfissionalParaTeste(
              context,
              estadoApi: 'concluido',
              jaAvaliou: jaAvaliou,
            ),
            child: const Text('menu'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('menu'));
  await tester.pumpAndSettle();
}

void main() {
  group('ja_avaliou (profissional)', () {
    testWidgets('menu: concluído e não avaliado oferece Avaliar cliente', (tester) async {
      await _menu(tester, jaAvaliou: false);
      expect(find.text('Avaliar cliente'), findsOneWidget);
    });

    testWidgets('menu: já avaliado só mostra os valores', (tester) async {
      await _menu(tester, jaAvaliou: true);
      expect(find.text('Avaliar cliente'), findsNothing);
      expect(find.text('Ver valores do pedido'), findsOneWidget);
    });

    test('card: sem "Avaliar cliente" quando já avaliou', () {
      expect(oQueFazerAgora('concluido'), 'Avaliar cliente');
      expect(oQueFazerAgora('concluido', jaAvaliou: true), isNull);
    });
  });

  test('categoria_nome vira o título do pedido; sem o campo, fica o título de antes', () {
    Map<String, dynamic> json({String? categoria}) => {
          'id': 'abcd1234',
          'estado': 'agendado',
          'estado_nome': 'Agendado',
          'cliente_id': 'c1',
          'aberto_em': '2026-11-20T10:00:00Z',
          'acoes_permitidas': <String>[],
          'titulo': 'Orçamento geral',
          if (categoria != null) 'categoria_nome': categoria,
        };
    expect(PedidoApi.deJson(json(categoria: 'Eletricista')).rotulo, 'Eletricista');
    expect(PedidoApi.deJson(json()).rotulo, 'Orçamento geral');
  });
}
