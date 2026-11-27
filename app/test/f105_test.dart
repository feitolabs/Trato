// TERMOS-APP7: cliente ausente (Termos 7.6), dos dois lados.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/linha_do_tempo.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/ausencia/ausencia_tela.dart';
import 'package:trato/telas/ausencia/modelos.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/profissional/check_in_tela.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/profissional/servico_check_in_fake.dart';
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

Widget _app(Widget tela) => MaterialApp(theme: TemaTrato.claro, home: tela);

Future<void> _ver(WidgetTester t, Finder alvo) =>
    t.scrollUntilVisible(alvo, 150, scrollable: find.byType(Scrollable).first);

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await _ver(t, alvo);
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

CasoAusencia _caso(String status, {DateTime? libera, String? decisao, int? retencao, String? c}) =>
    CasoAusencia(
      status: status,
      chegadaEm: DateTime(2026, 11, 26, 14),
      podeRegistrarEm: libera,
      justificativaAte: DateTime(2026, 11, 27, 14, 20),
      decisao: decisao,
      retencaoCentavos: retencao,
      retencaoJustificativa: retencao == null ? null : 'Deslocamento já realizado.',
      comprovantesDaRetencao: retencao == null ? 0 : 1,
      cancelamentoStatus: c,
    );

/// Check-in com a chegada do servidor novo ([semRota] = servidor antigo).
class _Chegada extends ServicoCheckInFake implements ServicoChegadaAusencia {
  _Chegada({this.semRota = false});
  final bool semRota;
  CasoAusencia? caso;
  var chegadas = 0;
  var registros = 0;
  var cedo = true;

  @override
  Future<CasoAusencia?> casoDeAusencia() async => caso;

  @override
  Future<CasoAusencia?> registrarChegada() async {
    chegadas++;
    if (semRota) return null;
    return caso = _caso('aguardando_espera',
        libera: DateTime.now().add(const Duration(minutes: 20)));
  }

  @override
  Future<void> avisarClienteAusente() async {
    if (cedo && !semRota) {
      throw const ErroTrato(TipoErro.recusado, 'Espere mais 20 min pelo cliente antes de registrar.',
          codigoHttp: 409);
    }
    registros++;
    if (caso != null) caso = _caso('aguardando_justificativa');
  }
}

class _Pedidos extends RepositorioPedidosFake {
  _Pedidos(this.caso);
  CasoAusencia? caso;
  final enviadas = <(String, List<String>)>[];

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => const PedidoEmExecucao(
        numero: '#AB12',
        titulo: 'Visita marcada',
        etapas: [
          EtapaLinhaDoTempo(titulo: 'Contratado', detalhe: '', estado: EstadoEtapa.atual),
        ],
        fotos: [],
        estadoApi: 'agendado',
      );

  @override
  Future<CasoAusencia?> casoDeAusencia(String pedidoId) async => caso;

  @override
  Future<CasoAusencia> justificarAusencia(
      String pedidoId, String texto, List<String> fotos) async {
    enviadas.add((texto, fotos));
    return caso = CasoAusencia(status: 'em_analise', justificativaTexto: texto);
  }
}

