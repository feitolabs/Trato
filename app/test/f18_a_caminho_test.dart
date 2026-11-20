import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/profissional_inicio/inicio_profissional_tela.dart';
import 'package:trato/telas/profissional_inicio/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/demo.dart';
import 'apoio/exemplos/telas/profissional_inicio/dados_exemplo.dart';
import 'apoio/fontes.dart';

RepositorioProfissionalApi _repo(
  Future<http.Response> Function(http.Request) resposta,
  List<http.Request> pedidas,
) {
  final cliente = MockClient((req) async {
    pedidas.add(req);
    return resposta(req);
  });
  final sessao = SessaoTrato()..entrar('valor-de-teste');
  return RepositorioProfissionalApi(
    ClienteApi(urlBase: 'https://api.teste/', sessao: sessao, cliente: cliente),
  );
}

http.Response _json(int status, Object corpo) => http.Response.bytes(
      utf8.encode(jsonEncode(corpo)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

InicioProfissional _inicioCom({String? estado, bool emAndamento = false}) => InicioProfissional(
      nome: 'Carlos',
      disponivelAgora: true,
      proximo: ProximoAtendimento(
        pedidoId: 'ped-1',
        quando: 'Hoje · 14h',
        titulo: 'Troca de tomadas',
        endereco: 'Rua A, 10',
        estadoApi: estado,
        emAndamento: emAndamento,
      ),
      carteira: inicioProfissionalExemplo.carteira,
      pedidos: const [],
    );

Future<void> _abrir(WidgetTester tester, Widget tela) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: TemaTrato.claro, home: tela));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(carregarFontesTrato);
  tearDown(() {
    RotasTrato.repos = repositoriosDemo();
    RotasTrato.salvarPdfParaTeste = null;
    RotasTrato.compartilharArquivo = (_) async {};
  });

  group('1. Estou a caminho — rota', () {
    test('POST com eta_minutos; enviado true e false', () async {
      final pedidas = <http.Request>[];
      var enviado = true;
      final repo = _repo(
        (req) async => _json(200, {'pedido_id': 'ped-1', 'enviado': enviado, 'eta_minutos': 30}),
        pedidas,
      );
      final r1 = await repo.avisarACaminho('ped-1', etaMinutos: 30);
      expect(pedidas.single.method, 'POST');
      expect(pedidas.single.url.path, '/v1/profissional/pedidos/ped-1/a-caminho');
      expect(jsonDecode(pedidas.single.body), {'eta_minutos': 30});
      expect(r1.enviado, isTrue);
      expect(r1.etaMinutos, 30);

      enviado = false;
      final r2 = await repo.avisarACaminho('ped-1');
      expect(jsonDecode(pedidas.last.body), isEmpty); // sem escolha, sem eta
      expect(r2.enviado, isFalse);
    });

    test('409 chega como ErroTrato com o código HTTP', () async {
      final repo = _repo((req) async => _json(409, {'detail': 'não agendado'}), []);
      await expectLater(
        repo.avisarACaminho('ped-1'),
        throwsA(isA<ErroTrato>().having((e) => e.codigoHttp, 'codigoHttp', 409)),
      );
    });
  });

  group('1. Estou a caminho — tela', () {
    testWidgets('só aparece com o pedido agendado (e com a ação ligada)', (tester) async {
      Future<AvisoACaminho> ok(String id, int? eta) async => const AvisoACaminho(enviado: true);
      await _abrir(
        tester,
        InicioProfissionalTela(dados: _inicioCom(estado: 'agendado'), aoAvisarACaminho: ok),
      );
      expect(find.text('Estou a caminho'), findsOneWidget);

      await _abrir(
        tester,
        InicioProfissionalTela(dados: _inicioCom(estado: 'pago_e_retido'), aoAvisarACaminho: ok),
      );
      expect(find.text('Estou a caminho'), findsNothing);

      await _abrir(
        tester,
        InicioProfissionalTela(dados: _inicioCom(estado: 'em_andamento', emAndamento: true), aoAvisarACaminho: ok),
      );
      expect(find.text('Estou a caminho'), findsNothing);

      await _abrir(tester, InicioProfissionalTela(dados: _inicioCom(estado: 'agendado')));
      expect(find.text('Estou a caminho'), findsNothing);
    });

    testWidgets('chip de tempo vai no aviso; mensagens de enviado true/false/409/rede',
        (tester) async {
      final chamadas = <(String, int?)>[];
      final respostas = <Object>[
        const AvisoACaminho(enviado: true, etaMinutos: 30),
        const AvisoACaminho(enviado: false),
        const ErroTrato(TipoErro.recusado, 'x', codigoHttp: 409),
        Exception('rede'),
      ];
      await _abrir(
        tester,
        InicioProfissionalTela(
          dados: _inicioCom(estado: 'agendado'),
          aoAvisarACaminho: (id, eta) async {
            chamadas.add((id, eta));
            final r = respostas.removeAt(0);
            if (r is AvisoACaminho) return r;
            throw r;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('eta-30')));
      await tester.pump();
      await tester.tap(find.text('Estou a caminho'));
      await tester.pumpAndSettle();
      expect(chamadas.last, ('ped-1', 30));
      expect(find.text('Aviso enviado ao cliente'), findsOneWidget);

      await tester.tap(find.byKey(const Key('eta-30'))); // desmarca: sem eta
      await tester.pump();
      await tester.tap(find.text('Estou a caminho'));
      await tester.pumpAndSettle();
      expect(chamadas.last, ('ped-1', null));
      expect(find.text('Você já avisou há pouco'), findsOneWidget);

      await tester.tap(find.text('Estou a caminho'));
      await tester.pumpAndSettle();
      expect(find.text('Só dá para avisar em serviço agendado'), findsOneWidget);

      await tester.tap(find.text('Estou a caminho'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Não deu para avisar agora'), findsOneWidget);
      expect(find.text('Estou a caminho'), findsOneWidget); // pode tentar de novo
    });
  });

  group('2. Compartilhar o extrato em PDF', () {
    Future<void> baixar(WidgetTester tester) async {
      RotasTrato.repos = repositoriosDemo();
      RotasTrato.salvarPdfParaTeste = (bytes, arquivo) async => '/tmp/$arquivo';
      await _abrir(tester, RotasTrato.cascaProfissionalParaTeste(abaInicial: 3));
      await tester.tap(find.text('PDF mensal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Baixar PDF'));
      await tester.pumpAndSettle();
    }

    testWidgets('"Compartilhar" chama o plugin com o caminho do arquivo salvo', (tester) async {
      String? caminho;
      RotasTrato.compartilharArquivo = (c) async => caminho = c;
      await baixar(tester);
      expect(find.text('Extrato em PDF salvo.'), findsOneWidget);
      await tester.tap(find.text('Compartilhar'));
      await tester.pumpAndSettle();
      expect(caminho, matches(RegExp(r'^/tmp/trato_extrato_\d{4}_\d{2}\.pdf$')));
    });

    testWidgets('se o compartilhamento falhar, fica só "Extrato em PDF salvo."', (tester) async {
      RotasTrato.compartilharArquivo = (_) async => throw StateError('sem plugin');
      await baixar(tester);
      await tester.tap(find.text('Compartilhar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Extrato em PDF salvo.'), findsOneWidget);
      expect(find.text('Compartilhar'), findsNothing);
    });
  });
}
