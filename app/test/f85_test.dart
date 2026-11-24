import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/indicacoes/indique_e_ganhe_tela.dart';
import 'package:trato/telas/indicacoes/servico_fake.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/fontes.dart';

void main() {
  setUpAll(carregarFontesTrato);

  for (final (tamanho, teclado) in [
    (const Size(411, 914), 345.0),
    (const Size(360, 640), 300.0),
    (const Size(320, 568), 260.0),
  ]) {
    for (final fonte in [1.0, 1.3]) {
      testWidgets(
          'teclado aberto em ${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte: '
          '"Validar código" e o campo ficam visíveis', (t) async {
        t.view.physicalSize = tamanho;
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = fonte;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(MaterialApp(
          theme: TemaTrato.claro,
          builder: (c, filho) => EscalaFonteLimitada(child: filho!),
          home: IndiqueEGanheTela(servico: ServicoIndicacoesFake()),
        ));
        await t.pumpAndSettle();
        final campo = find.byKey(const ValueKey('campo-codigo-indicacao'));
        await t.ensureVisible(campo);
        await t.pumpAndSettle();
        await t.tap(campo);
        await t.pump();
        // O teclado sobe depois do foco, como no aparelho.
        t.view.viewInsets = FakeViewPadding(bottom: teclado);
        await t.pumpAndSettle();
        await t.enterText(campo, '4FCZR35T');
        await t.pumpAndSettle();

        final limite = tamanho.height - teclado;
        final botao = t.getRect(find.byKey(const ValueKey('validar-codigo')));
        expect(botao.bottom, lessThanOrEqualTo(limite), reason: 'botão coberto pelo teclado');
        expect(botao.top, greaterThan(0));
        expect(t.getRect(campo).top, greaterThan(0));
        expect(t.getRect(campo).bottom, lessThanOrEqualTo(botao.top));
        expect(t.takeException(), isNull);

        // Depois de validar, a resposta (e o próximo botão) continua acima do teclado.
        await t.tap(find.byKey(const ValueKey('validar-codigo')));
        await t.pumpAndSettle();
        final proximo = find.byKey(const ValueKey('aplicar-codigo')).evaluate().isNotEmpty
            ? find.byKey(const ValueKey('aplicar-codigo'))
            : find.byKey(const ValueKey('validar-codigo'));
        expect(t.getRect(proximo).bottom, lessThanOrEqualTo(limite));
      });
    }
  }
}
