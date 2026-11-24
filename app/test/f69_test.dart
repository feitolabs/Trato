import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

void main() {
  // A resposta rápida é um item da faixa horizontal; a bolha enviada também mostra o texto.
  final chip = find.descendant(
    of: find.byType(InkWell),
    matching: find.text('Tudo certo!'),
  );

  testWidgets('chat: toque repetido na resposta rápida envia uma vez só enquanto o envio não termina',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final envios = <String>[];
    final pendente = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaTrato.claro,
        home: ChatPedidoTela(
          conversa: const ConversaPedido(
            nome: 'Carlos M.',
            iniciais: 'CM',
            numeroPedido: 'AB12',
            situacao: 'Agendado',
            mensagens: [],
            respostasRapidas: ['Tudo certo!'],
          ),
          aoEnviar: (texto) {
            envios.add(texto);
            return pendente.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(chip.last);
    await tester.pump();
    await tester.tap(chip.last);
    await tester.pump();
    expect(envios, ['Tudo certo!']);

    // Terminado o envio, dá para mandar de novo.
    pendente.complete();
    await tester.pumpAndSettle();
    await tester.tap(chip.last);
    await tester.pump();
    expect(envios, ['Tudo certo!', 'Tudo certo!']);
  });
}
