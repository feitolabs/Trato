// APP-TERMOS-100A: serviços não cobertos (cláusula 3.7) onde se pede e onde se oferece.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/tema/tema.dart';
import 'package:trato/telas/comuns/servicos_nao_cobertos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/telas/profissional_cadastro/cadastro_profissional_tela.dart';

import 'apoio/exemplos/telas/profissional_cadastro/cadastro_fake.dart';
import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart';
import 'apoio/fontes.dart';

void _alta(WidgetTester t) {
  t.view.physicalSize = const Size(390, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(carregarFontesTrato);

  testWidgets('resumo à vista; tocar mostra os quatro casos da 3.7 (320 px, 1,3x)', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: const Scaffold(body: SingleChildScrollView(child: CartaoServicosNaoCobertos())),
    ));
    expect(find.text('Serviços não cobertos'), findsOneWidget);
    expect(find.textContaining('habilitação ou registro'), findsOneWidget);
    expect(find.text(servicosNaoCobertos.first), findsNothing);
    await t.tap(find.text('Serviços não cobertos'));
    await t.pumpAndSettle();
    expect(servicosNaoCobertos, hasLength(4));
    for (final item in servicosNaoCobertos) {
      expect(find.text(item), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('quem pede vê o aviso no formulário do pedido', (t) async {
    _alta(t);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: const NovoPedidoTela(formulario: formularioExemplo),
    ));
    await t.pumpAndSettle();
    expect(find.byType(CartaoServicosNaoCobertos, skipOffstage: false), findsOneWidget);
  });

  testWidgets('quem oferece vê o aviso ao escolher categorias', (t) async {
    _alta(t);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: CadastroProfissionalTela(servico: ServicoCadastroProfissionalFake()),
    ));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Carlos Almeida');
    await t.enterText(find.byType(TextField).at(1), '10 anos em elétrica residencial.');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    expect(find.text('O que você faz'), findsOneWidget);
    expect(find.byType(CartaoServicosNaoCobertos, skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('quem oferece não escolhe remoto: o cadastro salva só presencial', (t) async {
    _alta(t);
    await t.pumpWidget(MaterialApp(
      theme: TemaTrato.claro,
      home: CadastroProfissionalTela(servico: ServicoCadastroProfissionalFake()),
    ));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Carlos Almeida');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Eletricista'));
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    expect(find.text('Onde e quando atende'), findsOneWidget);
    expect(find.text('Como você atende'), findsNothing);
    expect(find.text('Remoto'), findsNothing);
  });

  for (final remoto in [true, false]) {
    testWidgets('profissional, pedido concluído ${remoto ? 'remoto antigo' : 'presencial'}',
        (t) async {
      _alta(t);
      await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: const Scaffold()));
      RotasTrato.acoesPedidoProfissionalParaTeste(
        t.element(find.byType(Scaffold)),
        estadoApi: 'concluido',
        remoto: remoto,
      );
      await t.pumpAndSettle();
      // O pedido antigo continua abrindo; só não dá para repetir um remoto.
      expect(find.byKey(const ValueKey('baixar-comprovante')), findsOneWidget);
      expect(find.byKey(const ValueKey('repetir-servico')), remoto ? findsNothing : findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
