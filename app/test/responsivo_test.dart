import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/galeria/galeria_componentes.dart';
import 'package:trato/main.dart';
import 'package:trato/tema/tema.dart';

/// Celular pequeno, protótipo, celular grande, tablet em pé e deitado.
const _telas = {
  'pequeno 320x568': Size(320, 568),
  'protótipo 390x844': Size(390, 844),
  'grande 430x932': Size(430, 932),
  'tablet 768x1024': Size(768, 1024),
  'tablet deitado 1280x800': Size(1280, 800),
};

void _definirTela(WidgetTester tester, Size tamanho) {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('TamanhoTela.daLargura', () {
    test('faixas', () {
      expect(TamanhoTela.daLargura(320), TamanhoTela.pequeno);
      expect(TamanhoTela.daLargura(359.9), TamanhoTela.pequeno);
      expect(TamanhoTela.daLargura(360), TamanhoTela.celular);
      expect(TamanhoTela.daLargura(390), TamanhoTela.celular);
      expect(TamanhoTela.daLargura(599), TamanhoTela.celular);
      expect(TamanhoTela.daLargura(600), TamanhoTela.tablet);
      expect(TamanhoTela.daLargura(1280), TamanhoTela.tablet);
    });

    test('margem lateral cresce com a tela', () {
      expect(Responsivo.margemLateral(TamanhoTela.pequeno), 16);
      expect(Responsivo.margemLateral(TamanhoTela.celular), 20);
      expect(Responsivo.margemLateral(TamanhoTela.tablet), 32);
    });
  });

  testWidgets('no tablet o conteúdo fica com no máximo 560 de largura', (tester) async {
    _definirTela(tester, const Size(1024, 768));
    const chave = Key('conteudo');
    await tester.pumpWidget(
      const MaterialApp(
        home: ConteudoResponsivo(child: SizedBox(key: chave, height: 10, width: double.infinity)),
      ),
    );

    expect(tester.getSize(find.byKey(chave)).width, Responsivo.larguraMaximaConteudo);
    expect(tester.getCenter(find.byKey(chave)).dx, 512);
  });

  testWidgets('no celular o conteúdo usa a largura menos a margem', (tester) async {
    _definirTela(tester, const Size(390, 844));
    const chave = Key('conteudo');
    await tester.pumpWidget(
      const MaterialApp(
        home: ConteudoResponsivo(child: SizedBox(key: chave, height: 10, width: double.infinity)),
      ),
    );

    expect(tester.getSize(find.byKey(chave)).width, 390 - 2 * 20);
  });

  testWidgets('escala de fonte do sistema é limitada a 1,3', (tester) async {
    late double escala;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, filho) => EscalaFonteLimitada(child: filho!),
        home: Builder(
          builder: (context) {
            escala = MediaQuery.textScalerOf(context).scale(10) / 10;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(escala, Responsivo.escalaFonteMaxima);
  });

  // Qualquer estouro de layout (faixa amarela e preta) faz o teste falhar.
  for (final MapEntry(key: nome, value: tamanho) in _telas.entries) {
    for (final escala in [1.0, Responsivo.escalaFonteMaxima]) {
      testWidgets('sem estouro — $nome, fonte x$escala', (tester) async {
        _definirTela(tester, tamanho);
        tester.platformDispatcher.textScaleFactorTestValue = escala;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(const TratoApp());
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            builder: (context, filho) => EscalaFonteLimitada(child: filho!),
            home: const GaleriaComponentes(),
          ),
        );
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
