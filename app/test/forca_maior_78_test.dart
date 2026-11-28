// Termos 7.8 e 22.6: solicitação e acompanhamento de evento externo (força maior).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/pedidos/forca_maior.dart';
import 'package:trato/telas/pedidos/secao_forca_maior.dart';
import 'package:trato/tema/tema.dart';

EventoForcaMaior _evento({
  String id = 'fm-1',
  String acao = 'reagendar',
  String status = 'pendente',
  String descricao = 'Enchente impediu o acesso ao endereço combinado.',
  String? justificativa,
}) =>
    EventoForcaMaior(
      id: id,
      pedidoId: 'ped-78',
      solicitanteId: 'cli-1',
      solicitantePapel: 'cliente',
      acaoSolicitada: acao,
      descricao: descricao,
      status: status,
      criadoEm: DateTime.utc(2026, 11, 27, 12),
      justificativaDecisao: justificativa,
    );

class _ServicoFake implements ServicoForcaMaior {
  _ServicoFake(this.itens, {this.falharListar = false, this.erroSolicitar});

  final List<EventoForcaMaior>? itens;
  final bool falharListar;
  final ErroTrato? erroSolicitar;
  final envios = <(String, String, String, List<String>)>[];

  @override
  Future<List<EventoForcaMaior>?> listar(String pedidoId) async {
    if (falharListar) throw ErroTrato.servidor;
    return itens;
  }

  @override
  Future<EventoForcaMaior> solicitar(
    String pedidoId, {
    required String acaoSolicitada,
    required String descricao,
    List<String> comprovantes = const [],
  }) async {
    envios.add((pedidoId, acaoSolicitada, descricao, comprovantes));
    if (erroSolicitar != null) throw erroSolicitar!;
    return EventoForcaMaior(
      id: 'fm-novo',
      pedidoId: pedidoId,
      acaoSolicitada: acaoSolicitada,
      descricao: descricao,
      comprovantes: comprovantes,
      status: 'pendente',
      criadoEm: DateTime.utc(2026, 11, 28, 12),
    );
  }
}

