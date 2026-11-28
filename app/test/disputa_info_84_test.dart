// Termos 8.4: pedidos de informação adicional na disputa (exibição, resposta e notificação).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/erros.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/disputa_acordo/pedidos_info.dart';
import 'package:trato/telas/disputa_acordo/secao_pedidos_info.dart';
import 'package:trato/telas/fluxo/deep_link_modelo.dart';
import 'package:trato/telas/fluxo/rotas.dart';
import 'package:trato/telas/notificacoes/modelos.dart';
import 'package:trato/telas/notificacoes/servico_repositorio.dart';
import 'package:trato/tema/tema.dart';

PedidoInfoDisputa _item({
  String id = 'pi-1',
  String destinatario = 'cliente',
  String status = 'aguardando_resposta',
  String mensagem = 'Envie foto da nota fiscal.',
  String? respostaTexto,
}) =>
    PedidoInfoDisputa(
      id: id,
      disputaId: 'disp-1',
      pedidoId: 'ped-84',
      destinatarioPapel: destinatario,
      mensagem: mensagem,
      status: status,
      solicitadoEm: DateTime.utc(2026, 11, 20, 12),
      responderAte: DateTime.utc(2026, 12, 4, 23, 59),
      respostaTexto: respostaTexto,
    );

class _ServicoFake implements ServicoPedidosInfoDisputa {
  _ServicoFake(this.itens, {this.falharListar = false});

  final List<PedidoInfoDisputa> itens;
  final bool falharListar;
  final envios = <(String, String, String)>[];

  @override
  Future<List<PedidoInfoDisputa>> listar(String disputaOuPedidoId) async {
    if (falharListar) throw ErroTrato.servidor;
    return itens;
  }

  @override
  Future<PedidoInfoDisputa> responder(
    String disputaOuPedidoId,
    String pedidoInfoId,
    String respostaTexto,
  ) async {
    envios.add((disputaOuPedidoId, pedidoInfoId, respostaTexto));
    final atual = itens.firstWhere((e) => e.id == pedidoInfoId);
    return PedidoInfoDisputa(
      id: atual.id,
      disputaId: atual.disputaId,
      pedidoId: atual.pedidoId,
      destinatarioPapel: atual.destinatarioPapel,
      mensagem: atual.mensagem,
      status: 'respondido',
      solicitadoEm: atual.solicitadoEm,
      responderAte: atual.responderAte,
      respondidoEm: DateTime.utc(2026, 11, 28, 12),
      respostaTexto: respostaTexto,
    );
  }
}

