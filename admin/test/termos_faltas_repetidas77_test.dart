import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato_admin/dados/api_http.dart';
import 'package:trato_admin/dados/modelos.dart';
import 'package:trato_admin/nucleo/papeis.dart';
import 'package:trato_admin/telas/faltas_repetidas_tela.dart';

import 'ajuda.dart';
import 'apoio/api_fake.dart';

Finder _contem(String texto) => find.textContaining(texto, findRichText: true);

Future<void> _clicar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  test('só atendente_n2, lider_suporte, mediador e administrador têm disputas_ver', () {
    expect(
      {for (final p in Papel.values) if (p.pode(Permissao.disputasVer)) p},
      {Papel.atendenteN2, Papel.liderSuporte, Papel.mediador, Papel.administrador},
    );
  });

  testWidgets('sem disputas_ver a seção não aparece nem carrega', (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'financeiro', api: api);
    expect(find.byKey(const ValueKey('menu-faltas_repetidas')), findsNothing);
    expect(api.chamadasFaltasRepetidas, isEmpty);
  });

  testWidgets('lista profissionais com total, data em Brasília e responde aos filtros de período e mínimo',
      (tester) async {
    final api = ApiFake();
    await abrirPainel(tester, papel: 'lider_suporte', api: api, secao: 'faltas_repetidas', altura: 1400);

    expect(_contem(kAvisoFaltasRepetidas), findsOneWidget);
    expect(_contem('pro-falta-1'), findsWidgets);
    expect(_contem('pro-falta-2'), findsWidgets);
    expect(find.text('5 cancelamento(s)'), findsOneWidget);
    expect(find.text('2 cancelamento(s)'), findsOneWidget);
    expect(_contem('27/11/2026 12:00 (horário de Brasília)'), findsOneWidget);
    expect(api.chamadasFaltasRepetidas.last, {'dias': 90, 'minimo': 2});

    // Muda período para 30 dias e mínimo para 5 ou mais.
    await _clicar(tester, find.text('Últimos 30 dias'));
    expect(api.chamadasFaltasRepetidas.last, {'dias': 30, 'minimo': 2});

    await _clicar(tester, find.text('5 ou mais'));
    expect(api.chamadasFaltasRepetidas.last, {'dias': 30, 'minimo': 5});
    expect(_contem('pro-falta-1'), findsWidgets);
    expect(_contem('pro-falta-2'), findsNothing);
  });

  testWidgets('estado vazio', (tester) async {
    await abrirPainel(tester, papel: 'mediador', api: ApiFake(vazio: true), secao: 'faltas_repetidas');
    expect(find.text('Nenhum profissional com faltas repetidas nesse filtro.'), findsOneWidget);
  });

  testWidgets('estado de erro mostra mensagem do servidor e permite tentar novamente', (tester) async {
    final api = ApiFake()..falhaFaltasRepetidas = const ErroApi('Sem permissão para esta consulta.', status: 403);
    await abrirPainel(tester, papel: 'mediador', api: api, secao: 'faltas_repetidas');
    expect(_contem('Sem permissão para esta consulta.'), findsOneWidget);

    api.falhaFaltasRepetidas = null;
    await _clicar(tester, find.text('Tentar novamente'));
    expect(_contem('pro-falta-1'), findsWidgets);
  });

  test('API HTTP: GET /v1/admin/profissionais/faltas-repetidas com query params e erro 403', () async {
    final pedidos = <http.Request>[];
    var status = 200;
    final item = {
      'profissional_id': 'pro-99',
      'total_cancelamentos': 4,
      'ultimo_cancelamento_em': '2026-11-27T15:00:00+00:00',
      'periodo_dias': 30,
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
          return http.Response.bytes(utf8.encode('{"detail":"Acesso negado."}'), status);
        }
        return http.Response.bytes(utf8.encode(jsonEncode([item])), 200);
      }),
    );

    await api.entrar('m@teste.local', 'senha-de-teste');
    final lista = await api.listarFaltasRepetidas(dias: 30, minimo: 3);
    expect(pedidos.last.url.path, '/v1/admin/profissionais/faltas-repetidas');
    expect(pedidos.last.url.queryParameters, {'dias': '30', 'minimo': '3'});
    expect(lista.single.profissionalId, 'pro-99');
    expect(lista.single.totalCancelamentos, 4);
    expect(lista.single.periodoDias, 30);

    status = 403;
    await expectLater(
      api.listarFaltasRepetidas(),
      throwsA(isA<ErroApi>().having((e) => e.status, 'status', 403)),
    );
  });
}
