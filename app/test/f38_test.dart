import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/telas/pedidos/chat_pedido_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

const _acesso = 'Como é o acesso ao local? Tem portaria ou hora para entrar?';
const _estacionar = 'Tem onde estacionar perto?';
const _horario = 'Qual horário é melhor para você?';
const _materialCliente = 'Você traz o material ou eu compro?';
const _materialPro = 'O material fica por minha conta ou por sua?';

ConversaPedido _conversa({
  String? estado = 'aberto',
  String? categoria,
  bool souCliente = true,
  String pedidoId = 'ped-1',
}) =>
    ConversaPedido(
      nome: 'Carlos M.',
      iniciais: 'CM',
      numeroPedido: 'AB12',
      situacao: 'Aberto',
      mensagens: const [],
      respostasRapidas: const [],
      pedidoId: pedidoId,
      estadoApi: estado,
      categoriaNome: categoria,
      souCliente: souCliente,
    );

Future<void> _abrir(
  WidgetTester tester,
  ConversaPedido conversa, {
  void Function(String)? aoEnviar,
}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaTrato.claro,
      home: ChatPedidoTela(key: UniqueKey(), conversa: conversa, aoEnviar: aoEnviar),
    ),
  );
  await tester.pumpAndSettle();
}

/// Rola a faixa horizontal até a sugestão aparecer e toca nela.
Future<void> _tocarSugestao(WidgetTester tester, String texto) async {
  final chip = find.byKey(ValueKey('sugestao-$texto'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

String _campo(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('F38 · Roteiro do combinado', () {
    for (final estado in ['aberto', 'reservado', 'orcamento_aceito', 'pago_e_retido', 'agendado']) {
      testWidgets('aparece com o pedido $estado (4 sugestões, cliente)', (tester) async {
        await _abrir(tester, _conversa(estado: estado));
        expect(find.text('Sugestões para combinar'), findsOneWidget);
        expect(find.text(_acesso), findsOneWidget);
        expect(find.text(_estacionar), findsOneWidget);
        expect(find.text(_materialCliente), findsOneWidget);
        expect(find.text(_horario), findsOneWidget);
        expect(find.byKey(const Key('esconder-sugestoes')), findsOneWidget);
      });
    }

    testWidgets('o profissional vê a pergunta do material na voz dele', (tester) async {
      await _abrir(tester, _conversa(souCliente: false));
      expect(find.text(_materialPro), findsOneWidget);
      expect(find.text(_materialCliente), findsNothing);
    });

    for (final estado in [
      'em_andamento',
      'em_confirmacao',
      'concluido',
      'cancelado',
      'em_disputa',
      'retrabalho',
      null,
    ]) {
      testWidgets('não aparece com o pedido $estado', (tester) async {
        await _abrir(tester, _conversa(estado: estado));
        expect(find.text('Sugestões para combinar'), findsNothing);
        expect(find.text(_estacionar), findsNothing);
        expect(find.byType(TextField), findsOneWidget); // o chat segue igual
      });
    }

    testWidgets('tocar preenche o campo sem enviar e o chip some', (tester) async {
      final enviados = <String>[];
      await _abrir(tester, _conversa(), aoEnviar: enviados.add);
      await _tocarSugestao(tester, _estacionar);
      expect(_campo(tester), _estacionar);
      expect(enviados, isEmpty);
      expect(find.text(_estacionar), findsNWidgets(1)); // só o texto digitado no campo
      expect(find.byKey(const ValueKey('sugestao-$_estacionar')), findsNothing);
      expect(find.text(_horario), findsOneWidget);

      // Outro chip acrescenta ao que já está no campo, também sem enviar.
      await _tocarSugestao(tester, _horario);
      expect(_campo(tester), '$_estacionar $_horario');
      expect(enviados, isEmpty);
    });

    testWidgets('usadas todas as sugestões, a faixa some', (tester) async {
      await _abrir(tester, _conversa());
      for (final s in [_acesso, _estacionar, _materialCliente, _horario]) {
        await _tocarSugestao(tester, s);
      }
      expect(find.text('Sugestões para combinar'), findsNothing);
    });

    testWidgets('Esconder sugestões some e fica guardado para aquele pedido', (tester) async {
      await _abrir(tester, _conversa());
      await tester.tap(find.byKey(const Key('esconder-sugestoes')));
      await tester.pumpAndSettle();
      expect(find.text('Sugestões para combinar'), findsNothing);

      // Abrindo o mesmo pedido de novo (tela nova): continua escondido.
      await _abrir(tester, _conversa());
      expect(find.text('Sugestões para combinar'), findsNothing);

      // Outro pedido não é afetado.
      await _abrir(tester, _conversa(pedidoId: 'ped-2'));
      expect(find.text('Sugestões para combinar'), findsOneWidget);
    });

    testWidgets('categorias especiais trocam a 3ª pergunta', (tester) async {
      await _abrir(tester, _conversa(categoria: 'Eletricista'));
      expect(find.text('Sabe me dizer se o quadro de luz está identificado?'), findsOneWidget);
      expect(find.text(_materialCliente), findsNothing);

      await _abrir(tester, _conversa(categoria: 'Pintura'));
      expect(find.text('Posso mover os móveis ou você prefere deixar cobertos?'), findsOneWidget);

      await _abrir(tester, _conversa(categoria: 'Câmeras e segurança'));
      expect(
        find.text('Tem internet e tomada perto de onde ficarão as câmeras?'),
        findsOneWidget,
      );
      expect(find.text(_estacionar), findsOneWidget); // as outras 3 continuam
    });
  });
}
