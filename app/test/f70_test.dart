import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/notificacoes_tela.dart';
import 'package:trato/telas/orcamentos/orcamentos_recebidos_tela.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/tema/tema.dart';

/// Abre a tela de Notificações pela rota real (cliente ou profissional), com os dados de exemplo.
Future<void> _abrirNotificacoes(WidgetTester tester, {required bool profissional}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => RotasTrato.abrirNotificacoes(context, profissional: profissional),
              child: const Text('abrir-notificacoes'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir-notificacoes'));
  await tester.pumpAndSettle();
  expect(find.byType(NotificacoesTela), findsOneWidget);
}

Future<void> _tocar(WidgetTester tester, String titulo) async {
  await tester.tap(find.text(titulo));
  await tester.pumpAndSettle();
}

void main() {
  group('Notificações com pedido_id abrem o destino certo', () {
    testWidgets('cliente: novo orçamento abre os orçamentos recebidos do pedido', (tester) async {
      await _abrirNotificacoes(tester, profissional: false);
      await _tocar(tester, 'Novo orçamento');
      expect(find.byType(OrcamentosRecebidosTela), findsOneWidget);
    });

    testWidgets('cliente: mensagem nova abre o chat do pedido', (tester) async {
      await _abrirNotificacoes(tester, profissional: false);
      await _tocar(tester, 'Nova mensagem de Carlos Mendes');
      expect(find.byType(ChatPedidoTela), findsOneWidget);
    });

    testWidgets('cliente: pedido (profissional chegou) e pagamento abrem o serviço', (tester) async {
      await _abrirNotificacoes(tester, profissional: false);
      await _tocar(tester, 'Carlos Mendes chegou');
      expect(find.byType(PedidoExecucaoTela), findsOneWidget);
    });

    testWidgets('profissional: mensagem nova abre o chat do pedido', (tester) async {
      await _abrirNotificacoes(tester, profissional: true);
      await _tocar(tester, 'Nova mensagem de Carlos Mendes');
      expect(find.byType(ChatPedidoTela), findsOneWidget);
    });
  });
}
