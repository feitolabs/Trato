import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/comuns/moedas_ganhas_tela.dart';
import 'package:trato/tema/tema.dart';

void main() {
  testWidgets('mostra o bônus no fim da animação e continua ao tocar', (tester) async {
    var continuou = false;
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: MoedasGanhasTela(moedas: 50, aoContinuar: () => continuou = true),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('+50'), findsOneWidget);
    expect(find.text('Tratinhos'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    expect(continuou, isTrue);
  });

  testWidgets('um Tratinho fica no singular', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: MoedasGanhasTela(moedas: 1, aoContinuar: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Tratinho'), findsOneWidget);
  });

  testWidgets('destaca prazo de liberação junto do +50 quando há pendentes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: MoedasGanhasTela(
        moedas: 50,
        pendentes: 50,
        proximaLiberacao: DateTime(2026, 11, 27),
        aoContinuar: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('+50'), findsOneWidget);
    expect(find.text('Tratinhos reservados — liberam em 27/11'), findsOneWidget);
  });
}
