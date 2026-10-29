import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/pedidos/seus_pedidos_tela.dart';
import 'package:trato/tema/tema.dart';

const _telas = {
  'pequeno 320x568': Size(320, 568),
  'protótipo 390x844': Size(390, 844),
  'tablet 768x1024': Size(768, 1024),
};

Future<void> _abrir(
  WidgetTester tester,
  Widget tela, {
  Size tamanho = const Size(390, 844),
  double fonte = 1,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: tela,
    ),
  );
}

void main() {
  test('formatarReais', () {
    expect(formatarReais(4500), 'R\$ 45,00');
    expect(formatarReais(5), 'R\$ 0,05');
    expect(formatarReais(123456789), 'R\$ 1.234.567,89');
  });

  group('Seus pedidos', () {
    testWidgets('mostra os pedidos em andamento e troca de aba',
        (tester) async {
      await _abrir(tester, const SeusPedidosTela());
      expect(find.text('Troca de tomadas e chuveiro'), findsOneWidget);
      expect(find.text('Disputa aberta · valor congelado'), findsOneWidget);
      expect(find.text('Finalizado'), findsNothing);

      await tester.tap(find.text('Finalizados'));
      await tester.pumpAndSettle();
      expect(find.text('Troca de tomadas e chuveiro'), findsNothing);
      expect(find.text('Finalizado'), findsOneWidget);

      await tester.tap(find.text('Em andamento'));
      await tester.pumpAndSettle();
      expect(find.text('Instalar ventilador de teto'), findsOneWidget);
    });

    testWidgets('tocar no cartão abre o pedido', (tester) async {
      PedidoResumo? aberto;
      await _abrir(tester, SeusPedidosTela(aoAbrirPedido: (p) => aberto = p));
      await tester.tap(find.text('Vazamento na pia'));
      expect(aberto?.titulo, 'Vazamento na pia');
    });
  });

  group('Pedido em execução', () {
    testWidgets('aprovar o aditivo troca os botões pelo resultado',
        (tester) async {
      var aprovou = false;
      await _abrir(
          tester, PedidoExecucaoTela(aoAprovarAditivo: () => aprovou = true));
      expect(find.text('Aditivo aguardando sua resposta'), findsOneWidget);
      expect(find.textContaining('R\$ 45,00'), findsOneWidget);
      expect(find.text('Pagamento retido até a conclusão'), findsOneWidget);

      await tester.tap(find.text('Aprovar aditivo'));
      await tester.pumpAndSettle();
      expect(aprovou, isTrue);
      expect(find.text('Aditivo aprovado'), findsOneWidget);
      expect(find.text('Recusar'), findsNothing);
    });

    testWidgets('recusar o aditivo', (tester) async {
      var recusou = false;
      await _abrir(
          tester, PedidoExecucaoTela(aoRecusarAditivo: () => recusou = true));
      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();
      expect(recusou, isTrue);
      expect(find.text('Aditivo recusado'), findsOneWidget);
      expect(find.text('Aprovar aditivo'), findsNothing);
    });

    testWidgets('SOS, Conversar e Ver conclusão chamam as ações',
        (tester) async {
      final toques = <String>[];
      await _abrir(
        tester,
        PedidoExecucaoTela(
          aoTocarSos: () => toques.add('sos'),
          aoConversar: () => toques.add('conversar'),
          aoVerConclusao: () => toques.add('conclusao'),
        ),
      );
      await tester.tap(find.text('SOS'));
      await tester.tap(find.text('Conversar'));
      await tester.tap(find.text('Ver conclusão'));
      expect(toques, ['sos', 'conversar', 'conclusao']);
      expect(find.text('Linha do tempo'), findsOneWidget);
    });
  });

  group('Chat do pedido', () {
    testWidgets('mostra o aviso, a mensagem de sistema e as bolhas',
        (tester) async {
      await _abrir(tester, const ChatPedidoTela());
      expect(find.textContaining('Telefones e e-mails são ocultados'),
          findsOneWidget);
      expect(
          find.text('Serviço iniciado com o seu código às 14h10.',
              skipOffstage: false),
          findsOneWidget);
      expect(find.text('Vi aqui, vou olhar agora.'), findsOneWidget);
      expect(find.text('15h04 · lida'), findsOneWidget);
    });

    testWidgets('envia mensagem digitada e resposta rápida', (tester) async {
      final enviadas = <String>[];
      await _abrir(tester,
          ChatPedidoTela(aoEnviar: enviadas.add, horaAgora: () => '16h00'));
      await tester.enterText(find.byType(TextField), 'Obrigada!');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(find.text('Obrigada!'), findsOneWidget);
      expect(find.text('16h00'), findsOneWidget);

      await tester.tap(find.text('Tudo certo'));
      await tester.pumpAndSettle();
      expect(enviadas, ['Obrigada!', 'Tudo certo']);
    });

    testWidgets('mensagem vazia não é enviada', (tester) async {
      final enviadas = <String>[];
      await _abrir(tester, ChatPedidoTela(aoEnviar: enviadas.add));
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byTooltip('Enviar'));
      expect(enviadas, isEmpty);
    });
  });

  group('sem estouro de layout', () {
    final telas = <String, Widget>{
      'seus pedidos': const SeusPedidosTela(),
      'pedido em execução': const PedidoExecucaoTela(),
      'chat': const ChatPedidoTela(),
    };
    for (final MapEntry(key: nome, value: tela) in telas.entries) {
      for (final MapEntry(key: nomeTela, value: tamanho) in _telas.entries) {
        for (final fonte in [1.0, 1.3]) {
          testWidgets('$nome — $nomeTela, fonte x$fonte', (tester) async {
            await _abrir(tester, tela, tamanho: tamanho, fonte: fonte);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
