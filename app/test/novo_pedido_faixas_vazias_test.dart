import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pedido_novo/modelos.dart';
import 'package:trato/telas/pedido_novo/novo_pedido_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/telas/pedido_novo/dados_exemplo.dart';
import 'apoio/endereco_pedido.dart';

FormularioPedido _formularioSemFaixas() => FormularioPedido(
      categoria: formularioExemplo.categoria,
      categoriaId: formularioExemplo.categoriaId,
      servicos: formularioExemplo.servicos,
      servicosIniciais: formularioExemplo.servicosIniciais,
      perguntaQuantidade: formularioExemplo.perguntaQuantidade,
      dicaQuantidade: formularioExemplo.dicaQuantidade,
      quantidadeInicial: formularioExemplo.quantidadeInicial,
      perguntaVoltagem: formularioExemplo.perguntaVoltagem,
      voltagens: formularioExemplo.voltagens,
      voltagemInicial: formularioExemplo.voltagemInicial,
      descricaoInicial: formularioExemplo.descricaoInicial,
      fotos: formularioExemplo.fotos,
      prazos: formularioExemplo.prazos,
      faixas: const [],
      endereco: formularioExemplo.endereco,
      avisoEndereco: formularioExemplo.avisoEndereco,
      avisoPrazo: formularioExemplo.avisoPrazo,
      aceitaRemoto: true,
    );

void main() {
  testWidgets('faixas vazias: abre sem crashar, permite informar valor próprio e enviar',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    RascunhoPedido? enviado;
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaTrato.claro,
        home: NovoPedidoTela(
          formulario: _formularioSemFaixas(),
          aoEnviar: (r) => enviado = r,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Faixa estimada'), findsNothing);
    expect(find.text('Escolha uma faixa'), findsNothing);
    expect(find.text('Valor que pretende gastar'), findsOneWidget);

    await preencherEnderecoDoPedido(tester);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Ex.: 300,00'),
      '250,00',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Enviar pedido'));
    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(enviado, isNotNull);
    expect(enviado!.faixa.minimoCentavos, 25000);
    expect(enviado!.faixa.maximoCentavos, 25000);
  });
}
