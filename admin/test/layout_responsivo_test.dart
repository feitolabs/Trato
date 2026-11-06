import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ajuda.dart';

/// Abre cada tela em larguras de celular, tablet e desktop e falha se algo estourar o layout
/// (RenderFlex overflow, restrição inválida). Cobre RNF de responsividade do painel.
const _secoes = [
  'verificacao',
  'disputas',
  'busca',
  'risco',
  'pagamentos',
  'relatorios',
  'dashboard',
  'notificacoes',
  'cupons',
  'equipe',
  'config',
  'auditoria',
];

const _larguras = [360.0, 600.0, 820.0, 1100.0, 1440.0];

void main() {
  for (final largura in _larguras) {
    for (final secao in _secoes) {
      testWidgets('$secao em ${largura.toInt()} px não estoura o layout', (tester) async {
        await abrirPainel(tester, largura: largura, altura: 900);
        final direto = find.byKey(ValueKey('menu-$secao'));
        if (direto.evaluate().isEmpty) {
          await tester.tap(find.byKey(const ValueKey('menu-mais')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(ValueKey('menu-$secao')).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
