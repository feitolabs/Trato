import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/tema/tema.dart';

import 'apoio/exemplos/dados/repositorios_fake.dart';
import 'apoio/exemplos/demo.dart';
import 'apoio/fontes.dart';

final _inicio = DateTime(2030, 3, 14, 14);
const _aguardando = 'Aguardando a outra parte aceitar';
const _msg409 =
    'Para mudar a data, envie uma proposta de reagendamento; a outra parte precisa aceitar.';

class _Chamada {
  _Chamada(this.metodo, this.caminho, this.corpo);
  final String metodo;
  final String caminho;
  final Map<String, dynamic>? corpo;
}

/// Pedidos pela API de verdade, com HTTP simulado: dá para ver QUAIS rotas o app chama.
RepositorioPedidosApi _apiDePedidos(List<_Chamada> log, {int status = 200}) {
  final api = ClienteApi(
    urlBase: 'https://api.teste',
    sessao: SessaoTrato()..entrar('valor-de-teste'),
    cliente: MockClient((req) async {
      log.add(_Chamada(
          req.method,
          req.url.path,
          req.body.isEmpty
              ? null
              : jsonDecode(req.body) as Map<String, dynamic>));
      return http.Response.bytes(
        utf8.encode(
            jsonEncode(status == 200 ? {'ok': true} : {'detail': _msg409})),
        status,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return RepositorioPedidosApi(api);
}

class _PedidoAgendado extends RepositorioPedidosFake {
  _PedidoAgendado({this.erro});
  final ErroTrato? erro;

  @override
  Future<PedidoEmExecucao> acompanhar(String pedidoId) async =>
      const PedidoEmExecucao(
        numero: '#4821',
        titulo: 'Troca de chuveiro',
        etapas: [],
        fotos: [],
        estadoApi: 'agendado',
        visita: 'Qui, 03/12 · 14h às 16h',
        profissionalNome: 'Carlos Lima',
        podeVerConclusao: false,
      );

  @override
  Future<void> proporReagendamento(String pedidoId,
      {required DateTime inicio, required DateTime fim, String? motivo}) {
    if (erro != null) throw erro!;
    return super.proporReagendamento(pedidoId,
        inicio: inicio, fim: fim, motivo: motivo);
  }
}

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

const _tamanhos = [Size(390, 844), Size(320, 568)];
const _fontes = [1.0, 1.3];

void main() {
  setUpAll(carregarFontesTrato);
  setUp(() {
    ligarDemoNosTestes();
    RotasTrato.escolherJanelaParaTeste = (_) async => _inicio;
  });
  tearDown(() {
    RotasTrato.escolherJanelaParaTeste = null;
    RotasTrato.repos = repositoriosDemo();
  });

  test('o app não tem mais nenhum caminho para /acoes/remarcar', () {
    final achados = <String>[];
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final t = f.readAsStringSync();
      if (t.contains('acoes/remarcar') || t.contains('remarcarAgenda')) {
        achados.add(f.path);
      }
    }
    expect(achados, isEmpty);
  });

  for (final tamanho in _tamanhos) {
    for (final fonte in _fontes) {
      final rotulo =
          '${tamanho.width.toInt()}x${tamanho.height.toInt()} x$fonte';

      testWidgets(
          'PROFISSIONAL remarca: vira proposta e nunca chama /acoes/remarcar ($rotulo)',
          (t) async {
        await _janela(t, tamanho, fonte);
        final log = <_Chamada>[];
        RotasTrato.repos = repositoriosDemo(pedidos: _apiDePedidos(log));
        late BuildContext ctx;
        await t.pumpWidget(_app(Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }))));
        final f = RotasTrato.marcarVisitaParaTeste(ctx, 'p1', remarcar: true);
        await t.pumpAndSettle();
        await f;
        expect(log.map((c) => '${c.metodo} ${c.caminho}'),
            ['POST /v1/pedidos/p1/reagendamentos']);
        expect(log.single.corpo!.keys,
            containsAll(['nova_janela_inicio', 'nova_janela_fim']));
        expect(log.any((c) => c.caminho.contains('remarcar')), isFalse);
        expect(find.textContaining(_aguardando), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets(
          'CLIENTE remarca pelo pedido agendado: vira proposta ($rotulo)',
          (t) async {
        await _janela(t, tamanho, fonte);
        final pedidos = _PedidoAgendado();
        RotasTrato.repos = repositoriosDemo(pedidos: pedidos);
        late BuildContext ctx;
        await t.pumpWidget(_app(Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        })));
        RotasTrato.abrirServico(ctx, 'p1');
        await t.pumpAndSettle();
        final botao = find.text('Remarcar visita');
        await t.scrollUntilVisible(botao, 200,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        await t.tap(botao);
        await t.pumpAndSettle();
        expect(pedidos.chamadasReagendamento, contains('propor'));
        expect(find.textContaining(_aguardando), findsOneWidget);
        expect(
            find.textContaining('Visita remarcada com sucesso'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('servidor antigo/novo responde 409: o texto dele aparece',
      (t) async {
    await _janela(t, _tamanhos.first, 1);
    final log = <_Chamada>[];
    RotasTrato.repos =
        repositoriosDemo(pedidos: _apiDePedidos(log, status: 409));
    late BuildContext ctx;
    await t.pumpWidget(_app(Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }))));
    final f = RotasTrato.marcarVisitaParaTeste(ctx, 'p1', remarcar: true);
    await t.pumpAndSettle();
    await f;
    expect(find.textContaining('Para mudar a data, envie uma proposta'),
        findsOneWidget);
    expect(find.textContaining(_aguardando), findsNothing,
        reason: 'não finge que deu certo');
    expect(t.takeException(), isNull);
  });

  testWidgets('cliente: 409 mostra o texto do servidor, sem dizer que remarcou',
      (t) async {
    await _janela(t, _tamanhos.first, 1);
    RotasTrato.repos = repositoriosDemo(
      pedidos: _PedidoAgendado(
          erro: const ErroTrato(TipoErro.recusado, _msg409, codigoHttp: 409)),
    );
    late BuildContext ctx;
    await t.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    })));
    RotasTrato.abrirServico(ctx, 'p1');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Remarcar visita'), 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Remarcar visita'));
    await t.pumpAndSettle();
    expect(find.textContaining('Para mudar a data, envie uma proposta'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
