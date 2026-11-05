import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/agenda/agenda_tela.dart';
import 'package:trato/telas/agenda/modelos.dart';
import 'package:trato/tema/tema.dart';

// A Agenda precisa recarregar quando algo muda (visita marcada, check-in feito).
// Antes ela mostrava o dado da primeira carga até o app ser reaberto.

void main() {
  testWidgets('quando o aviso dispara, a Agenda busca de novo e troca o que está na tela',
      (tester) async {
    final aviso = ValueNotifier<int>(0);
    addTearDown(aviso.dispose);
    var chamadas = 0;
    final hoje = DateTime(2026, 11, 5);

    Future<List<Agendamento>> carregar() async {
      chamadas++;
      return [
        Agendamento(
          id: 'a1',
          pedidoId: 'p1',
          dia: chamadas == 1 ? hoje : hoje.add(const Duration(days: 1)),
          horario: chamadas == 1 ? 'Data da visita ainda não marcada' : '06/11 · 09:00 às 11:00',
          titulo: 'Pedido #9F38',
          local: '',
        ),
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: TemaTrato.claro,
        home: AgendaTela(carregar: carregar, atualizarQuando: aviso, hoje: hoje),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Data da visita ainda não marcada'), findsOneWidget);
    expect(find.text('HOJE'), findsOneWidget);

    aviso.value++;
    await tester.pumpAndSettle();
    expect(chamadas, 2);
    expect(find.text('06/11 · 09:00 às 11:00'), findsOneWidget);
    expect(find.text('AMANHÃ'), findsOneWidget);
    expect(find.text('Data da visita ainda não marcada'), findsNothing);
  });
}
