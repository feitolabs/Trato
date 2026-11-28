import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/auditoria_texto.dart';
import 'package:trato_admin/telas/forca_maior_tela.dart';

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
    [for (final c in api.chamadasForcaMaior) if (c.$1 == acao) c.$2];

void main() {
  testWidgets('sem disputas_ver a seção não aparece nem carrega', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'financeiro', api: api);
    expect(find.byKey(const ValueKey('menu-forca_maior')), findsNothing);
    expect(api.chamadasForcaMaior, isEmpty);
  });

  testWidgets('quem só vê disputas (atendente_n2) lista mas não vê botão Decidir', (tester) async {
    await abrirPainel(tester, papel: 'atendente_n2', secao: 'forca_maior', altura: 1400);
    expect(_contem('ped-fm-1'), findsWidgets);
    expect(_contem('boletim-defesa-civil.pdf'), findsOneWidget);
    expect(find.text('Decidir'), findsNothing);
  });

  testWidgets('lista com filtros de status, data em Brasília e comprovantes', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'forca_maior', altura: 1600);
    expect(_contem(kAvisoForcaMaior), findsOneWidget);
    expect(find.text('Pendente'), findsOneWidget);
    expect(_contem('ped-fm-1'), findsWidgets);
    expect(_contem('27/11/2026 12:00 (horário de Brasília)'), findsOneWidget);
    expect(_contem('boletim-defesa-civil.pdf, foto-rua.jpg'), findsOneWidget);
    expect(find.text('Decidir'), findsOneWidget);
    expect(_chamadas(api, 'listar').last['status'], 'pendente');

    await _clicar(tester, find.text('Aprovados'));
    expect(_chamadas(api, 'listar').last['status'], 'aprovado');
    expect(_contem('ped-fm-2'), findsWidgets);
    expect(find.text('Decidir'), findsNothing);

    await _clicar(tester, find.text('Todos'));
    expect(_chamadas(api, 'listar').last['status'], isNull);
    expect(_contem('ped-fm-1'), findsWidgets);
    expect(_contem('ped-fm-2'), findsWidgets);
  });

  testWidgets('estados vazio e erro de carregamento', (tester) async {
    await abrirPainel(tester, papel: 'mediador', api: ApiFake(vazio: true), secao: 'forca_maior');
    expect(find.text('Nenhuma solicitação de força maior com esse filtro.'), findsOneWidget);
  });

  testWidgets('erro de carregamento mostra mensagem do servidor', (tester) async {
    await abrirPainel(tester, papel: 'mediador', api: ApiFake(erro: true), secao: 'forca_maior');
    expect(_contem('Não foi possível falar com o servidor.'), findsWidgets);
  });

  testWidgets('decidir gera nova chave após 403/409/422 preservando texto e conclui ao confirmar', (tester) async {
    final api = ApiFake()..falhaForcaMaior = const ErroApi('Acima da sua alçada.', status: 403);
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'forca_maior', altura: 1400);
    await _clicar(tester, find.text('Decidir'));

    await _clicar(tester, _noModal('Aprovar'));
    const just = 'Comprovante da Defesa Civil confirma alagamento no horário.';
    await _escrever(tester, 'Justificativa', just);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));
    expect(_contem('Acima da sua alçada.'), findsOneWidget);
    expect(find.text(just), findsOneWidget);
    final chave1 = _chamadas(api, 'decisao').last['chave_idempotencia'] as String;

    // 409 gera chave nova e mantém texto editável.
    api.falhaForcaMaior = const ErroApi('Solicitação já decidida.', status: 409);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));
    expect(_contem('Solicitação já decidida.'), findsOneWidget);
    expect(find.text(just), findsOneWidget);
    final chave2 = _chamadas(api, 'decisao').last['chave_idempotencia'] as String;
    expect(chave2, isNot(chave1));

    // Sucesso: permite trocar para Recusar e conclui.
    api.falhaForcaMaior = null;
    await _clicar(tester, _noModal('Recusar'));
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));
    final ultima = _chamadas(api, 'decisao').last;
    expect(ultima['decisao'], 'recusado');
    expect(ultima['justificativa'], just);
    expect(ultima['chave_idempotencia'], isNot(chave2));
    expect(find.text('Solicitação recusada.'), findsOneWidget);
  });

  testWidgets('decidir mantém mesma chave e trava decisão/justificativa após 503', (tester) async {
    final api = ApiFake()..falhaForcaMaior = const ErroApi('Tabela indisponível.', status: 503);
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'forca_maior', altura: 1400);
    await _clicar(tester, find.text('Decidir'));
    await _clicar(tester, _noModal('Aprovar'));
    const just = 'Evento externo comprovado por boletim oficial.';
    await _escrever(tester, 'Justificativa', just);
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));

    expect(_contem('Tabela indisponível.'), findsOneWidget);
    expect(_contem('Decisão e justificativa travadas.'), findsOneWidget);
    final chave1 = _chamadas(api, 'decisao').last['chave_idempotencia'] as String;

    // Reabrir o modal preserva chave, decisão e justificativa travadas.
    await _clicar(tester, _noModal('Cancelar').last);
    await _clicar(tester, find.text('Decidir'));
    expect(_contem('Decisão e justificativa travadas.'), findsOneWidget);
    expect(find.text(just), findsOneWidget);

    api
      ..falhaForcaMaior = null
      ..forcaMaiorIdempotente = true;
    await _clicar(tester, _noModal('Revisar'));
    await _clicar(tester, _noModal('Confirmar decisão'));
    expect(_chamadas(api, 'decisao').last['chave_idempotencia'], chave1);
    expect(_contem('Essa decisão já estava registrada'), findsOneWidget);
  });

  test('auditoria descreve forca_maior.decidido e inclui filtro', () {
    final entrada = EntradaAuditoria(
      id: 1,
      ocorridaEm: DateTime.utc(2026, 11, 28, 4, 30),
      ator: 'mediador@trato.local',
      acao: 'forca_maior.decidido',
      entidade: 'pedidos:ped-fm-1',
      entidadeNome: 'ped-fm-1',
      motivo: 'Evento confirmado.',
      detalhes: const {'decisao': 'aprovado'},
    );
    expect(
      descreverAcao(entrada),
      'decidiu solicitação de força maior do pedido ped-fm-1 (Aprovado)',
    );
    expect(filtrosDeAcao.any((f) => f.$1 == 'forca_maior.'), isTrue);
  });

  test('API HTTP: GET e POST /v1/admin/forca-maior com payload exato e tratamento de erro', () async {
    final pedidos = <http.Request>[];
    var status = 200;
    final item = {
      'id': 'fm-1',
      'pedido_id': 'ped-1',
      'solicitante_id': 'cli-1',
      'solicitante_papel': 'cliente',
      'acao_solicitada': 'cancelar',
      'descricao': 'Alagamento na via.',
      'comprovantes': ['doc.pdf'],
      'status': 'pendente',
      'criado_em': '2026-11-27T15:00:00+00:00',
      'analista_id': null,
      'justificativa_decisao': null,
      'decidido_em': null,
      'chave_idempotencia': null,
      'idempotente': false,
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
          return http.Response.bytes(utf8.encode('{"detail":"Acima da alçada."}'), status);
        }
        final Object corpo = r.method == 'GET' ? {'itens': [item], 'total': 1, 'limite': 20, 'deslocamento': 0} : item;
        return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200);
      }),
    );

    await api.entrar('m@teste.local', 'senha-de-teste');
    final pagina = await api.listarForcaMaior(status: 'pendente', deslocamento: 0, limite: 20);
    expect(pedidos.last.url.path, '/v1/admin/forca-maior');
    expect(pedidos.last.url.queryParameters, {'status': 'pendente', 'limite': '20', 'deslocamento': '0'});
    expect(pagina.total, 1);
    expect(pagina.itens.single.comprovantes, ['doc.pdf']);

    await api.decidirForcaMaior(
      'fm-1',
      decisao: 'aprovado',
      justificativa: 'Comprovante aceito para isenção.',
      chaveIdempotencia: 'fm-12345678',
    );
    expect(pedidos.last.url.path, '/v1/admin/forca-maior/fm-1/decisao');
    expect(jsonDecode(pedidos.last.body), {
      'decisao': 'aprovado',
      'justificativa': 'Comprovante aceito para isenção.',
      'chave_idempotencia': 'fm-12345678',
    });

    status = 403;
    await expectLater(
      api.decidirForcaMaior(
        'fm-1',
        decisao: 'aprovado',
        justificativa: 'Comprovante aceito para isenção.',
        chaveIdempotencia: 'fm-12345678',
      ),
      throwsA(isA<ErroApi>().having((e) => e.status, 'status', 403)),
    );
  });
}
