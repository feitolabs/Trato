// Termos 7.7: substituição de pedido cancelado pelo profissional ou por ausência dele.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/componentes/linha_do_tempo.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/modelos_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/pedidos/modelos.dart';
import 'package:trato/telas/pedidos/pedido_execucao_tela.dart';
import 'package:trato/tema/tema.dart';

Map<String, dynamic> _pedidoJson({
  String id = 'ped-orig',
  String estado = 'cancelado',
  String? substituiPedidoId,
}) =>
    {
      'id': id,
      'estado': estado,
      'estado_nome': estado == 'cancelado' ? 'Cancelado' : 'Aberto',
      'cliente_id': 'cli-1',
      'profissional_id': 'prof-1',
      'aberto_em': '2026-11-27T10:00:00Z',
      'concluido_em': null,
      'acoes_permitidas': const <String>[],
      'codigo_inicio': null,
      'codigo_conclusao': null,
      if (substituiPedidoId != null) 'substitui_pedido_id': substituiPedidoId,
    };

PedidoEmExecucao _pedidoCancelado({required bool porProfissional}) => PedidoEmExecucao(
      numero: '#77AA',
      titulo: 'Pedido cancelado',
      estadoApi: 'cancelado',
      canceladoPorProfissional: porProfissional,
      etapas: const [
        EtapaLinhaDoTempo(titulo: 'Contratado', detalhe: '', estado: EstadoEtapa.feita),
      ],
      fotos: const [],
    );

Future<void> _abrir(
  WidgetTester t,
  PedidoEmExecucao pedido, {
  bool comoProfissional = false,
  Future<void> Function()? aoBuscarOutro,
}) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: PedidoExecucaoTela(
      pedido: pedido,
      comoProfissional: comoProfissional,
      aoBuscarOutroProfissional: aoBuscarOutro,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('PedidoApi.deJson mapeia substitui_pedido_id opcional sem quebrar se ausente', () {
    final com = PedidoApi.deJson(_pedidoJson(id: 'ped-novo', substituiPedidoId: 'ped-orig'));
    expect(com.substituiPedidoId, 'ped-orig');

    final sem = PedidoApi.deJson(_pedidoJson(id: 'ped-antigo'));
    expect(sem.substituiPedidoId, isNull);
  });

  test(
      'RepositorioPedidosApi: acompanhar identifica cancelamento pelo profissional e substituir faz POST',
      () async {
    Future<PedidoEmExecucao> carregarComEventos(List<Map<String, dynamic>> eventos) async {
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((req) async {
          if (req.url.path == '/v1/pedidos/ped-orig') {
            return http.Response.bytes(
              utf8.encode(jsonEncode(_pedidoJson(substituiPedidoId: 'ped-anterior'))),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/pedidos/ped-orig/eventos') {
            return http.Response.bytes(
              utf8.encode(jsonEncode(eventos)),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.Response('[]', 404);
        }),
      );
      return RepositorioPedidosApi(api).acompanhar('ped-orig');
    }

    final porDesistencia = await carregarComEventos([
      {
        'acao': 'cancelar',
        'para': 'cancelado',
        'ator_papel': 'profissional',
        'em': '2026-11-27T11:00:00Z',
      },
    ]);
    expect(porDesistencia.canceladoPorProfissional, isTrue);
    expect(porDesistencia.substituiPedidoId, 'ped-anterior');

    final porAusencia = await carregarComEventos([
      {
        'acao': 'registrar_ausencia',
        'para': 'cancelado',
        'ator_papel': 'sistema',
        'em': '2026-11-27T11:00:00Z',
      },
    ]);
    expect(porAusencia.canceladoPorProfissional, isTrue);

    final porCliente = await carregarComEventos([
      {
        'acao': 'cancelar',
        'para': 'cancelado',
        'ator_papel': 'cliente',
        'em': '2026-11-27T11:00:00Z',
      },
    ]);
    expect(porCliente.canceladoPorProfissional, isFalse);

    String? caminhoPost;
    String? corpoPost;
    final apiSub = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        caminhoPost = req.url.path;
        corpoPost = req.body;
        return http.Response.bytes(
          utf8.encode(jsonEncode(
            _pedidoJson(id: 'ped-substituto', estado: 'aberto', substituiPedidoId: 'ped-orig'),
          )),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final novoId = await RepositorioPedidosApi(apiSub).substituir('ped-orig');
    expect(caminhoPost, '/v1/pedidos/ped-orig/substituir');
    expect(corpoPost, isEmpty);
    expect(novoId, 'ped-substituto');
  });

  testWidgets('PedidoExecucaoTela exibe botão para cliente, aciona substituição e trata erro',
      (t) async {
    var chamadas = 0;
    await _abrir(
      t,
      _pedidoCancelado(porProfissional: true),
      aoBuscarOutro: () async {
        chamadas++;
      },
    );
    expect(find.byKey(const ValueKey('buscar-outro-profissional')), findsOneWidget);
    expect(find.text('Buscar outro profissional'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('buscar-outro-profissional')));
    await t.pumpAndSettle();
    expect(chamadas, 1);

    await _abrir(
      t,
      _pedidoCancelado(porProfissional: true),
      aoBuscarOutro: () async => throw const ErroTrato(
        TipoErro.recusado,
        'Só é possível substituir um pedido cancelado pelo profissional ou por ausência dele.',
        codigoHttp: 409,
      ),
    );
    await t.tap(find.byKey(const ValueKey('buscar-outro-profissional')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('erro-substituir-pedido')), findsOneWidget);
    expect(
      find.text(
        'Só é possível substituir um pedido cancelado pelo profissional ou por ausência dele.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'PedidoExecucaoTela oculta botão quando cancelado pelo cliente ou no modo profissional',
      (t) async {
    await _abrir(
      t,
      _pedidoCancelado(porProfissional: false),
      aoBuscarOutro: () async {},
    );
    expect(find.byKey(const ValueKey('buscar-outro-profissional')), findsNothing);

    await _abrir(
      t,
      _pedidoCancelado(porProfissional: true),
      comoProfissional: true,
      aoBuscarOutro: () async {},
    );
    expect(find.byKey(const ValueKey('buscar-outro-profissional')), findsNothing);
  });
}
