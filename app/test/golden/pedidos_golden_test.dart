import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/tema/tema.dart';

import '../apoio/fontes.dart';
import '../apoio/exemplos/telas/pedidos/dados_exemplo.dart' as exped;

/// Telas 15 a 17 do protótipo em celular pequeno, protótipo e tablet.
/// Atualizar: flutter test --update-goldens
void main() {
  setUpAll(carregarFontesTrato);

  const tamanhos = {
    'celular_pequeno': Size(320, 640),
    'celular': Size(390, 844),
    'tablet': Size(768, 1024),
  };
  final telas = <String, Widget>{
    'seus_pedidos': const SeusPedidosTela(emAndamento: exped.DadosExemplo.pedidosEmAndamento, finalizados: exped.DadosExemplo.pedidosFinalizados, ),
    'pedido_execucao': const PedidoExecucaoTela(pedido: exped.DadosExemplo.pedidoEmExecucao, ),
    'chat': const ChatPedidoTela(conversa: exped.DadosExemplo.conversa, ),
  };

  for (final MapEntry(key: tela, value: widget) in telas.entries) {
    for (final MapEntry(key: nome, value: tamanho) in tamanhos.entries) {
      testWidgets('$tela — $nome', (tester) async {
        tester.view.physicalSize = tamanho;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaTrato.claro,
            debugShowCheckedModeBanner: false,
            builder: (context, filho) => EscalaFonteLimitada(child: filho!),
            home: widget,
          ),
        );

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('pedidos_${tela}_$nome.png'));
      });
    }
  }
}
