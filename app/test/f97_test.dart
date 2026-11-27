import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/componentes/linha_do_tempo.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/repositorios_catalogo_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/agenda/agenda_tela.dart';
import 'package:trato/telas/agenda/modelos.dart';
import 'package:trato/telas/fluxo/navegacao_casca.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/mensagens/mensagens_tela.dart';
import 'package:trato/telas/mensagens/modelos.dart';
import 'package:trato/telas/mensagens/servico_estado.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/entrar.dart';
import 'apoio/exemplos/auth/servico_auth_fake.dart';
import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/perfil_publico/perfil_publico_fake.dart';
import 'apoio/exemplos/telas/profissional_inicio/dados_exemplo.dart';
import 'apoio/fontes.dart';

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];

Future<void> _janela(WidgetTester t, Size tamanho, double fonte) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = fonte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget tela) => MaterialApp(
      theme: TemaTrato.claro,
      builder: (c, f) => EscalaFonteLimitada(child: f!),
      home: tela,
    );

PedidoContratado _contratado(String estado, {bool jaAvaliou = false}) =>
    PedidoContratado(
      pedidoId: 'ped-cca5',
      titulo: 'Pedido #CCA5',
      situacao: 'x',
      estadoApi: estado,
      cliente: 'Ana S.',
      jaAvaliou: jaAvaliou,
    );

/// O início do profissional com os finalizados que o teste quer.
class _ProfissionalComFinalizados extends RepositorioProfissionalFake {
  _ProfissionalComFinalizados(this.finalizados);
  final List<PedidoContratado> finalizados;

  @override
  Future<InicioProfissional> inicio() async => InicioProfissional(
        nome: 'Carlos',
        disponivelAgora: true,
        carteira: inicioProfissionalExemplo.carteira,
        pedidos: const [],
        finalizados: finalizados,
      );
}

class _PedidoConcluido extends RepositorioPedidosFake {
  _PedidoConcluido({this.jaAvaliou = false});
  final bool jaAvaliou;

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async =>
      PedidoEmExecucao(
        numero: '#CCA5',
        titulo: 'Serviço finalizado',
        etapas: const [
          EtapaLinhaDoTempo(
              titulo: 'Finalizado', detalhe: '', estado: EstadoEtapa.feita),
        ],
        fotos: const [],
        estadoApi: 'concluido',
        jaAvaliou: jaAvaliou,
        podeVerConclusao: false,
      );
}

ServicoMensagens _conversas({bool contratado = true}) => _Conversas([
      ConversaResumo(
        pedidoId: 'ped-cca5',
        tituloPedido: 'Troca de chuveiro',
        interlocutor: 'Ana S.',
        iniciais: 'AS',
        ultimaMensagem: 'Obrigada!',
        quando: 'ontem',
        contratado: contratado,
      ),
      const ConversaResumo(
        pedidoId: 'ped-vivo',
        tituloPedido: 'Pintura',
        interlocutor: 'Paulo R.',
        iniciais: 'PR',
        ultimaMensagem: 'Pode vir amanhã',
        quando: '10h',
        contratado: true,
      ),
    ]);

