import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/componentes/imagem_trato.dart';
import 'package:trato/telas/conclusao/relatar_problema_tela.dart';
import 'package:trato/telas/disputa_profissional/responder_disputa_tela.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/conclusao/dados_exemplo.dart';
import 'apoio/exemplos/telas/disputa_profissional/disputa_fake.dart';
import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart';
import 'apoio/fontes.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

/// Telas que aceitam anexar foto, com o texto do botão e o número da primeira foto anexada.
final _telas = <(String, Widget Function(Future<String?> Function()), String, int)>[
  (
    'novo pedido',
    (captura) => NovoPedidoTela(formulario: formularioExemplo, aoCapturarFoto: captura),
    'Adicionar',
    formularioExemplo.fotos.length + 1,
  ),
  (
    'relatar problema',
    (captura) => RelatarProblemaTela(dados: dadosRelatoExemplo, aoCapturarFoto: captura),
    'Adicionar',
    1,
  ),
  (
    'responder disputa',
    (captura) => ResponderDisputaTela(
        servico: ServicoDisputaProfissionalFake(disputa: disputaExemplo),
        disputaId: 'disp-1',
        aoAdicionarEvidencia: captura),
    'Anexar foto',
    1,
  ),
];

Future<void> _anexar(WidgetTester t, Widget tela, String botao, double fonte) async {
  t.view.physicalSize = const Size(390, 2800);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(botao));
  await t.tap(find.text(botao));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);

  for (final (nome, montar, botao, numero) in _telas) {
    for (final fonte in [1.0, 1.3]) {
      testWidgets('$nome: nada escrito sobre a foto anexada (x$fonte)', (t) async {
        registrarImagemEmMemoria('f83-$nome', bytes: _png);
        await _anexar(t, montar(() async => 'f83-$nome'), botao, fonte);
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('Foto $numero'), findsNothing);
        expect(find.text('[Foto $numero]'), findsNothing);
        expect(find.text('Foto anexada'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('$nome: foto sem imagem no aparelho mostra "Foto N", sem colchetes', (t) async {
      await _anexar(t, montar(() async => 'arq-sem-imagem'), botao, 1);
      expect(find.text('Foto $numero'), findsOneWidget);
      expect(find.text('[Foto $numero]'), findsNothing);
    });
  }
}
