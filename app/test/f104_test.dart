// TERMOS-APP6: "Desistir do pedido" (7.2) e a caixa de execução antes dos 7 dias (7.3).
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
import 'package:trato/telas/comuns/textos_dos_termos.dart';
import 'package:trato/telas/desistencia/desistir_tela.dart';
import 'package:trato/telas/desistencia/modelos.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pagamento/modelos.dart';
import 'package:trato/telas/pagamento/pagamento_tela.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
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

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.scrollUntilVisible(alvo, 150, scrollable: find.byType(Scrollable).first);
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

Future<void> _ver(WidgetTester t, Finder alvo) =>
    t.scrollUntilVisible(alvo, 150, scrollable: find.byType(Scrollable).first);

const _integral = SituacaoDesistencia(
  efeito: EfeitoDesistencia.reembolsoIntegral,
  podeDesistir: true,
);

final _comprovante = RegistroDesistencia(
  protocolo: 'DES-123',
  recebidoEm: DateTime(2026, 11, 26, 10, 30),
  situacao: 'reembolso_integral',
  reembolsoCentavos: 10000,
  mensagem: 'Recebemos a sua desistência.',
);

/// API simulada: [respostas] por "MÉTODO caminho" -> (status, corpo).
(ClienteApi, List<(String, Object?, String?)>) _api(Map<String, (int, Object)> respostas) {
  final chamadas = <(String, Object?, String?)>[];
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('t'),
    cliente: MockClient((req) async {
      final chave = '${req.method} ${req.url.path}';
      chamadas.add((
        chave,
        req.body.isEmpty ? null : jsonDecode(req.body),
        req.headers['Idempotency-Key'],
      ));
      final (status, corpo) = respostas[chave] ?? (404, {'detail': 'Not Found'});
      return http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  return (api, chamadas);
}

class _Pedidos extends RepositorioPedidosFake {
  _Pedidos(this.estado, this.situacao);
  final String estado;
  final SituacaoDesistencia? situacao;

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async => PedidoEmExecucao(
        numero: '#AB12',
        titulo: 'Pedido',
        etapas: const [
          EtapaLinhaDoTempo(titulo: 'Contratado', detalhe: '', estado: EstadoEtapa.atual),
        ],
        fotos: const [],
        estadoApi: estado,
        podeVerConclusao: estado == 'em_confirmacao',
      );

  @override
  Future<SituacaoDesistencia?> situacaoDesistencia(String pedidoId) async => situacao;
}

void main() {
  setUpAll(carregarFontesTrato);
  setUp(ligarDemoNosTestes);
  tearDown(() => RotasTrato.repos = repositoriosDemo());

  group('API', () {
    test('lê a situação; 404 é servidor antigo (nulo); outro erro sobe', () async {
      final (api, _) = _api({
        'GET /v1/pedidos/p1/desistencia': (
          200,
          {
            'pode_desistir': true,
            'efeito': 'analise',
            'arrependimento_ate': '2026-12-01T02:59:59Z',
            'consentimento_execucao_imediata': true,
            'registro': null,
          }
        ),
        'GET /v1/pedidos/p3/desistencia': (403, {'detail': 'Só o cliente'}),
      });
      final repo = RepositorioPedidosApi(api);
      final s = await repo.situacaoDesistencia('p1');
      expect(s!.efeito, EfeitoDesistencia.analise);
      expect(s.pediuExecucaoImediata, isTrue);
      expect(s.arrependimentoAte, isNotNull);
      expect(await repo.situacaoDesistencia('p2'), isNull);
      await expectLater(repo.situacaoDesistencia('p3'), throwsA(isA<ErroTrato>()));
      expect(SituacaoDesistencia.deJson(const {'efeito': 'novo'}).efeito,
          EfeitoDesistencia.indisponivel);
    });

    test('desistir manda o motivo só quando há', () async {
      final (api, chamadas) = _api({
        'POST /v1/pedidos/p1/desistir': (
          200,
          {
            'protocolo': 'DES-9',
            'situacao': 'em_analise',
            'recebido_em': '2026-11-26T12:00:00Z',
            'reembolso_centavos': null,
          }
        ),
      });
      final repo = RepositorioPedidosApi(api);
      final r = await repo.desistir('p1', '  ');
      expect((r.protocolo, r.situacao, r.reembolsoCentavos), ('DES-9', 'em_analise', null));
      await repo.desistir('p1', 'Mudei de ideia');
      expect(chamadas.map((c) => c.$2), [
        <String, dynamic>{},
        {'motivo': 'Mudei de ideia'}
      ]);
    });

    for (final metodo in MetodoPagamento.values) {
      test('cobrança ${metodo.name}: o consentimento só vai quando marcado', () async {
        final (api, chamadas) = _api({
          'POST /v1/contratos/p1/cobranca': (201, {'cobranca_id': 'cb1'}),
        });
        final repo = RepositorioPagamentoApi(api);
        await repo.criarCobranca('p1', metodo);
        await repo.criarCobranca('p1', metodo, execucaoImediata: true);
        final sem = chamadas[0].$2! as Map<String, dynamic>;
        final com = chamadas[1].$2! as Map<String, dynamic>;
        expect(sem.containsKey('consentimento_execucao_imediata'), isFalse);
        expect(com['consentimento_execucao_imediata'], isTrue);
        expect(chamadas[0].$3, isNot(chamadas[1].$3));
      });
    }
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final r = '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets('mostra o efeito, confirma e mostra o comprovante ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        final motivos = <String>[];
        var avisou = 0;
        var falhar = true;
        await t.pumpWidget(_app(DesistirTela(
          carregar: () async => _integral,
          desistir: (m) async {
            motivos.add(m);
            if (falhar) {
              throw const ErroTrato(TipoErro.semInternet, 'Sem internet.');
            }
            return _comprovante;
          },
          aoDesistir: () => avisou++,
        )));
        await t.pumpAndSettle();
        expect(find.text('Reembolso integral'), findsOneWidget);
        expect(motivos, isEmpty, reason: 'nada é enviado antes de confirmar');

        final botao = find.byKey(const Key('confirmar-desistencia'));
        await _tocar(t, botao);
        await _ver(t, find.byKey(const Key('erro-desistencia')));
        expect(find.text('Sem internet.'), findsOneWidget);
        expect(avisou, 0);

        falhar = false;
        await _tocar(t, botao);
        await _ver(t, find.byKey(const Key('comprovante-desistencia')));
        for (final texto in ['DES-123', 'Pedido cancelado, com reembolso integral']) {
          expect(find.text(texto, skipOffstage: false), findsOneWidget);
        }
        expect(find.textContaining('26/11/2026', skipOffstage: false), findsOneWidget);
        expect(avisou, 1);
        expect(t.takeException(), isNull);
      });

      testWidgets('análise, indisponível e comprovante já existente ($r)', (t) async {
        await _janela(t, tamanho, fonte);
        Future<void> abrir(SituacaoDesistencia? s) async {
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(_app(DesistirTela(
            carregar: () async => s,
            desistir: (_) async => _comprovante,
          )));
          await t.pumpAndSettle();
        }

        await abrir(const SituacaoDesistencia(
            efeito: EfeitoDesistencia.analise, podeDesistir: true, pediuExecucaoImediata: true));
        expect(find.text('Um analista calcula o reembolso'), findsOneWidget);
        await _ver(t, find.textContaining('proporcional à parte não executada'));

        await abrir(const SituacaoDesistencia(
            efeito: EfeitoDesistencia.indisponivel, motivoIndisponivel: 'Já foi concluído.'));
        expect(find.text('Já foi concluído.'), findsOneWidget);
        expect(find.byKey(const Key('confirmar-desistencia')), findsNothing);

        await abrir(SituacaoDesistencia(
            efeito: EfeitoDesistencia.indisponivel, registro: _comprovante));
        expect(find.byKey(const Key('comprovante-desistencia')), findsOneWidget);
        expect(find.byKey(const Key('confirmar-desistencia')), findsNothing);

        // O servidor ainda deixa desistir: o registro antigo não esconde o formulário.
        await abrir(SituacaoDesistencia(
            efeito: EfeitoDesistencia.reembolsoIntegral,
            podeDesistir: true,
            registro: _comprovante));
        expect(find.byKey(const Key('comprovante-desistencia')), findsNothing);
        await _ver(t, find.byKey(const Key('confirmar-desistencia')));

        await abrir(null);
        expect(find.byKey(const Key('desistencia-indisponivel')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('pagamento: caixa desmarcada, com explicação, e avisa ao marcar ($r)',
          (t) async {
        await _janela(t, tamanho, fonte);
        final marcas = <bool>[];
        final dados = await RepositorioPagamentoFake().dados('p1');
        await t.pumpWidget(_app(PagamentoTela(
          dados: dados,
          aoMarcarExecucaoImediata: marcas.add,
        )));
        await t.pumpAndSettle();
        final caixa = find.byKey(const Key('execucao-imediata'));
        await _ver(t, caixa);
        expect(t.widget<CheckboxListTile>(caixa).value, isFalse);
        expect(find.text(textoExecucaoImediata, skipOffstage: false), findsOneWidget);
        await t.ensureVisible(caixa);
        await t.pumpAndSettle();
        await t.tap(find.descendant(of: caixa, matching: find.byType(Checkbox)));
        await t.pumpAndSettle();
        expect(marcas, [true]);
        expect(t.widget<CheckboxListTile>(caixa).value, isTrue);
        expect(t.takeException(), isNull);
      });
    }
  }

  group('no pedido contratado', () {
    Future<void> abrir(WidgetTester t, String estado, SituacaoDesistencia? s) async {
      await _janela(t, const Size(390, 1600), 1);
      RotasTrato.repos = repositoriosDemo(pedidos: _Pedidos(estado, s));
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

    final link = find.byKey(const ValueKey('desistir-do-pedido'));

    testWidgets('servidor com a rota: "Desistir do pedido" no lugar de cancelar', (t) async {
      await abrir(t, 'agendado', _integral);
      expect(find.text('Cancelar pedido'), findsNothing);
      await _tocar(t, link);
      expect(find.byType(DesistirTela), findsOneWidget);
      expect(find.text('Reembolso integral'), findsOneWidget);
    });

    testWidgets('servidor antigo (404): continua "Cancelar pedido"', (t) async {
      await abrir(t, 'agendado', null);
      expect(link, findsNothing);
      await _ver(t, find.text('Cancelar pedido'));
    });

    testWidgets('em confirmação também dá para desistir', (t) async {
      await abrir(t, 'em_confirmacao',
          const SituacaoDesistencia(efeito: EfeitoDesistencia.analise, podeDesistir: true));
      await _ver(t, link);
      expect(find.text('Desistir do pedido'), findsOneWidget);
    });

    testWidgets('com registro: link para o comprovante, mesmo cancelado', (t) async {
      await abrir(t, 'cancelado',
          SituacaoDesistencia(efeito: EfeitoDesistencia.indisponivel, registro: _comprovante));
      await _ver(t, find.text('Ver comprovante da desistência'));
      expect(find.text('Cancelar pedido'), findsNothing);
    });

    testWidgets('concluído sem registro: nenhum dos dois', (t) async {
      await abrir(t, 'concluido',
          const SituacaoDesistencia(efeito: EfeitoDesistencia.indisponivel));
      expect(link, findsNothing);
      expect(find.text('Cancelar pedido'), findsNothing);
    });
  });
}
