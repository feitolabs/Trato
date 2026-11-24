import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/pedidos/reagendamento.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';

final _inicio = DateTime(2030, 3, 14, 14);
final _fim = DateTime(2030, 3, 14, 16);

Reagendamento _prop({
  String id = 'r1',
  String por = 'outro',
  String status = 'pendente',
  String motivo = 'Imprevisto no trabalho',
}) =>
    Reagendamento(
      id: id,
      propostoPor: por,
      inicio: _inicio,
      fim: _fim,
      motivo: motivo,
      status: status,
    );

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: Scaffold(body: tela)));
  await tester.pumpAndSettle();
}

/// Seção ligada a uma lista em memória, como o backend faria.
class _Mundo {
  _Mundo({List<Reagendamento>? itens}) : itens = [...?itens];

  final List<Reagendamento> itens;
  final chamadas = <String>[];
  Object? falhar;
  Completer<void>? travar;
  var mudou = 0;

  Widget secao({String? meuId = 'eu'}) => SecaoReagendamento(
        meuId: meuId,
        aoMudar: () => mudou++,
        agora: () => DateTime(2030, 1, 1),
        escolherDia: (_) async => DateTime(2030, 3, 14),
        escolherHora: (_, inicial) async => inicial.hour == 9
            ? const TimeOfDay(hour: 14, minute: 0)
            : const TimeOfDay(hour: 16, minute: 0),
        carregar: () async => List.of(itens),
        propor: (i, f, m) async {
          chamadas.add('propor:$i|$f|$m');
          if (falhar != null) throw falhar!;
          itens.insert(0, Reagendamento(id: 'novo', propostoPor: 'eu', inicio: i, fim: f, motivo: m ?? ''));
        },
        aceitar: (id) async {
          chamadas.add('aceitar:$id');
          if (travar != null) await travar!.future;
          if (falhar != null) throw falhar!;
          itens[0] = _prop(id: id, status: 'aceito');
        },
        recusar: (id) async {
          chamadas.add('recusar:$id');
          if (falhar != null) throw falhar!;
          itens[0] = _prop(id: id, status: 'recusado');
        },
      );
}