Future<void> _abrir(
  WidgetTester t,
  ServicoForcaMaior servico, {
  bool pedidoAtivo = true,
}) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SecaoForcaMaior(
          servico: servico,
          pedidoId: 'ped-78',
          pedidoAtivo: pedidoAtivo,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('ServicoForcaMaiorApi: listar (200, 404, 503) e solicitar', () async {
    for (final codigo in [404, 503]) {
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((_) async => http.Response('{"detail":"nao disponivel"}', codigo)),
      );
      expect(await ServicoForcaMaiorApi(api).listar('ped-78'), isNull);
    }

    String? caminhoPost;
    Map<String, dynamic>? corpoPost;
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(jsonEncode([
              {
                'id': 'fm-1',
                'pedido_id': 'ped-78',
                'solicitante_id': 'cli-1',
                'solicitante_papel': 'cliente',
                'acao_solicitada': 'reagendar',
                'descricao': 'Enchente impediu o acesso ao endereço.',
                'comprovantes': ['https://exemplo/foto.jpg'],
                'status': 'aprovado',
                'criado_em': '2026-11-27T12:00:00Z',
                'justificativa_decisao': 'Comprovado pela defesa civil.',
                'decidido_em': '2026-11-27T15:00:00Z',
              }
            ])),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        caminhoPost = req.url.path;
        corpoPost = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'id': 'fm-2',
            'pedido_id': 'ped-78',
            'solicitante_id': 'cli-1',
            'solicitante_papel': 'cliente',
            'acao_solicitada': 'cancelar',
            'descricao': 'Queda de energia no bairro inteiro.',
            'comprovantes': <String>[],
            'status': 'pendente',
            'criado_em': '2026-11-28T10:00:00Z',
            'justificativa_decisao': null,
            'decidido_em': null,
          })),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final servico = ServicoForcaMaiorApi(api);
    final lista = await servico.listar('ped-78');
    expect(lista, hasLength(1));
    expect(lista!.first.status, 'aprovado');
    expect(lista.first.justificativaDecisao, 'Comprovado pela defesa civil.');

    final criado = await servico.solicitar(
      'ped-78',
      acaoSolicitada: 'cancelar',
      descricao: '  Queda de energia no bairro inteiro.  ',
    );
    expect(caminhoPost, '/v1/pedidos/ped-78/forca-maior');
    expect(corpoPost, {
      'acao_solicitada': 'cancelar',
      'descricao': 'Queda de energia no bairro inteiro.',
      'comprovantes': <String>[],
    });
    expect(criado.id, 'fm-2');
    expect(criado.status, 'pendente');
  });

  testWidgets('exibe solicitações existentes com justificativa e oculta botão se inativo',
      (t) async {
    final servico = _ServicoFake([
      _evento(
        acao: 'reagendar',
        status: 'aprovado',
        justificativa: 'Comprovado pela defesa civil.',
      ),
    ]);
    await _abrir(t, servico, pedidoAtivo: false);

    expect(find.byKey(const ValueKey('secao-forca-maior')), findsOneWidget);
    expect(find.text('Aprovado'), findsOneWidget);
    expect(find.text('Reagendar sem custo'), findsOneWidget);
    expect(find.text('Enchente impediu o acesso ao endereço combinado.'), findsOneWidget);
    expect(find.text('Comprovado pela defesa civil.'), findsOneWidget);
    expect(find.byKey(const ValueKey('alegar-forca-maior')), findsNothing);
  });

  testWidgets('abre modal, envia solicitação com comprovante opcional e atualiza lista', (t) async {
    final servico = _ServicoFake(const []);
    await _abrir(t, servico, pedidoAtivo: true);

    await t.tap(find.byKey(const ValueKey('alegar-forca-maior')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('opcao-forca-maior-cancelar')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('campo-descricao-forca-maior')),
      'Queda de árvore bloqueou a rua de acesso.',
    );
    await t.enterText(
      find.byKey(const ValueKey('campo-comprovante-forca-maior')),
      'https://exemplo.com/comprovante',
    );
    await t.tap(find.byKey(const ValueKey('enviar-forca-maior')));
    await t.pumpAndSettle();

    expect(servico.envios, hasLength(1));
    final envio = servico.envios.single;
    expect(envio.$1, 'ped-78');
    expect(envio.$2, 'cancelar');
    expect(envio.$3, 'Queda de árvore bloqueou a rua de acesso.');
    expect(envio.$4, ['https://exemplo.com/comprovante']);
    expect(find.text('Em análise'), findsOneWidget);
    expect(find.text('Cancelar sem multa'), findsOneWidget);
    expect(find.text('Queda de árvore bloqueou a rua de acesso.'), findsOneWidget);
  });

  testWidgets('valida descrição curta e trata erro do servidor preservando o texto digitado',
      (t) async {
    final servico = _ServicoFake(
      const [],
      erroSolicitar: const ErroTrato(
        TipoErro.recusado,
        'Já existe uma solicitação em análise para este pedido.',
        codigoHttp: 409,
      ),
    );
    await _abrir(t, servico, pedidoAtivo: true);

    await t.tap(find.byKey(const ValueKey('alegar-forca-maior')));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const ValueKey('campo-descricao-forca-maior')), 'Curto');
    await t.tap(find.byKey(const ValueKey('enviar-forca-maior')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('erro-forca-maior')), findsOneWidget);
    expect(servico.envios, isEmpty);

    const textoLongo = 'Tempestade forte interrompeu a energia elétrica na região.';
    await t.enterText(find.byKey(const ValueKey('campo-descricao-forca-maior')), textoLongo);
    await t.tap(find.byKey(const ValueKey('enviar-forca-maior')));
    await t.pumpAndSettle();

    expect(find.text('Já existe uma solicitação em análise para este pedido.'), findsOneWidget);
    final campo = t.widget<TextField>(find.byKey(const ValueKey('campo-descricao-forca-maior')));
    expect(campo.controller!.text, textoLongo);
  });

  testWidgets('fallback silencioso quando servidor é antigo (null) ou falha ao listar', (t) async {
    await _abrir(t, _ServicoFake(null), pedidoAtivo: true);
    expect(find.byKey(const ValueKey('secao-forca-maior')), findsNothing);

    await _abrir(t, _ServicoFake(const [], falharListar: true), pedidoAtivo: true);
    expect(find.byKey(const ValueKey('secao-forca-maior')), findsNothing);
    expect(t.takeException(), isNull);
  });
}