Future<void> _abrir(
  WidgetTester t,
  ServicoPedidosInfoDisputa servico, {
  required bool profissional,
}) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: TemaTrato.claro,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SecaoPedidosInfoDisputa(
          servico: servico,
          disputaOuPedidoId: 'ped-84',
          profissional: profissional,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('ServicoPedidosInfoDisputaApi: listar (200, 404, 503) e responder', () async {
    for (final codigo in [404, 503]) {
      final api = ClienteApi(
        urlBase: 'https://api.teste',
        sessao: SessaoTrato()..entrar('t'),
        cliente: MockClient((_) async => http.Response('{"detail":"nao disponivel"}', codigo)),
      );
      expect(await ServicoPedidosInfoDisputaApi(api).listar('disp-1'), isEmpty);
    }

    String? corpoEnviado;
    String? caminhoPost;
    final api = ClienteApi(
      urlBase: 'https://api.teste',
      sessao: SessaoTrato()..entrar('t'),
      cliente: MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(jsonEncode([
              {
                'id': 'pi-1',
                'disputa_id': 'disp-1',
                'pedido_id': 'ped-84',
                'destinatario_papel': 'cliente',
                'mensagem': 'Envie foto da nota fiscal.',
                'solicitado_em': '2026-11-20T12:00:00Z',
                'responder_ate': '2026-12-04T23:59:59Z',
                'respondido_em': null,
                'resposta_texto': null,
                'encerrado_sem_resposta_em': null,
                'status': 'aguardando_resposta',
              }
            ])),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        caminhoPost = req.url.path;
        corpoEnviado = req.body;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'id': 'pi-1',
            'disputa_id': 'disp-1',
            'pedido_id': 'ped-84',
            'destinatario_papel': 'cliente',
            'mensagem': 'Envie foto da nota fiscal.',
            'solicitado_em': '2026-11-20T12:00:00Z',
            'responder_ate': '2026-12-04T23:59:59Z',
            'respondido_em': '2026-11-28T12:00:00Z',
            'resposta_texto': 'Nota enviada no chat.',
            'encerrado_sem_resposta_em': null,
            'status': 'respondido',
          })),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final servico = ServicoPedidosInfoDisputaApi(api);
    final lista = await servico.listar('disp-1');
    expect(lista, hasLength(1));
    expect(lista.first.status, 'aguardando_resposta');
    expect(lista.first.destinatarioPapel, 'cliente');

    final resp = await servico.responder('disp-1', 'pi-1', '  Nota enviada no chat.  ');
    expect(caminhoPost, '/v1/disputas/disp-1/pedidos-informacao/pi-1/responder');
    expect(jsonDecode(corpoEnviado!), {'resposta_texto': 'Nota enviada no chat.'});
    expect(resp.status, 'respondido');
    expect(resp.respostaTexto, 'Nota enviada no chat.');
  });

  testWidgets('destinatário certo vê campo, valida vazio e envia resposta', (t) async {
    final servico = _ServicoFake([_item(destinatario: 'cliente', status: 'aguardando_resposta')]);
    await _abrir(t, servico, profissional: false);

    expect(find.byKey(const ValueKey('secao-pedidos-info')), findsOneWidget);
    expect(find.text('Envie foto da nota fiscal.'), findsOneWidget);
    expect(find.textContaining('Prazo:'), findsOneWidget);
    expect(find.text('Aguardando resposta'), findsOneWidget);
    expect(find.byKey(const ValueKey('campo-resposta-info-pi-1')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('enviar-resposta-info-pi-1')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('erro-resposta-info-pi-1')), findsOneWidget);
    expect(servico.envios, isEmpty);

    await t.enterText(
      find.byKey(const ValueKey('campo-resposta-info-pi-1')),
      'Seguem os detalhes pedidos.',
    );
    await t.tap(find.byKey(const ValueKey('enviar-resposta-info-pi-1')));
    await t.pumpAndSettle();

    expect(servico.envios, [('disp-1', 'pi-1', 'Seguem os detalhes pedidos.')]);
    expect(find.text('Respondido'), findsOneWidget);
    expect(find.text('Seguem os detalhes pedidos.'), findsOneWidget);
    expect(find.byKey(const ValueKey('campo-resposta-info-pi-1')), findsNothing);
  });

  testWidgets('destinatário profissional também responde quando status é vencido', (t) async {
    final servico = _ServicoFake([_item(destinatario: 'profissional', status: 'vencido')]);
    await _abrir(t, servico, profissional: true);

    expect(find.text('Prazo vencido'), findsOneWidget);
    expect(find.byKey(const ValueKey('campo-resposta-info-pi-1')), findsOneWidget);
    expect(find.text('Enviar resposta'), findsOneWidget);
  });

  testWidgets('outra parte vê o pedido mas NÃO vê campo nem botão de resposta', (t) async {
    final paraCliente = _ServicoFake([_item(destinatario: 'cliente')]);
    await _abrir(t, paraCliente, profissional: true);
    expect(find.text('Envie foto da nota fiscal.'), findsOneWidget);
    expect(find.byKey(const ValueKey('campo-resposta-info-pi-1')), findsNothing);
    expect(find.text('Enviar resposta'), findsNothing);

    final paraProf = _ServicoFake([_item(destinatario: 'profissional')]);
    await _abrir(t, paraProf, profissional: false);
    expect(find.text('Envie foto da nota fiscal.'), findsOneWidget);
    expect(find.byKey(const ValueKey('campo-resposta-info-pi-1')), findsNothing);
    expect(find.text('Enviar resposta'), findsNothing);
  });

  testWidgets('fallback silencioso em lista vazia ou erro ao carregar', (t) async {
    await _abrir(t, _ServicoFake(const []), profissional: false);
    expect(find.byKey(const ValueKey('secao-pedidos-info')), findsNothing);

    await _abrir(t, _ServicoFake(const [], falharListar: true), profissional: false);
    expect(find.byKey(const ValueKey('secao-pedidos-info')), findsNothing);
    expect(t.takeException(), isNull);
  });

  test('notificação disputa.pedido_informacao abre a disputa (push e caixa)', () {
    expect(
      resultadoDoPush({
        'evento': 'disputa.pedido_informacao',
        'tela': 'disputa',
        'pedido_id': 'ped-84',
        'papel': 'cliente',
      }),
      const ResultadoLink.valido(DestinoApp.disputa, 'ped-84', papel: 'cliente'),
    );
    final avisoCaixa = Notificacao(
      id: 'n-info',
      tipo: tipoDaNotificacao('disputa.pedido_informacao'),
      tipoApi: 'disputa.pedido_informacao',
      destinoId: 'ped-84',
      papel: 'profissional',
      titulo: 'Pedido de informação',
      texto: 'A equipe pediu mais detalhes.',
      quando: 'agora',
    );
    expect(
      RotasTrato.destinoDaCaixa(avisoCaixa, modoAtualProfissional: false),
      const ResultadoLink.valido(DestinoApp.disputa, 'ped-84', papel: 'profissional'),
    );
  });
}