void main() {
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('Modelo e API', () {
    test('Reagendamento.deJson lê os campos e ignora item sem id/datas', () {
      final r = Reagendamento.deJson({
        'id': 'r1',
        'pedido_id': 'p1',
        'proposto_por': 'u1',
        'nova_janela_inicio': '2030-03-14T17:00:00Z',
        'nova_janela_fim': '2030-03-14T19:00:00Z',
        'motivo': null,
        'status': 'pendente',
      })!;
      expect(r.id, 'r1');
      expect(r.propostoPor, 'u1');
      expect(r.pendente, isTrue);
      expect(r.motivo, '');
      expect(r.fim.difference(r.inicio), const Duration(hours: 2));
      expect(Reagendamento.deJson({'id': 'x'}), isNull);
      expect(Reagendamento.deJson('lixo'), isNull);
      expect(Reagendamento.deJson({'id': 'r', 'nova_janela_inicio': '2030-01-01T00:00:00Z', 'nova_janela_fim': '2030-01-01T01:00:00Z', 'status': 'aceito'})!.pendente, isFalse);
    });

    test('lista, propõe, aceita e recusa nas rotas /reagendamentos', () async {
      final pedidas = <http.Request>[];
      final api = ClienteApi(
        urlBase: 'https://api.teste/',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((req) async {
          pedidas.add(req);
          if (req.method == 'GET') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'r2',
                  'pedido_id': 'p1',
                  'proposto_por': 'u1',
                  'nova_janela_inicio': '2030-03-14T17:00:00Z',
                  'nova_janela_fim': '2030-03-14T19:00:00Z',
                  'motivo': 'chuva',
                  'status': 'pendente',
                },
                {'sem': 'id'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 201, headers: {'content-type': 'application/json'});
        }),
      );
      final repo = RepositorioPedidosApi(api);

      final lista = await repo.reagendamentos('p1');
      expect(lista.map((r) => r.id), ['r2']);
      expect(lista.single.motivo, 'chuva');

      await repo.proporReagendamento(
        'p1',
        inicio: DateTime.utc(2030, 3, 14, 17),
        fim: DateTime.utc(2030, 3, 14, 19),
        motivo: '  chuva  ',
      );
      await repo.proporReagendamento(
        'p1',
        inicio: DateTime.utc(2030, 3, 14, 17),
        fim: DateTime.utc(2030, 3, 14, 19),
      );
      await repo.aceitarReagendamento('p1', 'r2');
      await repo.recusarReagendamento('p1', 'r2');

      expect(pedidas[0].url.path, '/v1/pedidos/p1/reagendamentos');
      expect(pedidas[1].method, 'POST');
      expect(pedidas[1].url.path, '/v1/pedidos/p1/reagendamentos');
      expect(jsonDecode(pedidas[1].body), {
        'nova_janela_inicio': '2030-03-14T17:00:00.000Z',
        'nova_janela_fim': '2030-03-14T19:00:00.000Z',
        'motivo': 'chuva',
      });
      expect((jsonDecode(pedidas[2].body) as Map).containsKey('motivo'), isFalse);
      expect(pedidas[3].url.path, '/v1/pedidos/p1/reagendamentos/r2/aceitar');
      expect(pedidas[4].url.path, '/v1/pedidos/p1/reagendamentos/r2/recusar');
    });
  });

  group('Seção de reagendamento', () {
    testWidgets('sem proposta pendente: botão "Reagendar" → propõe nova data e passa a aguardar',
        (tester) async {
      final mundo = _Mundo();
      await _abrir(tester, mundo.secao());
      expect(find.text('Reagendar'), findsOneWidget);
      expect(find.byKey(const ValueKey('cartao-reagendamento')), findsNothing);

      await tester.tap(find.text('Reagendar'));
      await tester.pumpAndSettle();
      expect(find.text('Propor nova data'), findsOneWidget);

      // Sem escolher nada: aviso e a folha continua.
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('erro-reagendar')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reagendar-dia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reagendar-inicio')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reagendar-fim')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('reagendar-motivo')), '  Chuva forte  ');
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();

      expect(mundo.chamadas, ['propor:$_inicio|$_fim|Chuva forte']);
      expect(mundo.mudou, 1);
      // Agora a proposta é minha: aguarda a resposta e pode cancelar.
      expect(find.text('Aguardando resposta sobre a nova data'), findsOneWidget);
      expect(find.text('Cancelar proposta'), findsOneWidget);
      expect(find.text('Reagendar'), findsNothing);
      expect(find.text('Aceitar nova data'), findsNothing);
    });

    testWidgets('fim antes do início ou data passada não envia', (tester) async {
      final mundo = _Mundo();
      await tester.pumpWidget(const SizedBox());
      await _abrir(
        tester,
        SecaoReagendamento(
          meuId: 'eu',
          agora: () => DateTime(2030, 3, 14, 15), // depois do início escolhido (14h)
          escolherDia: (_) async => DateTime(2030, 3, 14),
          escolherHora: (_, inicial) async => inicial.hour == 9
              ? const TimeOfDay(hour: 14, minute: 0)
              : const TimeOfDay(hour: 16, minute: 0),
          carregar: () async => const [],
          propor: (i, f, m) async => mundo.chamadas.add('propor'),
          aceitar: (_) async {},
          recusar: (_) async {},
        ),
      );
      await tester.tap(find.text('Reagendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reagendar-dia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reagendar-inicio')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reagendar-fim')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar proposta'));
      await tester.pumpAndSettle();
      expect(find.text('Escolha uma data no futuro.'), findsOneWidget);
      expect(mundo.chamadas, isEmpty);
    });

    testWidgets('proposta da outra parte: mostra data e motivo; aceitar com uma vez só',
        (tester) async {
      final mundo = _Mundo(itens: [_prop()])..travar = Completer<void>();
      await _abrir(tester, mundo.secao());

      expect(find.text('Nova data proposta'), findsOneWidget);
      expect(find.text('Qui, 14/03 · 14:00 às 16:00'), findsOneWidget);
      expect(find.text('Motivo: Imprevisto no trabalho'), findsOneWidget);
      expect(find.text('Reagendar'), findsNothing);
      expect(find.text('Aceitar nova data'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);

      await tester.tap(find.text('Aceitar nova data'));
      await tester.pump();
      // Trava de duplo clique: enquanto responde, o botão ignora toques.
      await tester.tap(find.byKey(const ValueKey('aceitar-nova-data')), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('recusar-nova-data')), warnIfMissed: false);
      await tester.pump();
      expect(mundo.chamadas, ['aceitar:r1']);

      mundo.travar!.complete();
      await tester.pumpAndSettle();
      expect(mundo.mudou, 1);
      expect(find.byKey(const ValueKey('cartao-reagendamento')), findsNothing);
      expect(find.text('Reagendar'), findsOneWidget); // sem pendente de novo
    });

    testWidgets('recusar chama /recusar', (tester) async {
      final mundo = _Mundo(itens: [_prop()]);
      await _abrir(tester, mundo.secao());
      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();
      expect(mundo.chamadas, ['recusar:r1']);
      expect(find.text('Reagendar'), findsOneWidget);
    });

    testWidgets('quem propôs vê "Aguardando resposta" e cancela a proposta (/recusar)',
        (tester) async {
      final mundo = _Mundo(itens: [_prop(por: 'eu')]);
      await _abrir(tester, mundo.secao());
      expect(find.text('Aguardando resposta sobre a nova data'), findsOneWidget);
      expect(find.text('Aceitar nova data'), findsNothing);
      expect(find.text('Recusar'), findsNothing);
      await tester.tap(find.text('Cancelar proposta'));
      await tester.pumpAndSettle();
      expect(mundo.chamadas, ['recusar:r1']);
    });

    testWidgets('proposta já respondida não conta como pendente', (tester) async {
      final mundo = _Mundo(itens: [_prop(status: 'recusado'), _prop(id: 'r0', status: 'aceito')]);
      await _abrir(tester, mundo.secao());
      expect(find.byKey(const ValueKey('cartao-reagendamento')), findsNothing);
      expect(find.text('Reagendar'), findsOneWidget);
    });

    testWidgets('erro do backend (ex.: 409) aparece junto da ação e dá para tentar de novo',
        (tester) async {
      final mundo = _Mundo(itens: [_prop()])
        ..falhar = const ErroTrato(TipoErro.recusado, 'Já existe uma proposta pendente.');
      await _abrir(tester, mundo.secao());
      await tester.tap(find.text('Aceitar nova data'));
      await tester.pumpAndSettle();
      expect(find.text('Já existe uma proposta pendente.'), findsOneWidget);
      expect(find.text('Aceitar nova data'), findsOneWidget);

      mundo.falhar = null;
      await tester.tap(find.text('Aceitar nova data'));
      await tester.pumpAndSettle();
      expect(find.text('Já existe uma proposta pendente.'), findsNothing);
      expect(mundo.chamadas, ['aceitar:r1', 'aceitar:r1']);
    });

    testWidgets('falha ao carregar mostra aviso e "Tentar de novo"', (tester) async {
      var falha = true;
      await _abrir(
        tester,
        SecaoReagendamento(
          carregar: () async {
            if (falha) throw ErroTrato.semInternet;
            return const <Reagendamento>[];
          },
          propor: (i, f, m) async {},
          aceitar: (_) async {},
          recusar: (_) async {},
        ),
      );
      expect(find.text('Não foi possível ver as propostas de nova data agora.'), findsOneWidget);
      falha = false;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Reagendar'), findsOneWidget);
    });
  });

  group('Na tela do pedido (cliente)', () {
    PedidoEmExecucao pedido(String estado) => PedidoEmExecucao(
          numero: '#4821',
          titulo: 'Trocar disjuntor',
          etapas: const [],
          fotos: const [],
          estadoApi: estado,
        );

    testWidgets('PedidoExecucaoTela mostra a seção só quando ela é passada', (tester) async {
      await _abrir(
        tester,
        PedidoExecucaoTela(pedido: pedido('agendado'), secaoReagendamento: const Text('secao-x')),
      );
      expect(find.text('secao-x'), findsOneWidget);
      await _abrir(tester, PedidoExecucaoTela(pedido: pedido('agendado')));
      expect(find.text('secao-x'), findsNothing);
    });

    Future<RepositorioPedidosFake> ligar(WidgetTester tester, String estado,
        {List<Reagendamento> itens = const []}) async {
      final pedidos = _PedidosEmEstado(pedido(estado))..reagendamentosFake.addAll(itens);
      final base = repositoriosDemo();
      RotasTrato.repos = RepositoriosTrato(
        pedidos: pedidos,
        orcamentos: base.orcamentos,
        pagamento: base.pagamento,
        chat: base.chat,
        notificacoes: base.notificacoes,
        perfil: base.perfil,
        profissional: base.profissional,
        catalogo: base.catalogo,
        servicos: base.servicos,
        agenda: base.agenda,
      );
      await _abrir(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => RotasTrato.abrirServico(context, 'ped-1'),
            child: const Text('abrir'),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return pedidos;
    }

    testWidgets('pedido agendado: "Reagendar" aparece; proposta pendente vira card com aceitar',
        (tester) async {
      final pedidos = await ligar(tester, 'agendado', itens: [_prop(id: 'r9')]);
      expect(find.text('Nova data proposta'), findsOneWidget);
      await tester.tap(find.text('Aceitar nova data'));
      await tester.pumpAndSettle();
      expect(pedidos.chamadasReagendamento, ['aceitar:r9']);
    });

    testWidgets('pedido pago (pago_e_retido) sem proposta: mostra "Reagendar"', (tester) async {
      await ligar(tester, 'pago_e_retido');
      expect(find.text('Reagendar'), findsOneWidget);
    });

    for (final estado in ['em_andamento', 'em_confirmacao', 'concluido', 'cancelado']) {
      testWidgets('pedido "$estado": sem botão de reagendar', (tester) async {
        await ligar(tester, estado);
        expect(find.text('Reagendar'), findsNothing);
        expect(find.byKey(const ValueKey('cartao-reagendamento')), findsNothing);
      });
    }
  });
}

class _PedidosEmEstado extends RepositorioPedidosFake {
  _PedidosEmEstado(this._pedido);

  final PedidoEmExecucao _pedido;

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => _pedido;
}
