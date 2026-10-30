import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/tema/tema.dart';

void main() {
  test('cores principais batem com o protótipo', () {
    expect(CoresTrato.petroleo, const Color(0xFF0E3A43));
    expect(CoresTrato.creme, const Color(0xFFF4EEE2));
    expect(CoresTrato.superficie, const Color(0xFFFBF8F1));
    expect(CoresTrato.laranja, const Color(0xFFFF8A4C));
  });

  test('tema usa fundo creme e botão primário petróleo', () {
    final tema = TemaTrato.claro;

    expect(tema.scaffoldBackgroundColor, CoresTrato.creme);
    expect(tema.colorScheme.primary, CoresTrato.petroleo);
    final fundoBotao = tema.filledButtonTheme.style!.backgroundColor!.resolve({});
    expect(fundoBotao, CoresTrato.petroleo);
  });

  test('títulos em Archivo e corpo em Figtree', () {
    expect(TipografiaTrato.tituloGrande.fontFamily, 'Archivo');
    expect(TipografiaTrato.tituloGrande.fontWeight, FontWeight.w800);
    expect(TipografiaTrato.corpo.fontFamily, 'Figtree');
  });

  testWidgets('splash usa fundo petróleo', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: const SizedBox()));
    final contexto = tester.element(find.byType(SizedBox));

    expect(Theme.of(contexto).colorScheme.primary, CoresTrato.petroleo);
  });
}
