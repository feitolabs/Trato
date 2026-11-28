import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ajuda.dart';

/// Abre cada tela em larguras de celular, tablet e desktop e falha se algo estourar o layout
/// (RenderFlex overflow, restrição inválida). Cobre RNF de responsividade do painel.
const _secoes = [
  'verificacao',
  'disputas',
  'busca',
  'ausencias',
  'faltas_repetidas',
  'forca_maior',
  'checkout_sem_codigo',
  'incidentes',
  'indisponibilidades',
  'avaliacoes',
  'lgpd',
  'contestacoes',
  'atendimento',
  'medidas',
  'retorno_conta',
  'materiais',
  'compensacoes',
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
        final mais = find.byKey(const ValueKey('menu-mais'));
        if (direto.evaluate().isNotEmpty) {
          await tester.tap(direto.last);
        } else if (mais.evaluate().isNotEmpty) {
          await tester.tap(mais); // celular
          await tester.pumpAndSettle();
          await tocarNoMais(tester, secao);
        } else {
          // Menu lateral maior que a janela: rola até o item.
          await tester.scrollUntilVisible(direto, 120, scrollable: rolagemDoMenu());
          await tester.pumpAndSettle();
          await tester.tap(direto.last);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
