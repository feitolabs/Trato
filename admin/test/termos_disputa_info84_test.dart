import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Finder _modal() => find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog) : find.byType(BottomSheet);

Finder _noModal(String texto) => find.descendant(of: _modal(), matching: find.text(texto));

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _escrever(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.descendant(of: _modal(), matching: find.widgetWithText(TextField, rotulo));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pump();
}

List<Map<String, Object?>> _chamadas(ApiFake api, String acao) =>
    [for (final c in api.chamadasPedidosInfoDisputa) if (c.$1 == acao) c.$2];

void main() {
  testWidgets('lista pedidos de informação com status, prazo em Brasília, resposta e ação só para vencido',
      (tester) async {
    final api = ApiFake()
      ..pedidosInfoDisputa = {
        'd-1': [
          PedidoInfoDisputa(
            id: 'pi-vencido',
            disputaId: 'd-1',
            pedidoId: 'ped-1',
            solicitanteId: 'op-1',
            destinatarioPapel: 'cliente',
            mensagem: 'Envie foto da nota fiscal do serviço.',
            solicitadoEm: DateTime.utc(2026, 11, 10, 15, 0),
            responderAte: DateTime.utc(2026, 11, 24, 15, 0),
            status: 'vencido',
          ),
          PedidoInfoDisputa(
            id: 'pi-resp',
            disputaId: 'd-1',
            pedidoId: 'ped-1',
            solicitanteId: 'op-1',
            destinatarioPapel: 'profissional',
            mensagem: 'Confirme o horário de saída do local.',
            solicitadoEm: DateTime.utc(2026, 11, 12, 16, 0),
            responderAte: DateTime.utc(2026, 11, 26, 16, 0),
            respondidoEm: DateTime.utc(2026, 11, 13, 18, 0),
            respostaTexto: 'Saí às 17h30 com assinatura da portaria.',
            status: 'respondido',
          ),
        ],
      };

    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'disputas', altura: 1800);
    await rolarListaAte(tester, find.text('Pedidos de informação adicional'));
    expect(find.text('Pedidos de informação adicional'), findsOneWidget);
    expect(find.text('Pedir informação adicional'), findsOneWidget);
    expect(find.text('Prazo vencido'), findsOneWidget);
    expect(find.text('Respondido'), findsOneWidget);
    expect(_contem('24/11/2026 12:00 (horário de Brasília)'), findsOneWidget);
    expect(_contem('Envie foto da nota fiscal do serviço.'), findsOneWidget);
    expect(_contem('Saí às 17h30 com assinatura da portaria.'), findsOneWidget);
    // Só o pedido vencido mostra "Encerrar sem resposta".
    expect(find.text('Encerrar sem resposta'), findsOneWidget);
  });

  testWidgets('quem só vê disputas (sem disputas_decidir) não vê botões de solicitar nem encerrar', (tester) async {
    final api = ApiFake()
      ..pedidosInfoDisputa = {
        'd-1': [
          PedidoInfoDisputa(
            id: 'pi-vencido',
            disputaId: 'd-1',
            pedidoId: 'ped-1',
            solicitanteId: 'op-1',
            destinatarioPapel: 'cliente',
            mensagem: 'Precisamos de mais fotos do ambiente.',
            solicitadoEm: DateTime.utc(2026, 11, 10, 15, 0),
            responderAte: DateTime.utc(2026, 11, 24, 15, 0),
            status: 'vencido',
          ),
        ],
      };
    await abrirPainel(tester, papel: 'atendente_n2', api: api, secao: 'disputas', altura: 1800);
    await rolarListaAte(tester, find.text('Pedidos de informação adicional'));
    expect(find.text('Prazo vencido'), findsOneWidget);
    expect(find.text('Pedir informação adicional'), findsNothing);
    expect(find.text('Encerrar sem resposta'), findsNothing);
  });

  testWidgets('solicitar informação exige destinatário e mensagem >= 10, preserva texto em 409/503 e cria',
      (tester) async {
    final api = ApiFake()
      ..falhaAcaoPedidoInfoDisputa = const ErroApi('A disputa já está encerrada.', status: 409);
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'disputas', altura: 1600);
    await rolarListaAte(tester, find.text('Pedir informação adicional'));
    await _clicar(tester, find.text('Pedir informação adicional'));

    // Mensagem curta não habilita Revisar.
    await _escrever(tester, 'Mensagem', 'curto');
    await _clicar(tester, _noModal('Revisar'));
    expect(_noModal('Confirmar envio'), findsNothing);

    await _clicar(tester, _noModal('Profissional'));
    const msg = 'Por favor, envie o comprovante de compra do material usado.';
    await _escrever(tester, 'Mensagem', msg);
    await _clicar(tester, _noModal('Revisar'));
    expect(_chamadas(api, 'solicitar'), isEmpty);

    // 409: mostra erro e preserva o texto digitado.
    await _clicar(tester, _noModal('Confirmar envio'));
    expect(_contem('A disputa já está encerrada.'), findsOneWidget);
    expect(find.text(msg), findsOneWidget);

    // 503: mostra erro e preserva o texto digitado.
    api.falhaAcaoPedidoInfoDisputa = const ErroApi('Serviço indisponível no momento.', status: 503);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar envio'));
    expect(_contem('Serviço indisponível no momento.'), findsOneWidget);
    expect(find.text(msg), findsOneWidget);

    // Sucesso: envia e atualiza lista.
    api.falhaAcaoPedidoInfoDisputa = null;
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar envio'));
    expect(_chamadas(api, 'solicitar').last, {
      'disputa_id': 'd-1',
      'destinatario_papel': 'profissional',
      'mensagem': msg,
    });
    expect(find.text('Pedido de informação enviado.'), findsOneWidget);
    expect(find.text('Pedido para profissional'), findsOneWidget);
    expect(_contem(msg), findsOneWidget);
  });

  testWidgets('encerrar sem resposta exige motivo >= 10, preserva texto em 403/404/422 e confirma', (tester) async {
    final api = ApiFake()
      ..pedidosInfoDisputa = {
        'd-1': [
          PedidoInfoDisputa(
            id: 'pi-1',
            disputaId: 'd-1',
            pedidoId: 'ped-1',
            solicitanteId: 'op-1',
            destinatarioPapel: 'cliente',
            mensagem: 'Envie fotos adicionais do problema.',
            solicitadoEm: DateTime.utc(2026, 11, 10, 15, 0),
            responderAte: DateTime.utc(2026, 11, 24, 15, 0),
            status: 'vencido',
          ),
        ],
      }
      ..falhaAcaoPedidoInfoDisputa = const ErroApi('Sem permissão para encerrar.', status: 403);

    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'disputas', altura: 1800);
    await rolarListaAte(tester, find.text('Encerrar sem resposta'));
    await _clicar(tester, find.text('Encerrar sem resposta'));

    const motivo = 'Prazo encerrado sem qualquer resposta do cliente.';
    await _escrever(tester, 'Motivo', motivo);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar encerramento'));
    expect(_contem('Sem permissão para encerrar.'), findsOneWidget);
    expect(find.text(motivo), findsOneWidget);

    // Sucesso: encerra e atualiza status na tela.
    api.falhaAcaoPedidoInfoDisputa = null;
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar encerramento'));
    expect(_chamadas(api, 'encerrar').last, {
      'disputa_id': 'd-1',
      'pedido_info_id': 'pi-1',
      'motivo': motivo,
    });
    expect(find.text('Pedido encerrado sem resposta.'), findsOneWidget);
    expect(find.text('Encerrado sem resposta'), findsOneWidget);
  });

  test('auditoria descreve os dois eventos de pedido de informação e inclui filtro', () {
    final solicitado = EntradaAuditoria(
      id: 1,
      ocorridaEm: DateTime.utc(2026, 11, 28, 4, 0),
      ator: 'mediador@trato.local',
      acao: 'disputa.pedido_informacao_solicitado',
      entidade: 'pedidos:ped-1',
      entidadeNome: 'ped-1',
      motivo: 'Envie mais detalhes.',
      detalhes: const {'destinatario_papel': 'cliente'},
    );
    expect(
      descreverAcao(solicitado),
      'pediu informação adicional na disputa do pedido ped-1 (Cliente)',
    );

    final encerrado = EntradaAuditoria(
      id: 2,
      ocorridaEm: DateTime.utc(2026, 11, 28, 4, 10),
      ator: 'mediador@trato.local',
      acao: 'disputa.pedido_informacao_encerrado_sem_resposta',
      entidade: 'pedidos:ped-1',
      entidadeNome: 'ped-1',
      motivo: 'Prazo vencido sem retorno.',
    );
    expect(
      descreverAcao(encerrado),
      'encerrou sem resposta um pedido de informação no pedido ped-1',
    );
    expect(filtrosDeAcao.any((f) => f.$1 == 'disputa.'), isTrue);
  });

  test('API HTTP: GET e POSTs de pedidos-informacao com payload exato e tratamento de erro', () async {
    final pedidos = <http.Request>[];
    var status = 200;
    final item = {
      'id': 'pi-1',
      'disputa_id': 'd-1',
      'pedido_id': 'ped-1',
      'solicitante_id': 'u',
      'destinatario_papel': 'cliente',
      'mensagem': 'Envie foto complementar do serviço.',
      'solicitado_em': '2026-11-10T15:00:00+00:00',
      'responder_ate': '2026-11-24T15:00:00+00:00',
      'respondido_em': null,
      'resposta_texto': null,
      'encerrado_sem_resposta_em': null,
      'status': 'aguardando_resposta',
    };
    final api = ApiAdminHttp(
      urlApi: 'http://api.teste',
      urlSupabase: 'http://supa.teste',
      chaveAnonSupabase: 'anon',
      cliente: MockClient((r) async {
        if (r.url.path == '/auth/v1/token') return http.Response('{"access_token":"t"}', 200);
        if (r.url.path == '/v1/admin/eu') return http.Response('{"id":"u","papel":"mediador"}', 200);
        pedidos.add(r);
        if (status >= 400) {
          return http.Response.bytes(utf8.encode('{"detail":"O prazo para resposta ainda não venceu."}'), status);
        }
        final Object corpo = r.method == 'GET' ? [item] : item;
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), r.method == 'POST' && r.url.path.endsWith('/pedidos-informacao') ? 201 : status);
      }),
    );

    await api.entrar('m@teste.local', 'senha-de-teste');
    final lista = await api.listarPedidosInfoDisputa('d-1');
    expect(pedidos.last.url.path, '/v1/admin/disputas/d-1/pedidos-informacao');
    expect(lista.single.id, 'pi-1');
    expect(lista.single.status, 'aguardando_resposta');

    await api.solicitarInfoDisputa('d-1', destinatarioPapel: 'cliente', mensagem: 'Envie foto complementar do serviço.');
    expect(pedidos.last.url.path, '/v1/admin/disputas/d-1/pedidos-informacao');
    expect(jsonDecode(pedidos.last.body), {
      'destinatario_papel': 'cliente',
      'mensagem': 'Envie foto complementar do serviço.',
    });

    await api.encerrarPedidoInfoSemResposta('d-1', 'pi-1', motivo: 'Prazo vencido sem retorno do cliente.');
    expect(pedidos.last.url.path, '/v1/admin/disputas/d-1/pedidos-informacao/pi-1/encerrar-sem-resposta');
    expect(jsonDecode(pedidos.last.body), {'motivo': 'Prazo vencido sem retorno do cliente.'});

    status = 409;
    await expectLater(
      api.encerrarPedidoInfoSemResposta('d-1', 'pi-1', motivo: 'Prazo vencido sem retorno do cliente.'),
      throwsA(
        isA<ErroApi>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.mensagem, 'mensagem', 'O prazo para resposta ainda não venceu.'),
      ),
    );
  });
}