class _Conversas implements ServicoMensagens {
  _Conversas(this.itens);
  final List<ConversaResumo> itens;
  @override
  Future<List<ConversaResumo>> listar() async => itens;
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('1. Finalizados do profissional (P09)', () {
    Future<void> abrirPedidos(WidgetTester t, RepositorioProfissionalFake prof,
        {RepositorioPedidosFake? pedidos}) async {
      final auth = ServicoAuthFake();
      await entrarNaContaDeTeste(auth, email: 'carlos@exemplo.com');
      ServicoAuthPadrao.atual = auth;
      RotasTrato.repos = repositoriosDemo(profissional: prof, pedidos: pedidos);
      (RotasTrato.repos.perfilPublico! as ServicoPerfilPublicoFake)
          .definirTemPerfil(true);
      late BuildContext ctx;
      await t.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      await RotasTrato.irParaProfissional(ctx);
      await t.pumpAndSettle();
      ControladorCasca.selecionarAba(1); // Pedidos
      await t.pumpAndSettle();
    }

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

        testWidgets(
            'concluído aparece em Finalizados, abre e mostra "Avaliar cliente" ($r)',
            (t) async {
          await _janela(t, tamanho, fonte);
          await abrirPedidos(
            t,
            _ProfissionalComFinalizados([_contratado('concluido')]),
            pedidos: _PedidoConcluido(),
          );
          await t.ensureVisible(find.byKey(const Key('aba-finalizados')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('aba-finalizados')));
          await t.pumpAndSettle();
          expect(find.text('Finalizados (1)'), findsOneWidget);
          expect(find.text('Pedido #CCA5'), findsOneWidget);
          expect(find.text('Concluído'), findsOneWidget);
          expect(find.byKey(const ValueKey('avaliar-cliente-na-lista')),
              findsOneWidget);
          await t.tap(find.byKey(const ValueKey('finalizado-ped-cca5')));
          await t.pumpAndSettle();
          expect(find.byType(PedidoExecucaoTela), findsOneWidget);
          expect(find.widgetWithText(FilledButton, 'Avaliar cliente'),
              findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets('já avaliou: sem destaque na lista e o botão some ($r)',
            (t) async {
          await _janela(t, tamanho, fonte);
          await abrirPedidos(
            t,
            _ProfissionalComFinalizados(
                [_contratado('concluido', jaAvaliou: true)]),
            pedidos: _PedidoConcluido(jaAvaliou: true),
          );
          await t.ensureVisible(find.byKey(const Key('aba-finalizados')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('aba-finalizados')));
          await t.pumpAndSettle();
          expect(find.byKey(const ValueKey('avaliar-cliente-na-lista')),
              findsNothing);
          expect(find.text('Cliente avaliado'), findsOneWidget);
          await t.tap(find.byKey(const ValueKey('finalizado-ped-cca5')));
          await t.pumpAndSettle();
          expect(find.widgetWithText(FilledButton, 'Avaliar cliente'),
              findsNothing);
        });
      }
    }

    testWidgets(
        'cancelado entra em Finalizados como "Cancelado", sem pedir avaliação',
        (t) async {
      await _janela(t, _tamanhos.first, 1);
      await abrirPedidos(
          t, _ProfissionalComFinalizados([_contratado('cancelado')]));
      await t.ensureVisible(find.byKey(const Key('aba-finalizados')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('aba-finalizados')));
      await t.pumpAndSettle();
      expect(find.text('Cancelado'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('avaliar-cliente-na-lista')), findsNothing);
    });

    testWidgets('sem finalizados: estado vazio', (t) async {
      await _janela(t, _tamanhos.first, 1);
      await abrirPedidos(t, _ProfissionalComFinalizados(const []));
      await t.ensureVisible(find.byKey(const Key('aba-finalizados')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('aba-finalizados')));
      await t.pumpAndSettle();
      expect(find.text('Nenhum pedido finalizado'), findsOneWidget);
    });

    test(
        'a API separa concluídos e cancelados dos em andamento (GET /v1/pedidos?como=profissional)',
        () async {
      Map<String, dynamic> pedido(String id, String estado,
              {bool avaliou = false}) =>
          {
            'id': id,
            'cliente_id': 'cli-1',
            'estado': estado,
            'estado_nome': estado,
            'ja_avaliou': avaliou,
            'aberto_em': '2026-11-20T10:00:00Z',
            'acoes_permitidas': <String>[],
          };
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((req) async {
          final corpo = switch (req.url.path) {
            '/v1/pedidos' => [
                pedido('p-concluido', 'concluido'),
                pedido('p-cancelado', 'cancelado'),
                pedido('p-agendado', 'agendado'),
              ],
            '/v1/me' => {'id': 'pro-1', 'nome': 'Carlos Lima'},
            _ => <String, dynamic>{},
          };
          return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200,
              headers: const {
                'content-type': 'application/json; charset=utf-8'
              });
        }),
      );
      final repo = RepositorioProfissionalApi(api);
      final estados = await repo.estadosDosPedidos();
      expect(estados, {
        'p-concluido': 'concluido',
        'p-cancelado': 'cancelado',
        'p-agendado': 'agendado',
      });
      final inicio = await repo.inicio();
      expect(inicio.finalizados.map((c) => c.estadoApi),
          containsAll(['concluido', 'cancelado']));
      expect(inicio.finalizados.length, 2);
      expect(
          inicio.finalizados
              .firstWhere((c) => c.estadoApi == 'concluido')
              .situacao,
          'Concluído');
      expect(inicio.contratados.map((c) => c.pedidoId), ['p-agendado']);
    });
  });

  group('2. Agenda: pago sem data (P13)', () {
    Agendamento ag(String estadoApi, {bool semData = true}) => Agendamento(
          id: 'a1',
          pedidoId: 'ped-1',
          dia: DateTime(2026, 11, 25),
          horario:
              semData ? 'Data da visita ainda não marcada' : 'Qui, 14h às 16h',
          titulo: 'Troca de chuveiro',
          local: 'Rua das Acácias, 120',
          semData: semData,
          estadoApi: estadoApi,
        );

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

        testWidgets(
            'pago_e_retido: "Pago · marque a data", sem "Fazer check-in" ($r)',
            (t) async {
          await _janela(t, tamanho, fonte);
          Agendamento? tocado;
          await t.pumpWidget(_app(Scaffold(
            body: AgendaTela(
              carregar: () async => [ag('pago_e_retido')],
              aoFazerCheckIn: (a) => tocado = a,
              hoje: DateTime(2026, 11, 25),
            ),
          )));
          await t.pumpAndSettle();
          expect(find.text('Pago · marque a data'), findsOneWidget);
          expect(find.text('Agendado'), findsNothing);
          expect(find.text('Fazer check-in'), findsNothing);
          await t.scrollUntilVisible(
              find.byKey(const ValueKey('marcar-data-agenda')), 200,
              scrollable: find.byType(Scrollable).first);
          await t.tap(find.byKey(const ValueKey('marcar-data-agenda')));
          expect(tocado?.pedidoId, 'ped-1',
              reason: 'abre as ações, onde se marca a data');
          expect(t.takeException(), isNull);
        });

        testWidgets('agendado com data continua com "Fazer check-in" ($r)',
            (t) async {
          await _janela(t, tamanho, fonte);
          await t.pumpWidget(_app(Scaffold(
            body: AgendaTela(
              carregar: () async => [ag('agendado', semData: false)],
              aoFazerCheckIn: (_) {},
              hoje: DateTime(2026, 11, 25),
            ),
          )));
          await t.pumpAndSettle();
          expect(find.text('Agendado'), findsOneWidget);
          await t.scrollUntilVisible(find.text('Fazer check-in'), 200,
              scrollable: find.byType(Scrollable).first);
          expect(find.text('Fazer check-in'), findsOneWidget);
        });
      }
    }

    test('a Agenda herda o estado do pedido (mesma fonte da lista de Pedidos)',
        () async {
      final prof = _ProfissionalComContratado(const PedidoContratado(
        pedidoId: 'ped-1',
        titulo: 'Pedido #AB12',
        situacao: 'Pago · marque a data da visita',
        estadoApi: 'pago_e_retido',
      ));
      final lista = await RepositorioAgendaApi(prof).listar();
      expect(lista.single.estadoApi, 'pago_e_retido');
      expect(lista.single.aguardandoData, isTrue);
      expect(lista.single.podeFazerCheckIn, isFalse);
    });
  });

  group('3. Conversas com o estado real (P14)', () {
    test('concluído vira "Concluído"; sem estado, fica como veio', () async {
      final s = ServicoMensagensComEstado(
        _conversas(),
        () async => {'ped-cca5': 'concluido', 'ped-vivo': 'em_andamento'},
      );
      final r = await s.listar();
      expect(r.first.estadoEfetivo, 'Concluído');
      expect(r.last.estadoEfetivo, 'Em andamento');
    });

    test('cancelado, retrabalho e falha ao ler os estados', () async {
      final r = await ServicoMensagensComEstado(
        _conversas(),
        () async => {'ped-cca5': 'cancelado', 'ped-vivo': 'retrabalho'},
      ).listar();
      expect(r.first.estadoEfetivo, 'Cancelado');
      expect(r.last.estadoEfetivo, 'Retrabalho');
      final falhou = await ServicoMensagensComEstado(
        _conversas(),
        () async => throw Exception('sem rede'),
      ).listar();
      expect(falhou.first.estadoEfetivo, 'Em andamento',
          reason: 'segue como veio');
    });

    for (final tamanho in _tamanhos) {
      for (final fonte in _fontes) {
        testWidgets(
            'a lista mostra "Concluído" no pedido concluído '
            '(${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte)',
            (t) async {
          await _janela(t, tamanho, fonte);
          await t.pumpWidget(_app(Scaffold(
            body: ListaConversas(
              servico: ServicoMensagensComEstado(
                _conversas(),
                () async => {'ped-cca5': 'concluido'},
              ),
            ),
          )));
          await t.pumpAndSettle();
          expect(find.text('Concluído'), findsWidgets);
          expect(find.text('Em andamento'), findsWidgets,
              reason: 'o outro pedido segue vivo');
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}

class _ProfissionalComContratado extends RepositorioProfissionalFake {
  _ProfissionalComContratado(this.contratado);
  final PedidoContratado contratado;

  @override
  Future<InicioProfissional> inicio() async => InicioProfissional(
        nome: 'Carlos',
        disponivelAgora: true,
        carteira: inicioProfissionalExemplo.carteira,
        pedidos: const [],
        contratados: [contratado],
      );
}
