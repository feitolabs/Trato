import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
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

    // 3ª pergunta por categoria e por papel: o cliente fala na versão inversa.
    const porCategoria = {
      'Eletricista': (
        'Preciso deixar o quadro de luz identificado antes da visita?',
        'Sabe me dizer se o quadro de luz está identificado?',
      ),
      'Pintura': (
        'Preciso mover ou cobrir os móveis antes?',
        'Posso mover os móveis ou você prefere deixar cobertos?',
      ),
      'Câmeras e segurança': (
        'Preciso ter internet e tomada perto de onde ficarão as câmeras?',
        'Tem internet e tomada perto de onde ficarão as câmeras?',
      ),
    };
    for (final MapEntry(key: categoria, value: (cliente, profissional)) in porCategoria.entries) {
      testWidgets('$categoria: o cliente vê a versão dele', (tester) async {
        await _abrir(tester, _conversa(categoria: categoria));
        expect(find.text(cliente), findsOneWidget);
        expect(find.text(profissional), findsNothing);
        expect(find.text(_materialCliente), findsNothing);
        expect(find.text(_estacionar), findsOneWidget); // as outras 3 continuam
      });

      testWidgets('$categoria: o profissional mantém a versão atual', (tester) async {
        await _abrir(tester, _conversa(categoria: categoria, souCliente: false));
        expect(find.text(profissional), findsOneWidget);
        expect(find.text(cliente), findsNothing);
        expect(find.text(_materialPro), findsNothing);
        expect(find.text(_estacionar), findsOneWidget);
      });
    }
  });

  group('F44 · Fluxo real da rota do chat (API + RotasTrato)', () {
    http.Response jsonResposta(Object corpo, [int status = 200]) => http.Response(
          jsonEncode(corpo),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    ClienteApi clienteSimulado(http.Response Function(http.Request) responder) {
      final sessao = SessaoTrato()..entrar('token-teste');
      return ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: sessao,
        cliente: MockClient((req) async => responder(req)),
      );
    }

    Future<void> abrirRota(WidgetTester tester, Widget tela) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'profissional em pedido aberto (404 em /v1/pedidos/{id}) recebe categoria Pintura de interiores e mostra o roteiro sem quebrar chips rápidos',
      (tester) async {
        final anteriores = RotasTrato.repos;
        addTearDown(() => RotasTrato.repos = anteriores);

        final api = clienteSimulado((req) {
          switch (req.url.path) {
            case '/v1/pedidos/fdda1234/mensagens':
              return jsonResposta(<Object>[]);
            case '/v1/pedidos/fdda1234/orcamentos':
              return jsonResposta(<Object>[]);
            case '/v1/pedidos/fdda1234':
              return jsonResposta({'detail': 'Pedido não encontrado.'}, 404);
            case '/v1/pedidos/fdda1234/interlocutor':
              return jsonResposta({'id': 'cli-1', 'nome': 'Ana S.', 'papel': 'cliente'});
            case '/v1/profissional/pedidos-abertos/fdda1234':
              return jsonResposta({
                'id': 'fdda1234',
                'titulo': 'Pintar sala e corredor',
                'categoria_nome': 'Pintura de interiores',
                'modalidade': 'presencial',
              });
            default:
              return jsonResposta({'detail': 'não encontrado'}, 404);
          }
        });
        RotasTrato.repos = RepositoriosTrato.api(api);

        await abrirRota(
          tester,
          RotasTrato.chatParaTeste('fdda1234', comoProfissional: true),
        );

        expect(find.text('Sugestões para combinar'), findsOneWidget);
        expect(find.text('Esconder sugestões'), findsOneWidget);
        expect(
          find.text('Posso mover os móveis ou você prefere deixar cobertos?'),
          findsOneWidget,
        );
        // Chips rápidos existentes continuam intactos.
        expect(find.text('Tudo certo'), findsOneWidget);
        expect(find.text('Pode me mandar foto?'), findsOneWidget);
        await tester.drag(find.text('Pode me mandar foto?'), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(find.text('Que horas termina?'), findsOneWidget);
      },
    );

    testWidgets(
      'profissional mantém roteiro de Pintura via fallback da rota mesmo se /profissional/pedidos-abertos/{id} retornar 404',
      (tester) async {
        final anteriores = RotasTrato.repos;
        addTearDown(() => RotasTrato.repos = anteriores);

        final api = clienteSimulado((req) {
          if (req.url.path == '/v1/pedidos/fdda9999/mensagens') return jsonResposta(<Object>[]);
          if (req.url.path == '/v1/pedidos/fdda9999/interlocutor') {
            return jsonResposta({'id': 'cli-1', 'nome': 'Ana S.', 'papel': 'cliente'});
          }
          return jsonResposta({'detail': 'não encontrado'}, 404);
        });
        RotasTrato.repos = RepositoriosTrato.api(api);

        await abrirRota(
          tester,
          RotasTrato.chatParaTeste(
            'fdda9999',
            comoProfissional: true,
            categoriaNome: 'Pintura de interiores',
          ),
        );

        expect(find.text('Sugestões para combinar'), findsOneWidget);
        expect(find.text('Esconder sugestões'), findsOneWidget);
        expect(
          find.text('Posso mover os móveis ou você prefere deixar cobertos?'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'cliente em pedido aberto de Pintura de interiores vê o roteiro na voz do cliente e os chips rápidos',
      (tester) async {
        final anteriores = RotasTrato.repos;
        addTearDown(() => RotasTrato.repos = anteriores);

        final api = clienteSimulado((req) {
          switch (req.url.path) {
            case '/v1/pedidos/cli12345/mensagens':
              return jsonResposta(<Object>[]);
            case '/v1/pedidos/cli12345/orcamentos':
              return jsonResposta(<Object>[]);
            case '/v1/pedidos/cli12345':
              return jsonResposta({
                'id': 'cli12345',
                'estado': 'aberto',
                'estado_nome': 'Pedido aberto',
                'cliente_id': 'cli-1',
                'profissional_id': null,
                'aberto_em': '2026-11-21T12:00:00Z',
                'janela': null,
                'concluido_em': null,
                'acoes_permitidas': <String>[],
                'codigo_inicio': null,
                'codigo_conclusao': null,
                'modalidade': 'presencial',
                'categoria_nome': 'Pintura de interiores',
                'titulo': 'Pintar sala',
              });
            case '/v1/pedidos/cli12345/interlocutor':
              return jsonResposta({'id': 'pro-1', 'nome': 'Carlos M.', 'papel': 'profissional'});
            default:
              return jsonResposta({'detail': 'não encontrado'}, 404);
          }
        });
        RotasTrato.repos = RepositoriosTrato.api(api);

        await abrirRota(
          tester,
          RotasTrato.chatParaTeste(
            'cli12345',
            profissionalId: 'pro-1',
            comoProfissional: false,
          ),
        );

        expect(find.text('Sugestões para combinar'), findsOneWidget);
        expect(find.text('Esconder sugestões'), findsOneWidget);
        expect(find.text('Preciso mover ou cobrir os móveis antes?'), findsOneWidget);
        expect(find.text('Tudo certo'), findsOneWidget);
        expect(find.text('Pode me mandar foto?'), findsOneWidget);
        await tester.drag(find.text('Pode me mandar foto?'), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(find.text('Que horas termina?'), findsOneWidget);
      },
    );

    testWidgets('pedido concluído não exibe a faixa de sugestões no fluxo real', (tester) async {
      final anteriores = RotasTrato.repos;
      addTearDown(() => RotasTrato.repos = anteriores);

      final api = clienteSimulado((req) {
        switch (req.url.path) {
          case '/v1/pedidos/5226abcd/mensagens':
            return jsonResposta(<Object>[]);
          case '/v1/pedidos/5226abcd/orcamentos':
            return jsonResposta(<Object>[]);
          case '/v1/pedidos/5226abcd':
            return jsonResposta({
              'id': '5226abcd',
              'estado': 'concluido',
              'estado_nome': 'Concluído',
              'cliente_id': 'cli-1',
              'profissional_id': 'pro-1',
              'aberto_em': '2026-11-10T12:00:00Z',
              'janela': null,
              'concluido_em': '2026-11-12T15:00:00Z',
              'acoes_permitidas': <String>[],
              'codigo_inicio': null,
              'codigo_conclusao': null,
              'modalidade': 'presencial',
              'categoria_nome': 'Pintura de interiores',
              'titulo': 'Pintar sala',
            });
          case '/v1/pedidos/5226abcd/interlocutor':
            return jsonResposta({'id': 'cli-1', 'nome': 'Ana S.', 'papel': 'cliente'});
          default:
            return jsonResposta({'detail': 'não encontrado'}, 404);
        }
      });
      RotasTrato.repos = RepositoriosTrato.api(api);

      await abrirRota(
        tester,
        RotasTrato.chatParaTeste('5226abcd', comoProfissional: true),
      );

      expect(find.text('Sugestões para combinar'), findsNothing);
      expect(find.text('Esconder sugestões'), findsNothing);
      expect(find.text('Tudo certo'), findsOneWidget);
    });
  });
}