(ClienteApi, List<(String, Object?)>) _api(Map<String, (int, Object)> respostas) {
  final chamadas = <(String, Object?)>[];
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((req) async {
      final chave = '${req.method} ${req.url.path}';
      chamadas.add((chave, req.body.isEmpty ? null : jsonDecode(req.body)));
      final (status, corpo) = respostas[chave] ?? (404, {'detail': 'Not Found'});
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  return (api, chamadas);
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('API', () {
    test('lê o caso; 404 e 503 são "sem registro"; outro erro sobe', () async {
      final (api, _) = _api({
        'GET /v1/pedidos/p1/ausencia': (
          200,
          {
            'status': 'em_analise',
            'chegada_em': '2026-11-26T17:00:00Z',
            'anexos': ['a', 'b'],
            'retencao_centavos': 3000,
            'cancelamento_status': 'proposta_retencao_enviada',
          }
        ),
        'GET /v1/pedidos/p3/ausencia': (503, {'detail': 'indisponível'}),
        'GET /v1/pedidos/p4/ausencia': (403, {'detail': 'não'}),
      });
      final repo = RepositorioPedidosApi(api);
      final caso = await repo.casoDeAusencia('p1');
      expect((caso!.status, caso.anexos, caso.retencaoCentavos), ('em_analise', 2, 3000));
      expect(await repo.casoDeAusencia('p2'), isNull);
      expect(await repo.casoDeAusencia('p3'), isNull);
      await expectLater(repo.casoDeAusencia('p4'), throwsA(isA<ErroTrato>()));
    });

    test('justificativa manda texto e anexos; chegada remota manda corpo vazio', () async {
      final (api, chamadas) = _api({
        'POST /v1/pedidos/p1/ausencia/justificativa': (200, {'status': 'em_analise'}),
        'POST /v1/pedidos/p1/ausencia/chegada': (200, {'status': 'aguardando_espera'}),
        'POST /v1/pedidos/p2/ausencia/chegada': (503, {'detail': 'indisponível'}),
      });
      await RepositorioPedidosApi(api).justificarAusencia('p1', ' Estava no hospital ', const []);
      expect(chamadas.last.$2, {'texto': 'Estava no hospital', 'anexos': <Object?>[]});

      ServicoChegadaAusencia servico(String id) =>
          RepositorioProfissionalApi(api).servicoCheckIn(id, remoto: true)
              as ServicoChegadaAusencia;
      expect((await servico('p1').registrarChegada())!.esperando, isTrue);
      expect(chamadas.last.$2, <String, dynamic>{});
      expect(await servico('p2').registrarChegada(), isNull);
      expect(await servico('p9').registrarChegada(), isNull, reason: '404: servidor antigo');
    });

    test('os avisos novos abrem o pedido', () {
      for (final evento in [
        'pagamento.ausencia_justificar',
        'pagamento.ausencia_decidida',
        'pagamento.desistencia',
      ]) {
        final link = resultadoDoPush(
            {'evento': evento, 'tela': 'pedido', 'pedido_id': 'p1', 'papel': 'cliente'});
        expect(link, const ResultadoLink.valido(DestinoApp.pedido, 'p1', papel: 'cliente'));
        expect(tipoDaNotificacao(evento), TipoNotificacao.pagamento);
      }
    });
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('profissional: chegada, contagem, 409 junto do botão e registro ($r)',
          (t) async {
        await _janela(t, tamanho, fonte);
        final s = _Chegada();
        await t.pumpWidget(_app(CheckInTela(servico: s, tituloBarra: 'Pedido')));
        await t.pumpAndSettle();
        await _tocar(t, find.byKey(const Key('cliente-ausente')));
        expect(s.chegadas, 1);
        expect(s.registros, 0);
        await _ver(t, find.byKey(const Key('contagem-ausencia')));
        expect(find.textContaining(RegExp(r'Falta (19|20):\d\d')), findsOneWidget);

        Future<void> registrar() async {
          await _tocar(t, find.byKey(const Key('registrar-cliente-ausente')));
          await t.tap(find.text('Confirmar ausência'));
          await t.pumpAndSettle();
        }

        await registrar();
        await _ver(t, find.byKey(const Key('erro-ausencia')));
        expect(find.textContaining('Espere mais 20 min'), findsOneWidget);

        s.cedo = false;
        await registrar();
        expect(s.registros, 1);
        await _ver(t, find.text('Aguardando a justificativa do cliente'));
        expect(find.byKey(const Key('registrar-cliente-ausente')), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });

      testWidgets('profissional, servidor antigo: fluxo de antes ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final s = _Chegada(semRota: true);
        await t.pumpWidget(_app(CheckInTela(servico: s, tituloBarra: 'Pedido')));
        await t.pumpAndSettle();
        await _tocar(t, find.byKey(const Key('cliente-ausente')));
        await t.tap(find.text('Confirmar ausência'));
        await t.pumpAndSettle();
        expect(s.registros, 1);
        expect(find.byKey(const Key('espera-ausencia')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('cliente: prazo, envio da justificativa e acompanhamento ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final repo = _Pedidos(_caso('aguardando_justificativa'));
        var avisos = 0;
        await t.pumpWidget(_app(AusenciaTela(
          carregar: () => repo.casoDeAusencia('p1'),
          profissional: false,
          enviar: (texto, fotos) => repo.justificarAusencia('p1', texto, fotos),
          capturarFoto: () async => 'foto.jpg',
          aoEnviar: () => avisos++,
        )));
        await t.pumpAndSettle();
        expect(find.textContaining('Prazo: até 27/11'), findsOneWidget);
        final enviar = find.byKey(const Key('enviar-justificativa'));
        await _tocar(t, enviar);
        await _ver(t, find.byKey(const Key('erro-justificativa')));
        expect(repo.enviadas, isEmpty);

        await _ver(t, find.byKey(const Key('texto-justificativa')));
        await t.enterText(find.byKey(const Key('texto-justificativa')), 'Estava no hospital');
        await _tocar(t, find.byKey(const Key('anexar-foto-justificativa')));
        await _tocar(t, enviar);
        expect(repo.enviadas.single.$1, 'Estava no hospital');
        expect(repo.enviadas.single.$2, ['foto.jpg']);
        expect(find.text('Justificativa em análise'), findsOneWidget);
        expect(enviar, findsNothing);
        expect(avisos, 1);
        expect(t.takeException(), isNull);
      });

      testWidgets('decisão e retenção aparecem para os dois ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final caso = _caso('justificativa_recusada',
            decisao: 'Sem comprovação.', retencao: 3000, c: 'proposta_retencao_enviada');
        for (final profissional in [false, true]) {
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(_app(AusenciaTela(
              carregar: () async => caso, profissional: profissional)));
          await t.pumpAndSettle();
          expect(find.textContaining('Decisão do analista: Sem comprovação.'), findsOneWidget);
          await _ver(t, find.byKey(const Key('retencao-ausencia')));
          expect(find.textContaining('ainda não cobrada'), findsOneWidget);
          await _ver(t, find.textContaining('Deslocamento já realizado.'));
          expect(find.byKey(const Key('enviar-justificativa')), findsNothing);
        }
        expect(t.takeException(), isNull);
      });
    }
  }

  group('no pedido', () {
    Future<void> abrir(WidgetTester t, _Pedidos repo) async {
      await _janela(t, const Size(390, 1600), 1);
      RotasTrato.repos = repositoriosDemo(pedidos: repo);
      await t.pumpWidget(_app(Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => RotasTrato.abrirServico(c, 'ped-1'),
            child: const Text('abrir'),
          ),
        ),
      )));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
    }

    testWidgets('cliente vê o aviso com o prazo e abre o envio', (t) async {
      await abrir(t, _Pedidos(_caso('aguardando_justificativa')));
      await _ver(t, find.byKey(const Key('cartao-ausencia')));
      expect(find.textContaining('Prazo: até 27/11'), findsOneWidget);
      await _tocar(t, find.byKey(const Key('abrir-ausencia')));
      expect(find.byType(AusenciaTela), findsOneWidget);
      expect(find.byKey(const Key('texto-justificativa')), findsOneWidget);
    });

    testWidgets('sem registro (ou servidor antigo): nada muda', (t) async {
      await abrir(t, _Pedidos(null));
      expect(find.byKey(const Key('cartao-ausencia')), findsNothing);
    });
  });
}
