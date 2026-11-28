// APP-LOTE-A: Termos 6.4, diferença do parcelado para o à vista com os valores do servidor.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';

import 'apoio/fontes.dart';

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('6.4: cada parcelamento mostra total e diferença; sem taxa de juros', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: PagamentoTela(
        dados: const DadosPagamento(
          subtitulo: 'Pedido de exemplo',
          valorAgoraCentavos: 10000,
          opcoes: [
            OpcaoPagamento(metodo: MetodoPagamento.cartao, titulo: 'Cartão', descricao: 'Crédito'),
          ],
          parcelamento: [
            // Diferença propositalmente diferente de total - à vista: o app não recalcula.
            OpcaoParcelamento(
                parcelas: 2, custoCentavos: 301, totalCentavos: 10300, valorParcelaCentavos: 5150),
            OpcaoParcelamento(
                parcelas: 3, custoCentavos: 0, totalCentavos: 10000, valorParcelaCentavos: 3333),
          ],
        ),
        aoPagarDetalhado: (_, __, ___) async {},
      ),
    ));
    await t.pumpAndSettle();
    final cartao = find.text('Cartão');
    await t.scrollUntilVisible(cartao, 150, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(cartao);
    await t.pumpAndSettle();
    await t.tap(cartao);
    await t.pumpAndSettle();

    for (final texto in [
      'a mais que à vista (custo do parcelamento).',
      'Sem diferença em relação ao à vista.',
    ]) {
      await t.scrollUntilVisible(find.textContaining(texto), 100,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining(texto), findsOneWidget);
    }
    expect(textoDiferencaDoAVista(301), contains('3,01'));
    expect(find.textContaining('juros', skipOffstage: false), findsNothing);
    expect(t.takeException(), isNull);
  });
}
